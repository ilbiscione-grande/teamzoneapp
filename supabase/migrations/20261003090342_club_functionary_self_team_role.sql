-- A club membership administrator may correct their own team role. The
-- existing self-lock remains for team-scoped managers so nobody can remove
-- the last authority they depend on or promote themselves through this path.
create or replace function internal.team_role_command(target_club_id uuid,target_team_id uuid,target_person_id uuid,
 from_role text,to_role text,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); command text; existing jsonb; result jsonb;
begin
 perform internal.assert_team_role_manager(target_club_id,target_team_id);
 command:=case when from_role is null then 'roster.role.add.v1' when to_role is null then 'roster.role.remove.v1' else 'roster.role.change.v1' end;
 if idempotency_key is null or (from_role is not null and from_role not in('player','leader'))
  or (to_role is not null and to_role not in('player','leader')) or from_role is not distinct from to_role then
  raise invalid_parameter_value using message='invalid_role';
 end if;
 select dedup.result into existing from internal.command_deduplication dedup
 where dedup.actor_profile_id=actor_id and dedup.command_type=command
  and dedup.idempotency_key=team_role_command.idempotency_key;
 if existing is not null then return existing; end if;
 perform pg_advisory_xact_lock(hashtextextended('team_role:'||target_club_id::text||':'||target_person_id::text,0));
 if not exists(select 1 from core.club_people person where person.id=target_person_id
  and person.club_id=target_club_id and person.status='active') then
  raise invalid_parameter_value using message='invalid_person';
 end if;
 if from_role is not null then
  if not internal.team_role_active(target_club_id,target_team_id,target_person_id,from_role) then
   raise serialization_failure using message='stale_role';
  end if;
  if from_role='leader' and internal.actor_owns_club_person(target_club_id,target_person_id)
   and not internal.actor_has_capability(target_club_id,null,'club.memberships.manage') then
   raise check_violation using message='own_leader_role';
  end if;
  if to_role='player' and exists(select 1 from core.team_assignments home where home.club_id=target_club_id
   and home.club_person_id=target_person_id and home.state='active' and home.team_id<>target_team_id) then
   raise check_violation using message='home_in_other_team';
  end if;
  perform internal.stop_team_role(target_club_id,target_team_id,target_person_id,from_role);
 end if;
 if to_role is not null then
  perform internal.start_team_role(target_club_id,target_team_id,target_person_id,to_role);
 end if;
 result:=jsonb_build_object('person_id',target_person_id,'from_role',from_role,'to_role',to_role);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,command,result);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,command,'club_person',target_person_id,1,
  jsonb_build_object('team_id',target_team_id,'from_role',from_role,'to_role',to_role));
 return result;
end$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261003090342_club_functionary_self_team_role','greenfield','Profile edit: club administrators may change their own team role');

notify pgrst,'reload schema';
