-- Unified migration for couple-wide premium sharing and safe premium writes.
-- Run this once on Supabase to replace the earlier piecemeal scripts.

-- 1) Add premium tracking columns on users.
alter table public.users
    add column if not exists premium_until timestamptz,
    add column if not exists premium_source uuid;

-- 2) RPC to set the caller's premium status safely (no missing WHERE).
drop function if exists public.set_premium_status(timestamptz, uuid);
create or replace function public.set_premium_status(
    p_premium_until timestamptz,
    p_premium_source uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    update public.users
       set premium_until = p_premium_until,
           premium_source = coalesce(p_premium_source, auth.uid())
     where id = auth.uid();
end;
$$;

grant execute on function public.set_premium_status(timestamptz, uuid) to authenticated;

-- 3) Function that computes couple-level premium (either partner can grant).
create or replace function public.get_couple_premium()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    me public.users%rowtype;
    partner_row public.users%rowtype;
    my_entitled_until timestamptz;
    partner_entitled_until timestamptz;
    shared_from_partner_until timestamptz;
    best_until timestamptz;
    granted_to uuid;
begin
    select * into me from public.users where id = auth.uid();
    if me.id is null then
        raise exception 'auth.uid missing';
    end if;

    if me.partner_id is not null then
        select * into partner_row from public.users where id = me.partner_id;
    end if;

    -- My own premium (only if it's mine, not inherited).
    if me.premium_until is not null
       and me.premium_until > now()
       and (me.premium_source is null or me.premium_source = me.id) then
        my_entitled_until := me.premium_until;
    end if;

    -- Partner premium (only if it belongs to partner).
    if partner_row.id is not null
       and partner_row.premium_until is not null
       and partner_row.premium_until > now()
       and (partner_row.premium_source is null or partner_row.premium_source = partner_row.id) then
        partner_entitled_until := partner_row.premium_until;
    end if;

    -- Shared premium from partner.
    if partner_entitled_until is not null and me.partner_id is not null then
        shared_from_partner_until := partner_entitled_until;
    end if;

    -- Pick the best entitlement.
    best_until := greatest(
        coalesce(my_entitled_until, '-infinity'::timestamptz),
        coalesce(shared_from_partner_until, '-infinity'::timestamptz)
    );
    if best_until = '-infinity'::timestamptz then
        best_until := null;
    end if;

    if best_until is not null then
        if my_entitled_until = best_until then
            granted_to := me.id;
        elsif shared_from_partner_until = best_until then
            granted_to := partner_row.id;
        end if;
    end if;

    return jsonb_build_object(
        'is_premium', best_until is not null and best_until > now(),
        'premium_until', best_until,
        'granted_to', granted_to,
        'partner_id', partner_row.id
    );
end;
$$;

grant execute on function public.get_couple_premium() to authenticated;

-- 4) Thin wrapper for client RPC.
create or replace function public.get_couple_premium_status()
returns jsonb
language sql
security definer
set search_path = public
as $$
    select public.get_couple_premium();
$$;

grant execute on function public.get_couple_premium_status() to authenticated;
