-- Partner cleanup and resilient leave behavior.

-- 1) Trigger: when a user is deleted, clear partner links on the remaining user.
create or replace function public.detach_partner_on_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    update public.users
       set partner_id = null,
           partner_display_name = null
     where partner_id = old.id;
    return old;
end;
$$;

drop trigger if exists trg_detach_partner_on_delete on public.users;
create trigger trg_detach_partner_on_delete
before delete on public.users
for each row execute function public.detach_partner_on_delete();

-- 2) RPC: leave_partner that always clears both sides, even if partner is missing.
drop function if exists public.leave_partner();
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

    -- Clear my partner link.
    update public.users
       set partner_id = null,
           partner_display_name = null
     where id = me.id
     returning * into me;

    -- Clear partner's link if they still exist.
    if partner_row.id is not null then
        update public.users
           set partner_id = null,
               partner_display_name = null
         where id = partner_row.id
         returning * into partner_row;
    end if;

    return me;
end;
$$;

grant execute on function public.leave_partner() to authenticated;
