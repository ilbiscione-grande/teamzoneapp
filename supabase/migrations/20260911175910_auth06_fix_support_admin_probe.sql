-- The API probe must cross the private internal-schema EXECUTE boundary.
-- It exposes only the current actor's boolean result and no support data.
create or replace function api.is_support_admin()
returns boolean language sql stable security definer set search_path=''
as $$select internal.actor_is_support_admin()$$;

revoke all on function api.is_support_admin() from public,anon,authenticated;
grant execute on function api.is_support_admin() to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260911175910_auth06_fix_support_admin_probe','greenfield',
  'AUTH-06 allow the minimal API probe to cross the private internal function boundary');
