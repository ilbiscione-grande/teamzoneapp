-- TEAM-07: atomic moves between teams in the same club. Historical rows stay immutable.

create index if not exists team_assignments_active_person_team_idx
on core.team_assignments(club_id,club_person_id,team_id,starts_at)
where state='active';

create function internal.list_intra_club_move_options_for_actor(target_club_id uuid,target_source_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id,target_source_team_id,'club.memberships.manage')
  then raise insufficient_privilege using message='not_found'; end if;
  select jsonb_build_object(
    'people',coalesce((select jsonb_agg(jsonb_build_object(
      'club_person_id',person.id,'display_name',person.display_name,
      'source_team_id',assignment.team_id,'source_team_name',team.name,
      'assignment_id',assignment.id,'assignment_starts_at',assignment.starts_at,
      'assignment_revision',assignment.revision) order by person.display_name,person.id)
      from core.team_assignments assignment
      join core.club_people person on person.id=assignment.club_person_id and person.club_id=assignment.club_id
      join core.teams team on team.id=assignment.team_id and team.club_id=assignment.club_id
      where assignment.club_id=target_club_id and assignment.team_id=target_source_team_id
        and assignment.state='active' and assignment.starts_at<=now()
        and person.status='active'),'[]'::jsonb),
    'teams',coalesce((select jsonb_agg(jsonb_build_object('team_id',team.id,'team_name',team.name) order by team.name,team.id)
      from core.teams team where team.club_id=target_club_id and team.status='active'
        and team.id<>target_source_team_id),'[]'::jsonb)
  ) into result;
  return result;
end
$$;

create function internal.move_player_within_club_for_actor(
  target_club_id uuid,target_source_team_id uuid,target_target_team_id uuid,
  target_club_person_id uuid,target_assignment_id uuid,effective_at timestamptz,
  expected_revision bigint,reason text,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); source_row core.team_assignments%rowtype;
  existing_result jsonb; new_assignment_id uuid; result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select dedupe.result into existing_result from internal.command_deduplication dedupe
  where dedupe.actor_profile_id=actor_id and dedupe.command_type='roster.move.within_club.v1'
    and dedupe.idempotency_key=move_player_within_club_for_actor.idempotency_key;
  if existing_result is not null then return existing_result; end if;
  if target_source_team_id=target_target_team_id or length(btrim(coalesce(reason,''))) not between 2 and 240
    or effective_at<now()-interval '5 minutes' or effective_at>now()+interval '2 years'
    or not exists(select 1 from core.teams team where team.id=target_target_team_id
      and team.club_id=target_club_id and team.status='active')
  then raise invalid_parameter_value using message='invalid_move'; end if;
  if not internal.actor_has_capability(target_club_id,target_source_team_id,'club.memberships.manage')
    or not internal.actor_has_capability(target_club_id,target_target_team_id,'club.memberships.manage')
  then raise insufficient_privilege using message='not_found'; end if;

  perform pg_advisory_xact_lock(hashtextextended(target_club_id::text||':'||target_club_person_id::text,0));
  select assignment.* into source_row from core.team_assignments assignment
  where assignment.id=target_assignment_id and assignment.club_id=target_club_id
    and assignment.team_id=target_source_team_id and assignment.club_person_id=target_club_person_id
  for update;
  if source_row.id is null then raise insufficient_privilege using message='not_found'; end if;
  if source_row.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
  if source_row.state<>'active' or effective_at<=source_row.starts_at
  then raise check_violation using message='invalid_move_period'; end if;
  if exists(select 1 from core.team_assignments other where other.club_person_id=target_club_person_id
    and other.id<>source_row.id and tstzrange(other.starts_at,coalesce(other.ends_at,'infinity'::timestamptz),'[)')
      && tstzrange(effective_at,'infinity'::timestamptz,'[)'))
  then raise exclusion_violation using message='overlapping_home_assignment'; end if;

  update core.team_assignments set state='ended',ends_at=effective_at,ended_by=actor_id,revision=revision+1
  where id=source_row.id;
  insert into core.team_assignments(club_id,team_id,club_person_id,starts_at,created_by)
  values(target_club_id,target_target_team_id,target_club_person_id,effective_at,actor_id)
  returning id into new_assignment_id;
  result:=jsonb_build_object('source_assignment_id',source_row.id,'target_assignment_id',new_assignment_id,
    'club_person_id',target_club_person_id,'effective_at',effective_at);
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'roster.move.within_club.v1',result);
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
    aggregate_revision,reason,metadata)
  values(target_club_id,actor_id,'roster.move.within_club.v1','team_assignment',new_assignment_id,1,btrim(reason),
    jsonb_build_object('source_assignment_id',source_row.id,'source_team_id',target_source_team_id,
      'target_team_id',target_target_team_id,'club_person_id',target_club_person_id,'effective_at',effective_at));
  return result;
end
$$;

create function api.list_intra_club_move_options(target_club_id uuid,target_source_team_id uuid)
returns jsonb language sql stable security invoker set search_path=''
as $$select internal.list_intra_club_move_options_for_actor(target_club_id,target_source_team_id)$$;

create function api.move_player_within_club(target_club_id uuid,target_source_team_id uuid,target_target_team_id uuid,
  target_club_person_id uuid,target_assignment_id uuid,effective_at timestamptz,expected_revision bigint,
  reason text,idempotency_key uuid)
returns jsonb language sql security invoker set search_path=''
as $$select internal.move_player_within_club_for_actor(target_club_id,target_source_team_id,target_target_team_id,
  target_club_person_id,target_assignment_id,effective_at,expected_revision,reason,idempotency_key)$$;

revoke all on function internal.list_intra_club_move_options_for_actor(uuid,uuid),
  internal.move_player_within_club_for_actor(uuid,uuid,uuid,uuid,uuid,timestamptz,bigint,text,uuid)
  from public,anon,authenticated;
revoke all on function api.list_intra_club_move_options(uuid,uuid),
  api.move_player_within_club(uuid,uuid,uuid,uuid,uuid,timestamptz,bigint,text,uuid)
  from public,anon,authenticated;
grant execute on function internal.list_intra_club_move_options_for_actor(uuid,uuid),
  internal.move_player_within_club_for_actor(uuid,uuid,uuid,uuid,uuid,timestamptz,bigint,text,uuid)
  to authenticated;
grant execute on function api.list_intra_club_move_options(uuid,uuid),
  api.move_player_within_club(uuid,uuid,uuid,uuid,uuid,timestamptz,bigint,text,uuid)
  to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827053705_team07_intra_club_player_move','greenfield','TEAM-07 atomic intra-club move with immutable history');

notify pgrst,'reload schema';
