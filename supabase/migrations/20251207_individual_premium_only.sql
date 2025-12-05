-- Enforce individual premium (no sharing between partners).
-- This overrides prior sharing logic and cleans up inherited premium data.

-- Ensure premium_source is a uuid (handles older text column).
alter table public.users
    alter column premium_source type uuid using premium_source::uuid;

update public.users
   set premium_until = null,
       premium_source = null
 where premium_source is not null
   and premium_source <> id;

-- 2) Simplify set_premium_status to only affect the caller.
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

-- 3) Couple premium now reflects only the caller's own premium.
create or replace function public.get_couple_premium()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    me public.users%rowtype;
    my_entitled_until timestamptz;
begin
    select * into me from public.users where id = auth.uid();
    if me.id is null then
        raise exception 'auth.uid missing';
    end if;

    if me.premium_until is not null
       and me.premium_until > now()
       and (me.premium_source is null or me.premium_source = me.id) then
        my_entitled_until := me.premium_until;
    end if;

    return jsonb_build_object(
        'is_premium', my_entitled_until is not null and my_entitled_until > now(),
        'premium_until', my_entitled_until,
        'granted_to', me.id,
        'partner_id', me.partner_id
    );
end;
$$;

grant execute on function public.get_couple_premium() to authenticated;

-- 4) Wrapper RPC.
create or replace function public.get_couple_premium_status()
returns jsonb
language sql
security definer
set search_path = public
as $$
    select public.get_couple_premium();
$$;

grant execute on function public.get_couple_premium_status() to authenticated;

-- 5) Leave partner: clear links and any legacy shared premium.
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
    if me.id is null then
        raise exception 'auth.uid missing';
    end if;

    if me.partner_id is not null then
        select * into partner_row from public.users where id = me.partner_id;
    end if;

    update public.users
       set partner_id = null,
           partner_display_name = null,
           premium_until = case
               when partner_row.id is not null and premium_source = partner_row.id then null
               else premium_until
           end,
           premium_source = case
               when partner_row.id is not null and premium_source = partner_row.id then null
               else premium_source
           end
     where id = me.id
     returning * into me;

    if partner_row.id is not null then
        update public.users
           set partner_id = null,
               partner_display_name = null,
               premium_until = case when premium_source = me.id then null else premium_until end,
               premium_source = case when premium_source = me.id then null else premium_source end
         where id = partner_row.id
         returning * into partner_row;
    end if;

    return me;
end;
$$;

grant execute on function public.leave_partner() to authenticated;

-- 6) Detach trigger also clears any premium that referenced the deleted user.
create or replace function public.detach_partner_on_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    update public.users
       set partner_id = null,
           partner_display_name = null,
           premium_until = case when premium_source = old.id then null else premium_until end,
           premium_source = case when premium_source = old.id then null else premium_source end
     where partner_id = old.id
        or premium_source = old.id;
    return old;
end;
$$;

drop trigger if exists trg_detach_partner_on_delete on public.users;
create trigger trg_detach_partner_on_delete
before delete on public.users
for each row execute function public.detach_partner_on_delete();
