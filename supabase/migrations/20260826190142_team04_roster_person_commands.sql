-- TEAM-04 atomic, duplicate-safe roster person create and tenant-owned edit.

create or replace function internal.create_roster_person_for_actor(
  target_club_id uuid,target_team_id uuid,new_display_name text,
  new_age_class text,starts_at timestamptz,idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); new_person_id uuid; new_club_person_id uuid;
  existing_result jsonb; normalized_name text:=lower(regexp_replace(btrim(new_display_name),'\s+',' ','g'));
  normalized_age text:=nullif(btrim(new_age_class),'');
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
  then raise insufficient_privilege using message='not_found'; end if;
  select result into existing_result from internal.command_deduplication
   where actor_profile_id=actor_id and command_type='roster.person.create.v1'
     and internal.command_deduplication.idempotency_key=create_roster_person_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'club_person_id')::uuid; end if;
  if length(normalized_name) not between 1 and 120
     or (normalized_age is not null and length(normalized_age)>40)
     or starts_at>now()+interval '1 day'
     or not exists(select 1 from core.teams where id=target_team_id and club_id=target_club_id and status='active')
  then raise invalid_parameter_value using message='invalid_input'; end if;
  perform pg_advisory_xact_lock(hashtextextended(target_club_id::text||':'||target_team_id::text||':'||normalized_name||':'||coalesce(lower(normalized_age),''),0));
  if exists(
    select 1 from core.club_people person
    join core.team_assignments assignment on assignment.club_id=person.club_id
      and assignment.club_person_id=person.id and assignment.team_id=target_team_id
      and assignment.state='active'
    where person.club_id=target_club_id and person.status='active'
      and lower(regexp_replace(btrim(person.display_name),'\s+',' ','g'))=normalized_name
      and coalesce(lower(btrim(person.age_class)),'')=coalesce(lower(normalized_age),'')
  ) then raise unique_violation using message='duplicate_roster_person'; end if;
  insert into core.persons(created_by) values(actor_id) returning id into new_person_id;
  insert into core.club_people(club_id,person_id,display_name,age_class,created_by)
    values(target_club_id,new_person_id,btrim(regexp_replace(new_display_name,'\s+',' ','g')),normalized_age,actor_id)
    returning id into new_club_person_id;
  insert into core.team_assignments(club_id,team_id,club_person_id,starts_at,created_by)
    values(target_club_id,target_team_id,new_club_person_id,least(starts_at,now()),actor_id);
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
    values(actor_id,idempotency_key,'roster.person.create.v1',jsonb_build_object('club_person_id',new_club_person_id));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
    values(target_club_id,actor_id,'roster.person.create.v1','club_person',new_club_person_id,1);
  return new_club_person_id;
end
$$;

create function internal.update_roster_person_for_actor(
  target_club_id uuid,target_team_id uuid,target_club_person_id uuid,
  new_display_name text,new_age_class text,expected_revision bigint,idempotency_key uuid
)
returns bigint language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); person core.club_people%rowtype; existing_result jsonb;
  new_revision bigint; normalized_name text:=lower(regexp_replace(btrim(new_display_name),'\s+',' ','g'));
  normalized_age text:=nullif(btrim(new_age_class),'');
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
  then raise insufficient_privilege using message='not_found'; end if;
  select result into existing_result from internal.command_deduplication
   where actor_profile_id=actor_id and command_type='roster.person.update.v1'
     and internal.command_deduplication.idempotency_key=update_roster_person_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'revision')::bigint; end if;
  if length(normalized_name) not between 1 and 120
     or (normalized_age is not null and length(normalized_age)>40)
  then raise invalid_parameter_value using message='invalid_input'; end if;
  select * into person from core.club_people
   where id=target_club_person_id and club_id=target_club_id and status='active' for update;
  if person.id is null or not exists(
    select 1 from core.team_assignments assignment where assignment.club_id=target_club_id
      and assignment.team_id=target_team_id and assignment.club_person_id=person.id and assignment.state='active'
  ) then raise insufficient_privilege using message='not_found'; end if;
  if person.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
  if exists(
    select 1 from core.club_people other
    join core.team_assignments assignment on assignment.club_id=other.club_id
      and assignment.club_person_id=other.id and assignment.team_id=target_team_id and assignment.state='active'
    where other.club_id=target_club_id and other.id<>person.id and other.status='active'
      and lower(regexp_replace(btrim(other.display_name),'\s+',' ','g'))=normalized_name
      and coalesce(lower(btrim(other.age_class)),'')=coalesce(lower(normalized_age),'')
  ) then raise unique_violation using message='duplicate_roster_person'; end if;
  update core.club_people set display_name=btrim(regexp_replace(new_display_name,'\s+',' ','g')),
    age_class=normalized_age,revision=revision+1 where id=person.id returning revision into new_revision;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
    values(actor_id,idempotency_key,'roster.person.update.v1',jsonb_build_object('revision',new_revision));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
    values(target_club_id,actor_id,'roster.person.update.v1','club_person',person.id,new_revision);
  return new_revision;
end
$$;

create or replace function internal.get_roster_person_details_for_actor(
  target_club_id uuid,target_team_id uuid,target_club_person_id uuid
)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); can_manage boolean; actor_role text; result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.view')
     and not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
  then raise insufficient_privilege using message='not_found'; end if;
  select assignment.role_package into actor_role from core.person_account_links link
  join core.assignments assignment on assignment.club_person_id=link.club_person_id
    and assignment.club_id=link.club_id and assignment.state='active'
    and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now())
  where link.profile_id=actor_id and link.club_id=target_club_id and link.state='active'
    and (assignment.team_id=target_team_id or assignment.team_id is null)
  order by assignment.team_id is not null desc limit 1;
  if actor_role is null or actor_role not in ('player','leader','guardian','club_functionary')
  then raise insufficient_privilege using message='role_not_supported'; end if;
  can_manage:=internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
    or internal.actor_has_capability(target_club_id,null,'club.memberships.manage');
  select jsonb_strip_nulls(jsonb_build_object(
    'club_person_id',person.id,'display_name',person.display_name,'age_class',person.age_class,
    'team_id',team.id,'team_name',team.name,'assignment_state',assignment.state,
    'person_revision',case when can_manage then person.revision else null end,
    'safeguarding_required',case when can_manage then person.safeguarding_required else null end,
    'management',case when can_manage then jsonb_build_object('provenance',person.provenance,
      'assignment_starts_at',assignment.starts_at,'assignment_ends_at',assignment.ends_at,
      'assignment_revision',assignment.revision) else null end
  )) into result from core.club_people person
  join lateral(select item.* from core.team_assignments item where item.club_id=person.club_id
    and item.club_person_id=person.id and item.team_id=target_team_id
    order by item.state='active' desc,item.starts_at desc,item.id desc limit 1) assignment on true
  join core.teams team on team.id=assignment.team_id and team.club_id=assignment.club_id
  where person.id=target_club_person_id and person.club_id=target_club_id and person.status='active';
  if result is null then raise insufficient_privilege using message='not_found'; end if;
  return result;
end
$$;

create function api.update_roster_person(target_club_id uuid,target_team_id uuid,
  target_club_person_id uuid,display_name text,age_class text,expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path=''
as $$select internal.update_roster_person_for_actor(target_club_id,target_team_id,target_club_person_id,display_name,age_class,expected_revision,idempotency_key)$$;

revoke all on function internal.update_roster_person_for_actor(uuid,uuid,uuid,text,text,bigint,uuid),
  api.update_roster_person(uuid,uuid,uuid,text,text,bigint,uuid) from public,anon,authenticated;
grant execute on function internal.update_roster_person_for_actor(uuid,uuid,uuid,text,text,bigint,uuid),
  api.update_roster_person(uuid,uuid,uuid,text,text,bigint,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260826190142_team04_roster_person_commands','greenfield','TEAM-04 atomic tenant-owned roster create/edit');

notify pgrst,'reload schema';
