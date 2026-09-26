-- AUTH-05: an additional team must immediately become an usable context for
-- the club functionary who created it.

create or replace function internal.create_team_in_club_for_actor(
  target_club_id uuid,team_name text,idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); normalized_team text:=btrim(team_name);
 existing_result jsonb; team_id uuid; actor_club_person_id uuid;
 context_assignment_id uuid;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if length(normalized_team) not between 1 and 120 then
    raise invalid_parameter_value using message='invalid_name';
  end if;
  if not internal.actor_has_capability(target_club_id,null,'club.memberships.manage') then
    raise insufficient_privilege using message='not_found';
  end if;
  select result into existing_result from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='organization.team.create.v1'
    and internal.command_deduplication.idempotency_key=create_team_in_club_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'team_id')::uuid; end if;

  select link.club_person_id into actor_club_person_id
  from core.person_account_links link
  where link.profile_id=actor_id
    and link.club_id=target_club_id
    and link.state='active'
  order by link.created_at
  limit 1;
  if actor_club_person_id is null then
    raise insufficient_privilege using message='not_found';
  end if;

  insert into core.teams(club_id,name,created_by)
  values(target_club_id,normalized_team,actor_id) returning id into team_id;
  insert into core.assignments(
    club_id,team_id,club_person_id,role_package,state,starts_at,created_by
  ) values(
    target_club_id,team_id,actor_club_person_id,'club_functionary','active',now(),actor_id
  ) returning id into context_assignment_id;

  insert into core.capability_grants(
    club_id,assignment_id,capability,scope_type,scope_id,starts_at,ends_at,created_by
  )
  select target_club_id,context_assignment_id,source.capability,'club',target_club_id,
    now(),source.ends_at,actor_id
  from (
    select distinct on (grant_row.capability)
      grant_row.capability,grant_row.ends_at
    from core.assignments assignment_row
    join core.capability_grants grant_row
      on grant_row.assignment_id=assignment_row.id
    where assignment_row.club_id=target_club_id
      and assignment_row.club_person_id=actor_club_person_id
      and assignment_row.state='active'
      and grant_row.scope_type='club'
      and grant_row.scope_id=target_club_id
      and grant_row.starts_at<=now()
      and (grant_row.ends_at is null or grant_row.ends_at>now())
    order by grant_row.capability,grant_row.ends_at nulls first
  ) source;

  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'organization.team.create.v1',jsonb_build_object('team_id',team_id));
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,
    metadata
  ) values(
    target_club_id,actor_id,'organization.team.create.v1','team',team_id,1,
    jsonb_build_object('context_id',context_assignment_id)
  );
  return team_id;
end
$$;

revoke all on function internal.create_team_in_club_for_actor(uuid,text,uuid)
  from public,anon,authenticated;
grant execute on function internal.create_team_in_club_for_actor(uuid,text,uuid)
  to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values(
  '20260910183540_auth05_create_team_context',
  'greenfield',
  'AUTH-05 additional team creation produces an immediately usable creator context'
);
