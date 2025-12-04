-- Migration: Add mood check-in feature
-- Run this entire file in Supabase SQL Editor

-- 1) Table to store daily moods per user
create table if not exists public.user_moods (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.users (id) on delete cascade,
    mood_key text not null,
    emoji text,
    label text,
    mood_date date not null,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now()),
    unique (user_id, mood_date)
);

create or replace function public.set_user_moods_timestamp()
returns trigger language plpgsql as $$
begin
    new.updated_at := timezone('utc', now());
    return new;
end;
$$;

drop trigger if exists set_user_moods_timestamp on public.user_moods;
create trigger set_user_moods_timestamp
before insert or update on public.user_moods
for each row execute function public.set_user_moods_timestamp();

alter table public.user_moods enable row level security;

drop policy if exists "Couple can read moods" on public.user_moods;
drop policy if exists "User can upsert own mood" on public.user_moods;

create policy "Couple can read moods"
    on public.user_moods for select using (
        user_id = auth.uid() or
        user_id in (
            select partner_id from public.users where id = auth.uid()
        )
    );

create policy "User can upsert own mood"
    on public.user_moods for all using (user_id = auth.uid())
    with check (user_id = auth.uid());

create index if not exists idx_user_moods_user_date on public.user_moods (user_id, mood_date);

-- 2) RPC: set daily mood (local date provided by client)
create or replace function public.set_mood(
    p_mood_key text,
    p_emoji text,
    p_label text,
    p_local_date date
)
returns public.user_moods
language plpgsql
security definer
set search_path = public
as $$
declare
    new_mood public.user_moods%rowtype;
begin
    if p_local_date is null then
        raise exception 'mood_date_required';
    end if;

    insert into public.user_moods (user_id, mood_key, emoji, label, mood_date)
    values (auth.uid(), p_mood_key, p_emoji, p_label, p_local_date)
    on conflict (user_id, mood_date) do update
        set mood_key = excluded.mood_key,
            emoji = excluded.emoji,
            label = excluded.label
    returning * into new_mood;

    return new_mood;
end;
$$;

-- 3) RPC: load today's moods for user + partner
drop function if exists public.load_daily_moods(date);
create or replace function public.load_daily_moods(p_local_date date)
returns table (
    my_mood jsonb,
    partner_mood jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
    partner_user_id uuid;
begin
    select partner_id into partner_user_id from public.users where id = auth.uid();

    return query
    select
        (select to_jsonb(m) from public.user_moods m where m.user_id = auth.uid() and m.mood_date = p_local_date),
        (select to_jsonb(m) from public.user_moods m where m.user_id = partner_user_id and m.mood_date = p_local_date);
end;
$$;

-- 4) Grants
grant select, insert, update on public.user_moods to authenticated;
grant execute on function public.set_mood(text, text, text, date) to authenticated, service_role;
grant execute on function public.load_daily_moods(date) to authenticated, service_role;
