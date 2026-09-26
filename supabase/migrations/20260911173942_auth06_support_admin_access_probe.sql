-- Minimal self-probe used only to decide whether the support queue entry is shown.
create function api.is_support_admin()
returns boolean language sql stable security invoker set search_path=''
as $$select internal.actor_is_support_admin()$$;

revoke all on function api.is_support_admin() from public,anon,authenticated;
grant execute on function api.is_support_admin() to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260911173942_auth06_support_admin_access_probe','greenfield',
  'AUTH-06 minimal support-admin navigation probe');
