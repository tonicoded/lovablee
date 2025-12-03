-- lovablee shared schema helpers
create extension if not exists pgcrypto;

-- deterministic pairing codes for partners
create or replace function public.generate_pairing_code()
returns text
language plpgsql
as $$
declare
    candidate text;
begin
    loop
        candidate := upper(encode(gen_random_bytes(4), 'hex'));
        exit when not exists (
            select 1 from public.users where pairing_code = candidate
        );
    end loop;
    return candidate;
end;
$$;

-- 1. User profile table (stores Apple + APNs info + pairing metadata)
create table if not exists public.users (
    id uuid primary key references auth.users (id) on delete cascade,
    email text,
    apple_identifier text not null,
    display_name text,
    partner_id uuid references public.users (id) on delete set null,
    partner_display_name text,
    pairing_code text not null default public.generate_pairing_code(),
    apns_token text,
    updated_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists users_apple_identifier_key
    on public.users (apple_identifier);

create unique index if not exists users_pairing_code_key
    on public.users (pairing_code);

create or replace function public.set_users_timestamp()
returns trigger language plpgsql as $$
begin
    new.updated_at := timezone('utc', now());
    return new;
end;
$$;

drop trigger if exists set_users_timestamp on public.users;
create trigger set_users_timestamp
before insert or update on public.users
for each row execute function public.set_users_timestamp();

alter table public.users enable row level security;

drop policy if exists "Users can select their row" on public.users;
drop policy if exists "Users can insert their row" on public.users;
drop policy if exists "Users can update their row" on public.users;
drop policy if exists "Users can delete their row" on public.users;

create policy "Users can select their row"
    on public.users for select using (auth.uid() = id);

create policy "Users can insert their row"
    on public.users for insert with check (auth.uid() = id);

create policy "Users can update their row"
    on public.users for update using (auth.uid() = id);

create policy "Users can delete their row"
    on public.users for delete using (auth.uid() = id);

create or replace function public.join_partner(p_pairing_code text)
returns public.users
language plpgsql
security definer
set search_path = public
as $$
declare
    target public.users%rowtype;
    me public.users%rowtype;
    normalized text;
begin
    normalized := upper(trim(p_pairing_code));
    select * into target from public.users where pairing_code = normalized limit 1;
    if target.id is null then
        raise exception 'invalid_pairing_code';
    end if;
    if target.id = auth.uid() then
        raise exception 'cannot_join_self';
    end if;

    update public.users
    set partner_id = target.id,
        partner_display_name = target.display_name
    where id = auth.uid()
    returning * into me;

    update public.users
    set partner_id = me.id,
        partner_display_name = me.display_name
    where id = target.id;

    return me;
end;
$$;

grant execute on function public.join_partner(text) to authenticated;

create or replace function public.leave_partner()
returns public.users
language plpgsql
security definer
set search_path = public
as $$
declare
    me public.users%rowtype;
    partner_row public.users%rowtype;
begin
    select * into me from public.users where id = auth.uid();
    if me.partner_id is null then
        return me;
    end if;

    select * into partner_row from public.users where id = me.partner_id limit 1;

    update public.users
    set partner_id = null,
        partner_display_name = null
    where id = me.id
    returning * into me;

    if partner_row.id is not null then
        update public.users
        set partner_id = null,
            partner_display_name = null
        where id = partner_row.id;
    end if;

    return me;
end;
$$;

grant execute on function public.leave_partner() to authenticated;

-- 2. Cozy pet state per couple
create table if not exists public.pet_status (
    user_id uuid primary key references public.users (id) on delete cascade,
    pet_name text not null default 'Bubba',
    mood text not null default 'Sleepy',
    hydration_level integer not null default 60,
    playfulness_level integer not null default 55,
    hearts integer not null default 0,
    streak_count integer not null default 0,
    last_active_date date,
    last_watered_at timestamptz,
    last_played_at timestamptz,
    last_note_sent_at timestamptz,
    last_doodle_created_at timestamptz,
    adopted_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
);

create or replace function public.set_pet_status_timestamp()
returns trigger language plpgsql as $$
begin
    new.updated_at := timezone('utc', now());
    return new;
end;
$$;

drop trigger if exists set_pet_status_timestamp on public.pet_status;
create trigger set_pet_status_timestamp
before insert or update on public.pet_status
for each row execute function public.set_pet_status_timestamp();

alter table public.pet_status enable row level security;

drop policy if exists "Users can read pet status" on public.pet_status;
drop policy if exists "Users can write pet status" on public.pet_status;

create policy "Users can read pet status"
    on public.pet_status for select using (auth.uid() = user_id);

create policy "Users can write pet status"
    on public.pet_status for all using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Shared couple progress (hearts + streak)
create table if not exists public.couple_progress (
    couple_key text primary key,
    hearts integer not null default 0,
    streak_count integer not null default 0,
    last_active_date date,
    updated_at timestamptz not null default timezone('utc', now())
);

create or replace function public.set_couple_progress_timestamp()
returns trigger language plpgsql as $$
begin
    new.updated_at := timezone('utc', now());
    return new;
end;
$$;

drop trigger if exists set_couple_progress_timestamp on public.couple_progress;
create trigger set_couple_progress_timestamp
before insert or update on public.couple_progress
for each row execute function public.set_couple_progress_timestamp();

alter table public.couple_progress enable row level security;

drop policy if exists "Users can read couple progress" on public.couple_progress;
drop policy if exists "Users can write couple progress" on public.couple_progress;

create policy "Users can read couple progress"
    on public.couple_progress for select using (
        exists (
            select 1
            from public.users u
            left join public.users partner on partner.id = u.partner_id
            where u.id = auth.uid()
              and couple_key = case
                  when partner.pairing_code is null then u.pairing_code
                  when u.pairing_code <= partner.pairing_code then u.pairing_code
                  else partner.pairing_code
              end
        )
    );

create policy "Users can write couple progress"
    on public.couple_progress for all using (
        exists (
            select 1
            from public.users u
            left join public.users partner on partner.id = u.partner_id
            where u.id = auth.uid()
              and couple_key = case
                  when partner.pairing_code is null then u.pairing_code
                  when u.pairing_code <= partner.pairing_code then u.pairing_code
                  else partner.pairing_code
              end
        )
    ) with check (
        exists (
            select 1
            from public.users u
            left join public.users partner on partner.id = u.partner_id
            where u.id = auth.uid()
              and couple_key = case
                  when partner.pairing_code is null then u.pairing_code
                  when u.pairing_code <= partner.pairing_code then u.pairing_code
                  else partner.pairing_code
              end
        )
    );

-- Activity feed per couple (water/play events)
create table if not exists public.couple_activity (
    id uuid primary key default gen_random_uuid(),
    couple_key text not null,
    actor_id uuid not null references public.users (id) on delete cascade,
    actor_name text,
    action_type text not null,
    pet_name text,
    created_at timestamptz not null default timezone('utc', now())
);

alter table public.couple_activity enable row level security;

drop policy if exists "Couple can read activity" on public.couple_activity;
drop policy if exists "Users write their activity" on public.couple_activity;

create policy "Couple can read activity"
    on public.couple_activity for select using (
        exists (
            select 1
            from public.users u
            left join public.users partner on partner.id = u.partner_id
            where u.id = auth.uid()
              and couple_key = case
                  when partner.pairing_code is null then u.pairing_code
                  when u.pairing_code <= partner.pairing_code then u.pairing_code
                  else partner.pairing_code
              end
        )
    );

create policy "Users write their activity"
    on public.couple_activity for insert with check (
        actor_id = auth.uid()
        and exists (
            select 1
            from public.users u
            left join public.users partner on partner.id = u.partner_id
            where u.id = auth.uid()
              and couple_key = case
                  when partner.pairing_code is null then u.pairing_code
                  when u.pairing_code <= partner.pairing_code then u.pairing_code
                  else partner.pairing_code
              end
        )
    );

create or replace function public.compute_pet_mood(hydration integer, playful integer)
returns text
language sql
as $$
    select case
        when hydration >= 80 and playful >= 80 then 'Joyful'
        when hydration < 35 and playful < 35 then 'Needy'
        when hydration < 35 then 'Thirsty'
        when playful < 35 then 'Restless'
        else 'Content'
    end;
$$;

grant execute on function public.compute_pet_mood(integer, integer) to postgres, service_role, authenticated;

create or replace function public.ensure_pet_status()
returns public.pet_status
language plpgsql
security definer
set search_path = public
as $$
declare
    current_status public.pet_status%rowtype;
begin
    if auth.uid() is null then
        raise exception 'auth.uid is required';
    end if;

    insert into public.pet_status (user_id)
    values (auth.uid())
    on conflict (user_id) do nothing;

    select * into current_status
    from public.pet_status
    where user_id = auth.uid();

    return current_status;
end;
$$;

grant execute on function public.ensure_pet_status() to authenticated;

create or replace function public.refresh_pet_status()
returns public.pet_status
language plpgsql
security definer
set search_path = public
as $$
declare
    current_status public.pet_status%rowtype;
    partner_status public.pet_status%rowtype;
    base_status public.pet_status%rowtype;
    couple_row public.couple_progress%rowtype;
    now_utc timestamptz := timezone('utc', now());
    hours_since_update numeric;
    hydration_decay integer;
    play_decay integer;
    next_hydration integer;
    next_play integer;
    partner_user_id uuid;
    my_pairing_code text;
    partner_pairing_code text;
    v_couple_key text;
begin
    current_status := public.ensure_pet_status();

    select partner_id, pairing_code into partner_user_id, my_pairing_code from public.users where id = auth.uid();
    if partner_user_id = auth.uid() then
        partner_user_id := null;
    end if;
    if partner_user_id is not null then
        select pairing_code into partner_pairing_code from public.users where id = partner_user_id;
        select * into partner_status from public.pet_status where user_id = partner_user_id;
    end if;

    if partner_pairing_code is null then
        v_couple_key := my_pairing_code;
    elsif my_pairing_code is null then
        v_couple_key := partner_pairing_code;
    else
        v_couple_key := case
            when my_pairing_code <= partner_pairing_code then my_pairing_code
            else partner_pairing_code
        end;
    end if;
    if v_couple_key is not null then
        insert into public.couple_progress (couple_key)
        values (v_couple_key)
        on conflict (couple_key) do nothing;

        select * into couple_row from public.couple_progress where couple_key = v_couple_key;
    end if;

    base_status := current_status;
    if partner_status.updated_at is not null and (current_status.updated_at is null or partner_status.updated_at > current_status.updated_at) then
        base_status := partner_status;
    end if;

    if couple_row.couple_key is not null then
        base_status.hearts := coalesce(couple_row.hearts, base_status.hearts);
        base_status.streak_count := coalesce(couple_row.streak_count, base_status.streak_count);
        base_status.last_active_date := coalesce(couple_row.last_active_date, base_status.last_active_date);
    end if;

    if base_status.user_id is null then
        return base_status;
    end if;

    if base_status.updated_at is null then
        return base_status;
    end if;

    hours_since_update := greatest(
        0,
        extract(epoch from now_utc - base_status.updated_at) / 3600
    );

    if hours_since_update <= 0 then
        return base_status;
    end if;

    hydration_decay := floor(hours_since_update * 3);
    play_decay := floor(hours_since_update * 4);

    if hydration_decay <= 0 and play_decay <= 0 then
        return base_status;
    end if;

    next_hydration := greatest(0, coalesce(base_status.hydration_level, 0) - hydration_decay);
    next_play := greatest(0, coalesce(base_status.playfulness_level, 0) - play_decay);

    update public.pet_status
    set hydration_level = next_hydration,
        playfulness_level = next_play,
        mood = public.compute_pet_mood(next_hydration, next_play),
        updated_at = now_utc
    where user_id = base_status.user_id
    returning * into current_status;

    if partner_user_id is not null then
        insert into public.pet_status (user_id) values (partner_user_id)
        on conflict (user_id) do nothing;

        update public.pet_status
        set hydration_level = next_hydration,
            playfulness_level = next_play,
            mood = public.compute_pet_mood(next_hydration, next_play),
            pet_name = base_status.pet_name,
            last_watered_at = base_status.last_watered_at,
            last_played_at = base_status.last_played_at,
            updated_at = now_utc
        where user_id = partner_user_id;
    end if;

    if couple_row.couple_key is not null then
        current_status.hearts := coalesce(couple_row.hearts, 0);
        current_status.streak_count := coalesce(couple_row.streak_count, 0);
        current_status.last_active_date := couple_row.last_active_date;
    end if;

    return current_status;
end;
$$;

grant execute on function public.refresh_pet_status() to authenticated;

create or replace function public.get_pet_status()
returns public.pet_status
language plpgsql
security definer
set search_path = public
as $$
begin
    return public.refresh_pet_status();
end;
$$;

grant execute on function public.get_pet_status() to authenticated;

create or replace function public.get_couple_activity(p_limit integer default 50)
returns setof public.couple_activity
language plpgsql
security definer
set search_path = public
as $$
declare
    partner_user_id uuid;
    my_pairing_code text;
    partner_pairing_code text;
    v_couple_key text;
    safe_limit integer := greatest(1, coalesce(p_limit, 50));
begin
    select partner_id, pairing_code into partner_user_id, my_pairing_code from public.users where id = auth.uid();
    if partner_user_id = auth.uid() then
        partner_user_id := null;
    end if;
    if partner_user_id is not null then
        select pairing_code into partner_pairing_code from public.users where id = partner_user_id;
    end if;

    if partner_pairing_code is null then
        v_couple_key := my_pairing_code;
    elsif my_pairing_code is null then
        v_couple_key := partner_pairing_code;
    else
        v_couple_key := case
            when my_pairing_code <= partner_pairing_code then my_pairing_code
            else partner_pairing_code
        end;
    end if;

    if v_couple_key is null then
        return;
    end if;

    return query
    select *
    from public.couple_activity
    where couple_key = v_couple_key
    order by created_at desc
    limit safe_limit;
end;
$$;

grant execute on function public.get_couple_activity(integer) to authenticated;

create or replace function public.record_pet_action(action_type text)
returns public.pet_status
language plpgsql
security definer
set search_path = public
as $$
declare
    updated_status public.pet_status%rowtype;
    now_utc timestamptz := timezone('utc', now());
    water_cooldown interval := interval '1 hour';
    play_cooldown interval := interval '15 minutes';
    today date := timezone('utc', now())::date;
    hearts_reward integer := 5;
    new_hearts integer;
    new_streak integer;
    last_active date;
    partner_user_id uuid;
    v_couple_key text;
    couple_row public.couple_progress%rowtype;
    my_pairing_code text;
    partner_pairing_code text;
    source_hearts integer;
    source_streak integer;
    source_last_active date;
    partner_status public.pet_status%rowtype;
    base_status public.pet_status%rowtype;
    new_hydration integer;
    new_play integer;
    actor_name text;
    pet_label text;
begin
    select partner_id, pairing_code into partner_user_id, my_pairing_code from public.users where id = auth.uid();
    if partner_user_id = auth.uid() then
        partner_user_id := null;
    end if;

    if partner_user_id is not null then
        select pairing_code into partner_pairing_code from public.users where id = partner_user_id;
    end if;

    if partner_pairing_code is null then
        v_couple_key := my_pairing_code;
    elsif my_pairing_code is null then
        v_couple_key := partner_pairing_code;
    else
        v_couple_key := case
            when my_pairing_code <= partner_pairing_code then my_pairing_code
            else partner_pairing_code
        end;
    end if;

    insert into public.couple_progress (couple_key)
    values (v_couple_key)
    on conflict (couple_key) do nothing;

    select * into couple_row from public.couple_progress where couple_key = v_couple_key;

    if coalesce(couple_row.hearts, 0) = 0 and coalesce(couple_row.streak_count, 0) = 0 then
        select coalesce(max(hearts), 0),
               coalesce(max(streak_count), 0),
               max(last_active_date)
        into source_hearts, source_streak, source_last_active
        from public.couple_progress
        where couple_key in (
            my_pairing_code,
            partner_pairing_code
        );

        update public.couple_progress
        set hearts = greatest(couple_row.hearts, source_hearts),
            streak_count = greatest(couple_row.streak_count, source_streak),
            last_active_date = coalesce(source_last_active, couple_row.last_active_date)
        where couple_key = v_couple_key;

        select * into couple_row from public.couple_progress where couple_key = v_couple_key;
    end if;

    -- Fetch pet status for both partners and pick the freshest
    select * into updated_status from public.pet_status where user_id = auth.uid();
    if partner_user_id is not null then
        select * into partner_status from public.pet_status where user_id = partner_user_id;
    end if;

    base_status := updated_status;
    if partner_status.updated_at is not null and (updated_status.updated_at is null or partner_status.updated_at > updated_status.updated_at) then
        base_status := partner_status;
    end if;
    if base_status.user_id is null then
        base_status := updated_status;
    end if;
    pet_label := coalesce(base_status.pet_name, 'Bubba');
    select display_name into actor_name from public.users where id = auth.uid();

    last_active := couple_row.last_active_date;
    if last_active = today then
        new_streak := coalesce(couple_row.streak_count, 0);
    elsif last_active = (today - 1) then
        new_streak := coalesce(couple_row.streak_count, 0) + 1;
    else
        new_streak := 1;
    end if;
    new_hearts := coalesce(couple_row.hearts, 0) + hearts_reward;

    update public.couple_progress
    set hearts = new_hearts,
        streak_count = new_streak,
        last_active_date = today
    where couple_key = v_couple_key
    returning * into couple_row;

    updated_status.hearts := couple_row.hearts;
    updated_status.streak_count := couple_row.streak_count;
    updated_status.last_active_date := couple_row.last_active_date;

    if action_type = 'water' then
        if base_status.last_watered_at is not null
            and now_utc - base_status.last_watered_at < water_cooldown then
            raise exception 'pet_action_cooldown'
                using detail = 'water';
        end if;

        new_hydration := least(100, coalesce(base_status.hydration_level, 0) + 20);
        new_play := greatest(0, coalesce(base_status.playfulness_level, 0) - 4);

        update public.pet_status
        set hydration_level = new_hydration,
            playfulness_level = new_play,
            last_watered_at = now_utc,
            mood = public.compute_pet_mood(new_hydration, new_play),
            updated_at = now_utc
        where user_id = auth.uid()
        returning * into updated_status;

        updated_status.hearts := couple_row.hearts;
        updated_status.streak_count := couple_row.streak_count;
        updated_status.last_active_date := couple_row.last_active_date;

        if partner_user_id is not null then
            insert into public.pet_status (user_id) values (partner_user_id)
            on conflict (user_id) do nothing;

            update public.pet_status
            set hydration_level = new_hydration,
                playfulness_level = new_play,
                last_watered_at = now_utc,
                mood = public.compute_pet_mood(new_hydration, new_play),
                pet_name = base_status.pet_name,
                updated_at = now_utc
            where user_id = partner_user_id;
        end if;
    elsif action_type = 'play' then
        if base_status.last_played_at is not null
            and now_utc - base_status.last_played_at < play_cooldown then
            raise exception 'pet_action_cooldown'
                using detail = 'play';
        end if;

        new_play := least(100, coalesce(base_status.playfulness_level, 0) + 22);
        new_hydration := greatest(0, coalesce(base_status.hydration_level, 0) - 6);

        update public.pet_status
        set playfulness_level = new_play,
            hydration_level = new_hydration,
            last_played_at = now_utc,
            mood = public.compute_pet_mood(new_hydration, new_play),
            updated_at = now_utc
        where user_id = auth.uid()
        returning * into updated_status;

        updated_status.hearts := couple_row.hearts;
        updated_status.streak_count := couple_row.streak_count;
        updated_status.last_active_date := couple_row.last_active_date;

        if partner_user_id is not null then
            insert into public.pet_status (user_id) values (partner_user_id)
            on conflict (user_id) do nothing;

            update public.pet_status
            set playfulness_level = new_play,
                hydration_level = new_hydration,
                last_played_at = now_utc,
                mood = public.compute_pet_mood(new_hydration, new_play),
                pet_name = base_status.pet_name,
                updated_at = now_utc
            where user_id = partner_user_id;
        end if;
    else
        raise exception 'unknown_pet_action';
    end if;

    if v_couple_key is not null then
        insert into public.couple_activity (couple_key, actor_id, actor_name, action_type, pet_name)
        values (v_couple_key, auth.uid(), actor_name, action_type, pet_label);
    end if;

    return updated_status;
end;
$$;

grant execute on function public.record_pet_action(text) to authenticated;

-- Love Notes table for couple messages
create table if not exists public.love_notes (
    id uuid primary key default gen_random_uuid(),
    couple_key text not null,
    sender_id uuid not null references public.users (id) on delete cascade,
    sender_name text not null,
    message text not null,
    is_read boolean not null default false,
    created_at timestamptz not null default timezone('utc', now())
);

create index if not exists love_notes_couple_key_idx on public.love_notes (couple_key, created_at desc);
create index if not exists love_notes_sender_idx on public.love_notes (sender_id);

alter table public.love_notes enable row level security;

drop policy if exists "Couple can read love notes" on public.love_notes;
drop policy if exists "Users can send love notes" on public.love_notes;

create policy "Couple can read love notes"
    on public.love_notes for select using (
        exists (
            select 1
            from public.users u
            left join public.users partner on partner.id = u.partner_id
            where u.id = auth.uid()
              and couple_key = case
                  when partner.pairing_code is null then u.pairing_code
                  when u.pairing_code <= partner.pairing_code then u.pairing_code
                  else partner.pairing_code
              end
        )
    );

create policy "Users can send love notes"
    on public.love_notes for insert with check (
        sender_id = auth.uid()
        and exists (
            select 1
            from public.users u
            left join public.users partner on partner.id = u.partner_id
            where u.id = auth.uid()
              and couple_key = case
                  when partner.pairing_code is null then u.pairing_code
                  when u.pairing_code <= partner.pairing_code then u.pairing_code
                  else partner.pairing_code
              end
        )
    );

create or replace function public.send_love_note(p_message text)
returns public.love_notes
language plpgsql
security definer
set search_path = public
as $$
declare
    partner_user_id uuid;
    my_pairing_code text;
    partner_pairing_code text;
    v_couple_key text;
    sender_display_name text;
    new_note public.love_notes%rowtype;
begin
    select partner_id, pairing_code, display_name
    into partner_user_id, my_pairing_code, sender_display_name
    from public.users where id = auth.uid();

    if partner_user_id is null then
        raise exception 'no_partner';
    end if;

    if partner_user_id = auth.uid() then
        raise exception 'cannot_send_to_self';
    end if;

    select pairing_code into partner_pairing_code
    from public.users where id = partner_user_id;

    if partner_pairing_code is null then
        v_couple_key := my_pairing_code;
    elsif my_pairing_code is null then
        v_couple_key := partner_pairing_code;
    else
        v_couple_key := case
            when my_pairing_code <= partner_pairing_code then my_pairing_code
            else partner_pairing_code
        end;
    end if;

    insert into public.love_notes (couple_key, sender_id, sender_name, message)
    values (v_couple_key, auth.uid(), coalesce(sender_display_name, 'Someone'), p_message)
    returning * into new_note;

    -- Send push notification to partner
    if partner_user_id is not null then
        perform public.send_test_push(
            partner_user_id,
            '💌 ' || coalesce(sender_display_name, 'Someone') || ' sent you a love note',
            left(p_message, 100),
            jsonb_build_object('type', 'love_note', 'note_id', new_note.id)
        );
    end if;

    return new_note;
end;
$$;

grant execute on function public.send_love_note(text) to authenticated;

create or replace function public.get_love_notes(p_limit integer default 50)
returns setof public.love_notes
language plpgsql
security definer
set search_path = public
as $$
declare
    partner_user_id uuid;
    my_pairing_code text;
    partner_pairing_code text;
    v_couple_key text;
    safe_limit integer := greatest(1, coalesce(p_limit, 50));
begin
    select partner_id, pairing_code into partner_user_id, my_pairing_code
    from public.users where id = auth.uid();

    if partner_user_id = auth.uid() then
        partner_user_id := null;
    end if;

    if partner_user_id is not null then
        select pairing_code into partner_pairing_code
        from public.users where id = partner_user_id;
    end if;

    if partner_pairing_code is null then
        v_couple_key := my_pairing_code;
    elsif my_pairing_code is null then
        v_couple_key := partner_pairing_code;
    else
        v_couple_key := case
            when my_pairing_code <= partner_pairing_code then my_pairing_code
            else partner_pairing_code
        end;
    end if;

    if v_couple_key is null then
        return;
    end if;

    return query
    select *
    from public.love_notes
    where couple_key = v_couple_key
    order by created_at desc
    limit safe_limit;
end;
$$;

grant execute on function public.get_love_notes(integer) to authenticated;

-- ============================================================================
-- DOODLES FEATURE
-- ============================================================================

-- 1. Doodles table to store drawing metadata
create table if not exists public.doodles (
    id uuid primary key default gen_random_uuid(),
    couple_key text not null,
    sender_id uuid not null references public.users (id) on delete cascade,
    sender_name text not null,
    storage_path text,
    content text,
    is_viewed boolean not null default false,
    created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_doodles_couple_key on public.doodles (couple_key);
create index if not exists idx_doodles_sender_id on public.doodles (sender_id);
create index if not exists idx_doodles_created_at on public.doodles (created_at desc);

alter table public.doodles enable row level security;

drop policy if exists "Users can view doodles in their couple" on public.doodles;
create policy "Users can view doodles in their couple"
    on public.doodles for select using (
        exists (
            select 1
            from public.users u
            left join public.users partner on partner.id = u.partner_id
            where u.id = auth.uid()
              and couple_key = case
                  when partner.pairing_code is null then u.pairing_code
                  when u.pairing_code <= partner.pairing_code then u.pairing_code
                  else partner.pairing_code
              end
        )
    );

drop policy if exists "Users can insert doodles" on public.doodles;
create policy "Users can insert doodles"
    on public.doodles for insert with check (
        sender_id = auth.uid()
        and exists (
            select 1
            from public.users u
            left join public.users partner on partner.id = u.partner_id
            where u.id = auth.uid()
              and couple_key = case
                  when partner.pairing_code is null then u.pairing_code
                  when u.pairing_code <= partner.pairing_code then u.pairing_code
                  else partner.pairing_code
              end
        )
    );

-- 2. Function to save a doodle with base64 content
create or replace function public.save_doodle(
    p_content text default null,
    p_storage_path text default null
)
returns public.doodles
language plpgsql
security definer
set search_path = public
as $$
declare
    partner_user_id uuid;
    my_pairing_code text;
    partner_pairing_code text;
    v_couple_key text;
    sender_display_name text;
    new_doodle public.doodles%rowtype;
begin
    select partner_id, pairing_code, display_name
    into partner_user_id, my_pairing_code, sender_display_name
    from public.users where id = auth.uid();

    if partner_user_id is null then
        raise exception 'no_partner';
    end if;

    if partner_user_id = auth.uid() then
        raise exception 'cannot_send_to_self';
    end if;

    select pairing_code into partner_pairing_code
    from public.users where id = partner_user_id;

    if partner_pairing_code is null then
        v_couple_key := my_pairing_code;
    elsif my_pairing_code is null then
        v_couple_key := partner_pairing_code;
    else
        v_couple_key := case
            when my_pairing_code <= partner_pairing_code then my_pairing_code
            else partner_pairing_code
        end;
    end if;

    insert into public.doodles (couple_key, sender_id, sender_name, storage_path, content)
    values (v_couple_key, auth.uid(), coalesce(sender_display_name, 'Someone'), p_storage_path, p_content)
    returning * into new_doodle;

    -- Send push notification to partner
    if partner_user_id is not null then
        perform public.send_test_push(
            partner_user_id,
            '🎨 ' || coalesce(sender_display_name, 'Someone') || ' sent you a doodle',
            'Check it out in the gallery!',
            jsonb_build_object('type', 'doodle', 'doodle_id', new_doodle.id)
        );
    end if;

    return new_doodle;
end;
$$;

grant execute on function public.save_doodle(text, text) to authenticated;

-- 3. Function to get doodles for the current user's couple
create or replace function public.get_doodles(p_limit integer default 50)
returns setof public.doodles
language plpgsql
security definer
set search_path = public
as $$
declare
    partner_user_id uuid;
    my_pairing_code text;
    partner_pairing_code text;
    v_couple_key text;
    safe_limit integer := greatest(1, coalesce(p_limit, 50));
begin
    select partner_id, pairing_code into partner_user_id, my_pairing_code
    from public.users where id = auth.uid();

    if partner_user_id = auth.uid() then
        partner_user_id := null;
    end if;

    if partner_user_id is not null then
        select pairing_code into partner_pairing_code
        from public.users where id = partner_user_id;
    end if;

    if partner_pairing_code is null then
        v_couple_key := my_pairing_code;
    elsif my_pairing_code is null then
        v_couple_key := partner_pairing_code;
    else
        v_couple_key := case
            when my_pairing_code <= partner_pairing_code then my_pairing_code
            else partner_pairing_code
        end;
    end if;

    if v_couple_key is null then
        return;
    end if;

    return query
    select *
    from public.doodles
    where couple_key = v_couple_key
    order by created_at desc
    limit safe_limit;
end;
$$;

grant execute on function public.get_doodles(integer) to authenticated;

-- 3. Storage bucket + policies for profile photos
insert into storage.buckets (id, name, public)
values ('storage', 'storage', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "Public read profile photos" on storage.objects;
drop policy if exists "Users upload profile photos" on storage.objects;
drop policy if exists "Users update profile photos" on storage.objects;
drop policy if exists "Users delete profile photos" on storage.objects;

create policy "Public read profile photos"
    on storage.objects for select
    using (bucket_id = 'storage');

create policy "Users upload profile photos"
    on storage.objects for insert
    with check (bucket_id = 'storage' and auth.uid() = owner);

create policy "Users update profile photos"
    on storage.objects for update
    using (bucket_id = 'storage' and auth.uid() = owner);

create policy "Users delete profile photos"
    on storage.objects for delete
    using (bucket_id = 'storage' and auth.uid() = owner);

-- 4. Simple secret store for the service-role key
create table if not exists public.internal_secrets (
    name text primary key,
    value text not null
);

revoke all on public.internal_secrets from public;
grant select, insert, update, delete on public.internal_secrets to postgres, service_role;

insert into public.internal_secrets (name, value)
values (
    'edge_service_key',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFodGtxY2F4ZXljeHZ3bnRqY3hwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDUwMjcwNCwiZXhwIjoyMDgwMDc4NzA0fQ.6qFuTZvTQOrd5Mo76F4rBVDRJDX1kmhVqgpX8b7CMMI'
)
on conflict (name) do update set value = excluded.value;

create or replace function public.get_internal_secret(secret_name text)
returns text
language sql
security definer
set search_path = public
as $$
    select value from public.internal_secrets where name = secret_name;
$$;

-- 5. pg_net helper + RPC to call the Edge Function
create extension if not exists pg_net schema extensions;

create or replace function public.send_test_push(
    target_user uuid,
    title text,
    body text,
    extra jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    service_key text := public.get_internal_secret('edge_service_key');
    endpoint text := 'https://ahtkqcaxeycxvwntjcxp.functions.supabase.co/send-push';
    response jsonb;
begin
    if service_key is null then
        raise exception 'edge_service_key secret missing';
    end if;

    response := net.http_post(
        url := endpoint,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || service_key
        ),
        body := jsonb_build_object(
            'targetUserId', target_user,
            'title', title,
            'body', body,
            'payload', extra
        )
    );

    return response;
end;
$$;

-- 6. Fire a test push (replace UUID with your user ID)
select public.send_test_push(
    '1908b6a6-1da4-4a65-862e-ee073b9e1e38',
    'lovablee ping',
    'SQL triggered push',
    '{}'::jsonb
);
