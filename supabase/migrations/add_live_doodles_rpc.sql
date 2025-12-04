-- Live doodles RPC helpers to enforce canonical couple_key server-side

-- Compute canonical couple_key (matches RLS logic)
create or replace function public.get_couple_key()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    partner_row public.users%rowtype;
    me public.users%rowtype;
    v_key text;
begin
    select * into me from public.users where id = auth.uid();
    if me.id is null then
        raise exception 'auth.uid missing';
    end if;

    if me.partner_id is null then
        return me.pairing_code;
    end if;

    select * into partner_row from public.users where id = me.partner_id;

    if partner_row.pairing_code is null then
        v_key := me.pairing_code;
    elsif me.pairing_code <= partner_row.pairing_code then
        v_key := me.pairing_code;
    else
        v_key := partner_row.pairing_code;
    end if;

    return v_key;
end;
$$;

grant execute on function public.get_couple_key() to authenticated;

-- Publish live doodle with canonical couple_key
create or replace function public.publish_live_doodle(
    p_content_base64 text,
    p_sender_name text default null
)
returns public.live_doodles
language plpgsql
security definer
set search_path = public
as $$
declare
    v_key text;
    new_row public.live_doodles%rowtype;
begin
    v_key := public.get_couple_key();
    insert into public.live_doodles (couple_key, sender_id, sender_name, content_base64)
    values (v_key, auth.uid(), p_sender_name, p_content_base64)
    returning * into new_row;
    return new_row;
end;
$$;

grant execute on function public.publish_live_doodle(text, text) to authenticated;

-- Fetch latest partner live doodle for the couple (optionally exclude my own)
create or replace function public.fetch_latest_live_doodle(p_exclude_sender uuid default null)
returns public.live_doodles
language plpgsql
security definer
set search_path = public
as $$
declare
    v_key text;
    result_row public.live_doodles%rowtype;
begin
    v_key := public.get_couple_key();
    select *
    into result_row
    from public.live_doodles
    where couple_key = v_key
      and (p_exclude_sender is null or sender_id <> p_exclude_sender)
    order by created_at desc
    limit 1;
    return result_row;
end;
$$;

grant execute on function public.fetch_latest_live_doodle(uuid) to authenticated;
