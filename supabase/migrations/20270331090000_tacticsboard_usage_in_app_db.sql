-- Supportens statistik för Tacticsboard i appens databas (2026-11-15).
--
-- Since 2026-11-15 the app and Tacticsboard share the live database, so the
-- support page reads Tacticsboard's numbers directly instead of through the
-- edge function support-tacticsboard-usage and the production project's
-- secret key. Only support administrators may call it; others get
-- insufficient_privilege (not_found), as for the other support numbers.
--
-- Counts only, from the same functions as before; the only names are titles
-- of items shared in the library, which are public there.

create or replace function internal.get_tacticsboard_usage_for_support_for_actor(period_days integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return internal.get_tacticsboard_usage_for_server(period_days)
    || internal.get_tacticsboard_usage_more_for_server(period_days);
end
$$;

create or replace function api.get_tacticsboard_usage_for_support(period_days integer default 30)
returns jsonb language sql stable security invoker set search_path = ''
as $$select internal.get_tacticsboard_usage_for_support_for_actor(period_days)$$;

revoke all on function
  internal.get_tacticsboard_usage_for_support_for_actor(integer),
  api.get_tacticsboard_usage_for_support(integer)
from public, anon, authenticated;

grant execute on function
  internal.get_tacticsboard_usage_for_support_for_actor(integer),
  api.get_tacticsboard_usage_for_support(integer)
to authenticated;

notify pgrst, 'reload schema';
