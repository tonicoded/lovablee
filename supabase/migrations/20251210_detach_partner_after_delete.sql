-- Move partner cleanup trigger to AFTER DELETE to avoid tuple-modified errors.

drop trigger if exists trg_detach_partner_on_delete on public.users;

create trigger trg_detach_partner_on_delete
after delete on public.users
for each row execute function public.detach_partner_on_delete();
