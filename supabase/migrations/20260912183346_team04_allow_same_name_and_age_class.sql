-- Names and age classes are descriptive roster data, not person identifiers.
-- Two real people in one team may legitimately share both values. Retry safety
-- remains provided by the actor-scoped command idempotency key.

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

create or replace function internal.update_roster_person_for_actor(
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
  update core.club_people set display_name=btrim(regexp_replace(new_display_name,'\s+',' ','g')),
    age_class=normalized_age,revision=revision+1 where id=person.id returning revision into new_revision;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
    values(actor_id,idempotency_key,'roster.person.update.v1',jsonb_build_object('revision',new_revision));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
    values(target_club_id,actor_id,'roster.person.update.v1','club_person',person.id,new_revision);
  return new_revision;
end
$$;

revoke all on function internal.create_roster_person_for_actor(uuid,uuid,text,text,timestamptz,uuid),
  internal.update_roster_person_for_actor(uuid,uuid,uuid,text,text,bigint,uuid)
from public,anon,authenticated;
grant execute on function internal.create_roster_person_for_actor(uuid,uuid,text,text,timestamptz,uuid),
  internal.update_roster_person_for_actor(uuid,uuid,uuid,text,text,bigint,uuid)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values(
  '20260912183346_team04_allow_same_name_and_age_class',
  'greenfield',
  'TEAM-04 names and age classes are not unique person identifiers'
)
on conflict do nothing;

notify pgrst,'reload schema';
