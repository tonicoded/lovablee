-- Live doodle streaming (separate from saved doodles/gallery)
-- This is intentionally lightweight (no cooldown) and meant for short-lived lockscreen mirroring.

create table if not exists public.live_doodles (
    id uuid primary key default gen_random_uuid(),
    couple_key text not null,
    sender_id uuid not null references public.users (id) on delete cascade,
    sender_name text,
    content_base64 text not null, -- expected: data:image/png;base64,... or raw base64 png
    created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_live_doodles_couple_created
    on public.live_doodles (couple_key, created_at desc);

alter table public.live_doodles enable row level security;

-- Lock down default grants
revoke all on public.live_doodles from public;
revoke all on public.live_doodles from anon;
revoke all on public.live_doodles from authenticated;

-- Helpers to derive the canonical couple_key (same pattern used elsewhere)
drop policy if exists "Couple can read live doodles" on public.live_doodles;
create policy "Couple can read live doodles"
    on public.live_doodles
    for select using (
        exists (
            select 1 from public.users u
            left join public.users partner on partner.id = u.partner_id
            where u.id = auth.uid()
              and live_doodles.couple_key = case
                  when partner.pairing_code is null then u.pairing_code
                  when u.pairing_code <= partner.pairing_code then u.pairing_code
                  else partner.pairing_code
              end
        )
    );

drop policy if exists "User can publish live doodles" on public.live_doodles;
create policy "User can publish live doodles"
    on public.live_doodles
    for insert with check (
        sender_id = auth.uid()
        and exists (
            select 1 from public.users u
            left join public.users partner on partner.id = u.partner_id
            where u.id = auth.uid()
              and live_doodles.couple_key = case
                  when partner.pairing_code is null then u.pairing_code
                  when u.pairing_code <= partner.pairing_code then u.pairing_code
                  else partner.pairing_code
              end
        )
    );

-- Explicitly deny update/delete by policy (default deny under RLS, but keep explicit)
drop policy if exists "No updates on live doodles" on public.live_doodles;
create policy "No updates on live doodles"
    on public.live_doodles
    for update using (false) with check (false);

drop policy if exists "No deletes on live doodles" on public.live_doodles;
create policy "No deletes on live doodles"
    on public.live_doodles
    for delete using (false);

grant select, insert on public.live_doodles to authenticated;

-- Optional cleanup helper: delete entries older than 30 minutes (call from a scheduled job if desired)
create or replace function public.prune_live_doodles(p_older_than interval default interval '30 minutes')
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    delete from public.live_doodles
    where created_at < timezone('utc', now()) - p_older_than;
end;
$$;

grant execute on function public.prune_live_doodles(interval) to service_role;
