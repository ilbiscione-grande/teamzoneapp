create or replace function internal.decide_team_creation_request_for_actor(
 target_request_id uuid,decision text,expected_revision bigint,idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();request core.team_creation_requests%rowtype;existing jsonb;
 team_id uuid;requester_person_id uuid;new_assignment_id uuid;command_result jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select dedupe.result into existing from internal.command_deduplication dedupe
 where dedupe.actor_profile_id=actor_id
  and dedupe.command_type='organization.team.request.decide.v1'
  and dedupe.idempotency_key=decide_team_creation_request_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 select * into request from core.team_creation_requests where id=target_request_id for update;
 if request.id is null or not internal.actor_has_capability(request.club_id,null,'club.memberships.manage')
 then raise insufficient_privilege using message='not_found';end if;
 if request.state<>'pending' or request.revision<>expected_revision or decision not in('approved','rejected')
 then raise check_violation using message='invalid_transition';end if;
 if decision='approved' then
  team_id:=internal.create_team_in_club_for_actor(request.club_id,request.team_name,gen_random_uuid());
  select link.club_person_id into requester_person_id from core.person_account_links link
   where link.profile_id=request.requester_profile_id and link.club_id=request.club_id and link.state='active' limit 1;
  insert into core.assignments(club_id,team_id,club_person_id,role_package,state,starts_at,created_by)
   values(request.club_id,team_id,requester_person_id,'leader','active',now(),actor_id)
   returning id into new_assignment_id;
  insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,ends_at,created_by)
   select request.club_id,new_assignment_id,grant_row.capability,'team',team_id,now(),grant_row.ends_at,actor_id
   from core.capability_grants grant_row where grant_row.assignment_id=request.requester_assignment_id
    and grant_row.scope_type='team' and grant_row.starts_at<=now()
    and(grant_row.ends_at is null or grant_row.ends_at>now())
   on conflict(assignment_id,capability,scope_type,scope_id)do nothing;
 end if;
 update core.team_creation_requests set state=decision,decided_by=actor_id,decided_at=now(),
  created_team_id=team_id,revision=revision+1 where id=request.id;
 command_result:=jsonb_build_object('request_id',request.id,'state',decision,'team_id',team_id);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'organization.team.request.decide.v1',command_result);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(request.club_id,actor_id,'organization.team.request.decide.v1','team_creation_request',request.id,request.revision+1,
  jsonb_build_object('decision',decision,'team_id',team_id));
 return command_result;
end $$;

revoke all on function internal.decide_team_creation_request_for_actor(uuid,text,bigint,uuid)
 from public,anon,authenticated;
grant execute on function internal.decide_team_creation_request_for_actor(uuid,text,bigint,uuid)
 to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260913095854_auth05_fix_team_request_decision','greenfield','qualify idempotency result in team creation decision');
notify pgrst,'reload schema';
