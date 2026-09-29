-- Descriptive team functions/playing positions; never capability grants.
create table core.team_person_details (
 club_id uuid not null,
 team_id uuid not null,
 club_person_id uuid not null,
 functions text[] not null default '{}',
 positions text[] not null default '{}',
 revision bigint not null default 1 check(revision>0),
 updated_at timestamptz not null default now(),
 updated_by uuid not null,
 primary key(team_id,club_person_id),
 foreign key(team_id,club_id) references core.teams(id,club_id),
 foreign key(club_person_id,club_id) references core.club_people(id,club_id),
 check(cardinality(functions)<=10 and functions <@ array[
  'head_coach','assistant_coach','team_manager','contact_person','goalkeeper_coach',
  'fitness_coach','equipment_manager','medical_staff','treasurer','administrator']::text[]
  and array_position(functions,null) is null),
 check(cardinality(positions)<=11 and positions <@ array[
  'goalkeeper','centre_back','left_back','right_back','wing_back','defensive_midfielder',
  'central_midfielder','attacking_midfielder','left_winger','right_winger','striker']::text[]
  and array_position(positions,null) is null)
);
alter table core.team_person_details enable row level security;
revoke all on core.team_person_details from public,anon,authenticated;

create function internal.set_team_person_details_for_actor(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_functions text[],new_positions text[],expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); current_revision bigint; saved_revision bigint; cached jsonb;
begin
 perform internal.assert_team_role_manager(target_club_id,target_team_id);
 if idempotency_key is null or new_functions is null or new_positions is null
  or expected_revision is null or expected_revision<0 then
  raise invalid_parameter_value using message='invalid_input'; end if;
 -- Serialize before deduplication so concurrent retries are also idempotent.
 perform pg_advisory_xact_lock(hashtextextended('team-person-details:'||target_team_id::text||':'||target_person_id::text,0));
 select d.result into cached from internal.command_deduplication d
 where d.actor_profile_id=actor_id and d.command_type='team.person_details.updated.v1'
  and d.idempotency_key=set_team_person_details_for_actor.idempotency_key;
 if cached is not null then return (cached->>'revision')::bigint; end if;
 if not exists(select 1 from core.assignments a join core.club_people p
  on p.id=a.club_person_id and p.club_id=a.club_id
  where a.club_id=target_club_id and a.team_id=target_team_id and a.club_person_id=target_person_id
   and a.role_package in('player','leader','club_functionary') and a.state='active'
   and a.starts_at<=now() and(a.ends_at is null or a.ends_at>now()) and p.status='active')
 then raise insufficient_privilege using message='not_found'; end if;
 select d.revision into current_revision from core.team_person_details d
 where d.team_id=target_team_id and d.club_person_id=target_person_id for update;
 if coalesce(current_revision,0)<>expected_revision then
  raise serialization_failure using message='stale_revision'; end if;
 saved_revision:=coalesce(current_revision,0)+1;
 insert into core.team_person_details(club_id,team_id,club_person_id,functions,positions,revision,updated_by)
 values(target_club_id,target_team_id,target_person_id,
  array(select distinct v from unnest(new_functions)v order by v),
  array(select distinct v from unnest(new_positions)v order by v),saved_revision,actor_id)
 on conflict(team_id,club_person_id) do update
 set functions=excluded.functions,positions=excluded.positions,revision=excluded.revision,
  updated_by=actor_id,updated_at=now();
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'team.person_details.updated.v1',jsonb_build_object('revision',saved_revision));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,'team.person_details.updated.v1','team_person',target_person_id,saved_revision,
  jsonb_build_object('team_id',target_team_id,'functions',new_functions,'positions',new_positions));
 return saved_revision;
end;
$$;

create function api.set_team_person_details(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,new_functions text[],new_positions text[],
 expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path='' as $$
 select internal.set_team_person_details_for_actor(target_club_id,target_team_id,target_person_id,
 new_functions,new_positions,expected_revision,idempotency_key)
$$;

-- Reuse the existing batch list and its visibility/capability boundary.
create or replace function internal.list_team_roles_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.view')
  and not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage') then
  raise insufficient_privilege using message='not_found';
 end if;
 return jsonb_build_object(
  'can_manage',internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage'),
  'roles',coalesce((select jsonb_agg(jsonb_build_object(
    'person_id',person.id,'name',person.display_name,'role',assignment.role_package,
    'starts_at',assignment.starts_at,'is_self',internal.actor_owns_club_person(target_club_id,person.id),
    'functions',coalesce(details.functions,'{}'::text[]),
    'positions',coalesce(details.positions,'{}'::text[]),'details_revision',coalesce(details.revision,0))
   order by case assignment.role_package when 'leader' then 0 when 'club_functionary' then 1 else 2 end,person.display_name,person.id)
   from core.assignments assignment
   join core.club_people person on person.id=assignment.club_person_id and person.club_id=assignment.club_id
   left join core.team_person_details details on details.club_id=assignment.club_id
    and details.team_id=assignment.team_id and details.club_person_id=assignment.club_person_id
   where assignment.club_id=target_club_id and assignment.team_id=target_team_id
    and assignment.role_package in('player','leader','club_functionary')
    and assignment.state='active' and assignment.starts_at<=now()
    and (assignment.ends_at is null or assignment.ends_at>now())
    and person.status='active'),'[]'::jsonb));
end$$;
revoke all on function internal.set_team_person_details_for_actor(uuid,uuid,uuid,text[],text[],bigint,uuid),
 api.set_team_person_details(uuid,uuid,uuid,text[],text[],bigint,uuid) from public,anon,authenticated;
grant execute on function internal.set_team_person_details_for_actor(uuid,uuid,uuid,text[],text[],bigint,uuid),
 api.set_team_person_details(uuid,uuid,uuid,text[],text[],bigint,uuid) to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260929101319_team_person_functions_positions','greenfield','Descriptive per-team functions and playing positions, separate from permissions');
notify pgrst,'reload schema';
