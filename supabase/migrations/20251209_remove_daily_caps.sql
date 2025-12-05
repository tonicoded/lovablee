-- Roll back daily caps: restore original cooldown-only behavior.

-- Love notes: 1-hour cooldown, no per-day cap.
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
    v_last_note_sent_at timestamptz;
    v_cooldown_hours int := 1;
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

    select last_note_sent_at into v_last_note_sent_at
    from public.pet_status where user_id = auth.uid();

    if v_last_note_sent_at is not null
       and v_last_note_sent_at > (now() - (v_cooldown_hours || ' hours')::interval) then
        raise exception 'cooldown_active';
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

    update public.couple_progress
       set hearts = hearts + 10
     where couple_key = v_couple_key;

    update public.pet_status
       set last_note_sent_at = now()
     where user_id = auth.uid();

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

-- Doodles: 15-minute cooldown, no per-day cap.
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
    v_last_doodle_created_at timestamptz;
    v_cooldown_minutes int := 15;
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

    select last_doodle_created_at into v_last_doodle_created_at
    from public.pet_status where user_id = auth.uid();

    if v_last_doodle_created_at is not null
       and v_last_doodle_created_at > (now() - (v_cooldown_minutes || ' minutes')::interval) then
        raise exception 'cooldown_active';
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

    update public.couple_progress
       set hearts = hearts + 10
     where couple_key = v_couple_key;

    update public.pet_status
       set last_doodle_created_at = now()
     where user_id = auth.uid();

    if partner_user_id is not null then
        perform public.send_test_push(
            partner_user_id,
            coalesce(sender_display_name, 'Someone') || ' just shared a doodle',
            'Open your space to see it',
            jsonb_build_object('type', 'doodle', 'doodle_id', new_doodle.id)
        );
    end if;

    return new_doodle;
end;
$$;

grant execute on function public.save_doodle(text, text) to authenticated;
