-- RPC to set premium status for the current user (avoids WHERE-less PATCH issues).
create or replace function public.set_premium_status(
    p_premium_until timestamptz,
    p_premium_source uuid default null
)
returns public.users
language sql
security definer
set search_path = public
as $$
    update public.users
    set premium_until = p_premium_until,
        premium_source = p_premium_source,
        updated_at = timezone('utc', now())
    where id = auth.uid()
    returning *;
$$;

grant execute on function public.set_premium_status(timestamptz, uuid) to authenticated;
