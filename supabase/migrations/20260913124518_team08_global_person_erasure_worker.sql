-- TEAM-08: explicit support-admin queue plus service-only worker projection.

create or replace function api.list_global_person_erasure_cases()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  result jsonb;
begin
  if auth.uid() is null or not internal.actor_is_support_admin() then
    raise insufficient_privilege using message='not_found';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'request_id', request.id,
        'requester_name', profile.display_name,
        'state', request.state,
        'reason', request.reason,
        'requested_at', request.created_at,
        'reviewed_at', request.reviewed_at,
        'completed_at', request.completed_at,
        'revision', request.revision
      ) order by
        case request.state
          when 'requested' then 0
          when 'approved' then 1
          else 2
        end,
        request.created_at desc
    ),
    '[]'::jsonb
  ) into result
  from internal.global_person_erasure_requests request
  join core.profiles profile on profile.id=request.requested_by;

  return result;
end
$$;

create or replace function api.get_global_person_erasure_worker_item(
  target_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  request_row internal.global_person_erasure_requests%rowtype;
begin
  if current_user not in ('service_role','postgres') then
    raise insufficient_privilege using message='service_role_required';
  end if;

  select * into request_row
  from internal.global_person_erasure_requests
  where id=target_request_id;

  if request_row.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'request_id', request_row.id,
    'subject_profile_id', request_row.requested_by,
    'state', request_row.state,
    'revision', request_row.revision
  );
end
$$;

revoke all on function api.list_global_person_erasure_cases(),
  api.get_global_person_erasure_worker_item(uuid)
from public,anon,authenticated;

grant execute on function api.list_global_person_erasure_cases()
to authenticated;

grant execute on function api.get_global_person_erasure_worker_item(uuid)
to service_role;

insert into internal.migration_provenance(
  migration_name,
  source_kind,
  source_reference
)
values(
  '20260913124518_team08_global_person_erasure_worker',
  'greenfield',
  'TEAM-08 support-admin queue and service-only Auth erasure worker projection'
);

notify pgrst,'reload schema';
