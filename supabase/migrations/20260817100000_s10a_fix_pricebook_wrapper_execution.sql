-- Cross the revoked internal boundary through one capability-checked API.

create or replace function api.get_published_pricebook(target_club_id uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select internal.get_published_pricebook_for_actor(target_club_id)
$$;

revoke all on function api.get_published_pricebook(uuid) from public, anon;
grant execute on function api.get_published_pricebook(uuid) to authenticated;

insert into internal.migration_provenance(migration_name, source_kind)
values ('20260817100000_s10a_fix_pricebook_wrapper_execution', 'greenfield');
