-- HOME-02/HOME-03: show the current decline reason only inside the already
-- authorized own/selected-child home projection. Never accept a callup ID
-- from the client for this enrichment.

create function internal.home_with_own_decline_reasons(home jsonb, callup_key text)
returns jsonb
language plpgsql
stable
security invoker
set search_path=''
as $$
declare enriched jsonb;
begin
  select coalesce(jsonb_agg(
    case when item.value->>'state'='declined'
      then item.value || jsonb_build_object(
        'decline_reason_code', latest.decline_reason_code,
        'decline_reason_text', latest.decline_reason_text)
      else item.value end
    order by item.ordinality), '[]'::jsonb)
  into enriched
  from jsonb_array_elements(coalesce(home->callup_key, '[]'::jsonb))
       with ordinality as item(value, ordinality)
  left join lateral (
    select response.decline_reason_code, response.decline_reason_text
    from core.callup_responses response
    where response.callup_id=(item.value->>'callup_id')::uuid
      and response.revision=(item.value->>'revision')::bigint
      and response.response='declined'
    limit 1
  ) latest on true;

  return jsonb_set(home, array[callup_key], enriched, true);
end;
$$;

revoke all on function internal.home_with_own_decline_reasons(jsonb,text)
from public, anon, authenticated;

create function internal.get_player_home_with_reasons_for_actor(target_context_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  select internal.home_with_own_decline_reasons(
    internal.get_player_home_for_actor(target_context_id), 'own_callups');
$$;

create function internal.get_guardian_home_with_reasons_for_actor(
  target_context_id uuid, target_child_person_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  select internal.home_with_own_decline_reasons(
    internal.get_guardian_home_for_actor(target_context_id,target_child_person_id),
    'child_callups');
$$;

revoke all on function internal.get_player_home_with_reasons_for_actor(uuid),
  internal.get_guardian_home_with_reasons_for_actor(uuid,uuid)
from public, anon, authenticated;
grant execute on function internal.get_player_home_with_reasons_for_actor(uuid),
  internal.get_guardian_home_with_reasons_for_actor(uuid,uuid)
to authenticated;

create or replace function api.get_player_home(context_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path=''
as $$
  select internal.get_player_home_with_reasons_for_actor(context_id);
$$;

create or replace function api.get_guardian_home(
  context_id uuid, child_person_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path=''
as $$
  select internal.get_guardian_home_with_reasons_for_actor(context_id,child_person_id);
$$;

revoke all on function api.get_player_home(uuid),
  api.get_guardian_home(uuid,uuid)
from public, anon;
grant execute on function api.get_player_home(uuid),
  api.get_guardian_home(uuid,uuid)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20260924102411_home03_visible_own_decline_reason','greenfield',
  'HOME-02/HOME-03 current response reason for own or selected child callup'
where not exists (
  select 1 from internal.migration_provenance
  where migration_name='20260924102411_home03_visible_own_decline_reason'
);
