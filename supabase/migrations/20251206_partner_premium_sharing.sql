-- Share premium with partner and keep inherited premium cleanups in sync.

-- 1) Expand set_premium_status to mirror premium to your partner without
--    overriding a partner's own purchase. Clears shared premium when unset.
create or replace function public.set_premium_status(
    p_premium_until timestamptz,
    p_premium_source uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me public.users%rowtype;
    partner_row public.users%rowtype;
    new_source uuid;
begin
    select * into me from public.users where id = auth.uid();
    if me.id is null then
        raise exception 'auth.uid missing';
    end if;

    new_source := coalesce(p_premium_source, me.id);

    update public.users
       set premium_until = p_premium_until,
           premium_source = new_source
     where id = me.id
     returning * into me;

    if me.partner_id is not null then
        select * into partner_row from public.users where id = me.partner_id;

        if partner_row.id is not null then
            if p_premium_until is null then
                -- Remove shared premium granted by me.
                update public.users
                   set premium_until = null,
                       premium_source = null
                 where id = partner_row.id
                   and premium_source = me.id;
            else
                -- Mirror my entitlement to partner unless they own a better one.
                update public.users
                   set premium_until = greatest(p_premium_until, coalesce(premium_until, '-infinity'::timestamptz)),
                       premium_source = case
                           when premium_until is null or premium_until < p_premium_until then new_source
                           else premium_source
                       end
                 where id = partner_row.id
                   and (premium_source is null or premium_source = me.id or premium_source <> partner_row.id);
            end if;
        end if;
    end if;
end;
$$;

grant execute on function public.set_premium_status(timestamptz, uuid) to authenticated;

-- 2) Clean up inherited premium when leaving a partner.
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

    -- Clear my partner link and any premium inherited from them.
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

    -- Clear partner's link and any premium I granted them.
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

-- 3) Clear shared premium when a user is deleted.
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
