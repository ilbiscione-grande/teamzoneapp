create table core.team_creation_requests(
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  requester_profile_id uuid not null references core.profiles(id),
  requester_assignment_id uuid not null,
  team_name text not null check(length(btrim(team_name)) between 1 and 120),
  state text not null default 'pending' check(state in('pending','approved','rejected')),
  decided_by uuid references core.profiles(id),
  decided_at timestamptz,
  created_team_id uuid references core.teams(id),
  revision bigint not null default 1,
  created_at timestamptz not null default now(),
  foreign key(club_id,requester_assignment_id)
    references core.assignments(club_id,id)
);
create unique index team_creation_requests_pending_unique
  on core.team_creation_requests(club_id,requester_profile_id,lower(btrim(team_name)))
  where state='pending';
create index team_creation_requests_admin_queue
  on core.team_creation_requests(club_id,state,created_at desc);
alter table core.team_creation_requests enable row level security;
create policy team_creation_requests_no_direct_select
  on core.team_creation_requests for select to authenticated using(false);

create function internal.request_team_creation_for_actor(
  target_club_id uuid,source_assignment_id uuid,team_name text,idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();normalized_name text:=btrim(team_name);
 request_id uuid;existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='organization.team.request.v1'
  and internal.command_deduplication.idempotency_key=request_team_creation_for_actor.idempotency_key;
 if existing is not null then return(existing->>'request_id')::uuid;end if;
 if length(normalized_name) not between 1 and 120 or not exists(
  select 1 from core.assignments assignment_row
  join core.person_account_links link on link.club_id=assignment_row.club_id
   and link.club_person_id=assignment_row.club_person_id and link.profile_id=actor_id and link.state='active'
  where assignment_row.id=source_assignment_id and assignment_row.club_id=target_club_id
   and assignment_row.role_package='leader' and assignment_row.state='active'
   and assignment_row.starts_at<=now() and(assignment_row.ends_at is null or assignment_row.ends_at>now())
 ) then raise insufficient_privilege using message='not_found';end if;
 insert into core.team_creation_requests(club_id,requester_profile_id,requester_assignment_id,team_name)
 values(target_club_id,actor_id,source_assignment_id,normalized_name) returning id into request_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'organization.team.request.v1',jsonb_build_object('request_id',request_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
 values(target_club_id,actor_id,'organization.team.request.v1','team_creation_request',request_id,1);
 return request_id;
end $$;

create function internal.list_team_creation_requests_for_actor(target_club_id uuid)
returns table(request_id uuid,team_name text,requester_name text,state text,revision bigint,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$ begin
 if auth.uid() is null or not internal.actor_has_capability(target_club_id,null,'club.memberships.manage')
 then raise insufficient_privilege using message='not_found';end if;
 return query select request.id,request.team_name,profile.display_name,request.state,request.revision,request.created_at
 from core.team_creation_requests request join core.profiles profile on profile.id=request.requester_profile_id
 where request.club_id=target_club_id order by(request.state='pending')desc,request.created_at desc;
end $$;

create function internal.decide_team_creation_request_for_actor(
 target_request_id uuid,decision text,expected_revision bigint,idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();request core.team_creation_requests%rowtype;existing jsonb;
 team_id uuid;requester_person_id uuid;new_assignment_id uuid;result jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='organization.team.request.decide.v1'
  and internal.command_deduplication.idempotency_key=decide_team_creation_request_for_actor.idempotency_key;
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
 result:=jsonb_build_object('request_id',request.id,'state',decision,'team_id',team_id);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'organization.team.request.decide.v1',result);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(request.club_id,actor_id,'organization.team.request.decide.v1','team_creation_request',request.id,request.revision+1,
  jsonb_build_object('decision',decision,'team_id',team_id));
 return result;
end $$;

create function api.request_team_creation(target_club_id uuid,source_assignment_id uuid,team_name text,idempotency_key uuid)
returns uuid language sql security invoker set search_path='' as $$select internal.request_team_creation_for_actor(target_club_id,source_assignment_id,team_name,idempotency_key)$$;
create function api.list_team_creation_requests(target_club_id uuid)
returns table(request_id uuid,team_name text,requester_name text,state text,revision bigint,created_at timestamptz)
language sql stable security invoker set search_path='' as $$select * from internal.list_team_creation_requests_for_actor(target_club_id)$$;
create function api.decide_team_creation_request(request_id uuid,decision text,expected_revision bigint,idempotency_key uuid)
returns jsonb language sql security invoker set search_path='' as $$select internal.decide_team_creation_request_for_actor(request_id,decision,expected_revision,idempotency_key)$$;

revoke all on function internal.request_team_creation_for_actor(uuid,uuid,text,uuid),internal.list_team_creation_requests_for_actor(uuid),internal.decide_team_creation_request_for_actor(uuid,text,bigint,uuid) from public,anon,authenticated;
revoke all on function api.request_team_creation(uuid,uuid,text,uuid),api.list_team_creation_requests(uuid),api.decide_team_creation_request(uuid,text,bigint,uuid) from public,anon,authenticated;
grant execute on function internal.request_team_creation_for_actor(uuid,uuid,text,uuid),internal.list_team_creation_requests_for_actor(uuid),internal.decide_team_creation_request_for_actor(uuid,text,bigint,uuid) to authenticated;
grant execute on function api.request_team_creation(uuid,uuid,text,uuid),api.list_team_creation_requests(uuid),api.decide_team_creation_request(uuid,text,bigint,uuid) to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)values('20260913093334_auth05_team_creation_requests','greenfield','AUTH-05 leader request and club approval for additional teams');
notify pgrst,'reload schema';
