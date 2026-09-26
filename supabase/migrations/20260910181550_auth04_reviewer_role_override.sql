alter table core.membership_applications
  add column approved_role text
  check (
    approved_role is null
    or approved_role in ('player','leader','guardian','club_functionary')
  );

create function internal.decide_membership_application_v2(
  application_id uuid,
  decision text,
  approved_role text,
  idempotency_key uuid
)
returns text
language plpgsql
security definer
set search_path=''
as $$
declare
  actor_id uuid:=auth.uid();
  row_value core.membership_applications%rowtype;
  selected_role text;
  result text;
  existing_result jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;
  if decision not in ('approved','rejected') then
    raise invalid_parameter_value using message='invalid_decision';
  end if;

  select dedupe.result into existing_result
  from internal.command_deduplication dedupe
  where dedupe.actor_profile_id=actor_id
    and dedupe.command_type='membership.application.decide.v2'
    and dedupe.idempotency_key=decide_membership_application_v2.idempotency_key;
  if existing_result is not null then
    return existing_result->>'status';
  end if;

  select * into row_value
  from core.membership_applications application
  where application.id=decide_membership_application_v2.application_id
  for update;
  if row_value.id is null or row_value.status<>'pending'
     or not (
       internal.actor_has_capability(
         row_value.club_id,row_value.team_id,'club.memberships.manage'
       )
       or internal.actor_has_capability(
         row_value.club_id,row_value.team_id,'team.roster.manage'
       )
     ) then
    raise insufficient_privilege using message='not_found';
  end if;

  selected_role:=case
    when decision='approved' then coalesce(approved_role,row_value.requested_role)
    else row_value.requested_role
  end;
  if selected_role not in ('player','leader','guardian','club_functionary') then
    raise invalid_parameter_value using message='invalid_role';
  end if;

  if decision='approved' and selected_role<>row_value.requested_role then
    -- The v1 command creates the assignment from requested_role. Change it
    -- only while holding the row lock, then restore the applicant's request.
    update core.membership_applications
    set requested_role=selected_role
    where id=row_value.id;
  end if;

  result:=internal.decide_membership_application_for_actor(
    row_value.id,decision,idempotency_key
  );

  update core.membership_applications
  set requested_role=row_value.requested_role,
      approved_role=case when decision='approved' then selected_role else null end
  where id=row_value.id;

  if decision='approved' and selected_role<>row_value.requested_role then
    insert into audit.command_events(
      club_id,actor_profile_id,command_type,aggregate_type,
      aggregate_id,aggregate_revision,metadata
    ) values (
      row_value.club_id,actor_id,'membership.application.role_override.v1',
      'membership_application',row_value.id,row_value.revision+1,
      jsonb_build_object(
        'requested_role',row_value.requested_role,
        'approved_role',selected_role,
        'team_id',row_value.team_id
      )
    );
  end if;

  insert into internal.command_deduplication(
    actor_profile_id,idempotency_key,command_type,result
  ) values (
    actor_id,idempotency_key,'membership.application.decide.v2',
    jsonb_build_object('status',result,'approved_role',selected_role)
  );
  return result;
end
$$;

create function api.decide_membership_application_v2(
  application_id uuid,
  decision text,
  approved_role text,
  idempotency_key uuid
)
returns text
language sql
security invoker
set search_path=''
as $$
  select internal.decide_membership_application_v2(
    application_id,decision,approved_role,idempotency_key
  )
$$;

revoke all on function
  internal.decide_membership_application_v2(uuid,text,text,uuid),
  api.decide_membership_application_v2(uuid,text,text,uuid)
  from public,anon;
revoke all on function
  internal.decide_membership_application_v2(uuid,text,text,uuid)
  from authenticated;
grant execute on function
  internal.decide_membership_application_v2(uuid,text,text,uuid),
  api.decide_membership_application_v2(uuid,text,text,uuid)
  to authenticated;
