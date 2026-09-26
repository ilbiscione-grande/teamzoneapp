-- Exact birth date is private club-person data. General roster projections
-- expose only its year; exact date is limited to the existing management
-- projection and write capability.

alter table core.club_people add column birth_date date;
alter table core.club_people add constraint club_people_birth_date_range_check
  check (birth_date is null or birth_date between date '1900-01-01' and date '2100-01-01');

create or replace function internal.list_club_people_for_actor(target_club_id uuid,target_team_id uuid default null)
returns table(club_person_id uuid,display_name text,age_class text,safeguarding_required boolean,
 team_id uuid,team_name text,assignment_state text,assignment_starts_at timestamptz,assignment_ends_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.view')
  and not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
 then raise insufficient_privilege using message='not_found'; end if;
 return query select person.id,person.display_name,
  coalesce(extract(year from person.birth_date)::integer::text,person.age_class),
  person.safeguarding_required,home.team_id,team.name,home.state,home.starts_at,home.ends_at
 from core.club_people person
 join lateral(select assignment.* from core.team_assignments assignment
  where assignment.club_person_id=person.id and assignment.club_id=person.club_id
   and (target_team_id is null or assignment.team_id=target_team_id)
  order by assignment.state='active' desc,assignment.starts_at desc,assignment.id desc limit 1) home on true
 join core.teams team on team.id=home.team_id and team.club_id=home.club_id
 where person.club_id=target_club_id and person.status in('active','ended')
 order by home.state='active' desc,person.display_name,person.id;
end
$$;

create function internal.create_roster_person_v2_for_actor(
 target_club_id uuid,target_team_id uuid,new_display_name text,
 new_birth_date date,starts_at timestamptz,idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); result_id uuid; existing_result jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select result into existing_result from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='roster.person.create.v1'
   and internal.command_deduplication.idempotency_key=create_roster_person_v2_for_actor.idempotency_key;
 if existing_result is not null then return(existing_result->>'club_person_id')::uuid; end if;
 if new_birth_date is null or new_birth_date>current_date
   or new_birth_date<current_date-interval '120 years'
 then raise invalid_parameter_value using message='invalid_birth_date'; end if;
 result_id:=internal.create_roster_person_for_actor(
   target_club_id,target_team_id,new_display_name,
   extract(year from new_birth_date)::integer::text,starts_at,idempotency_key);
 update core.club_people set birth_date=new_birth_date where id=result_id and club_id=target_club_id;
 return result_id;
end
$$;

create function internal.update_roster_person_v2_for_actor(
 target_club_id uuid,target_team_id uuid,target_club_person_id uuid,
 new_display_name text,new_birth_date date,expected_revision bigint,idempotency_key uuid
)
returns bigint language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); result_revision bigint; existing_result jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select result into existing_result from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='roster.person.update.v1'
   and internal.command_deduplication.idempotency_key=update_roster_person_v2_for_actor.idempotency_key;
 if existing_result is not null then return(existing_result->>'revision')::bigint; end if;
 if new_birth_date is null or new_birth_date>current_date
   or new_birth_date<current_date-interval '120 years'
 then raise invalid_parameter_value using message='invalid_birth_date'; end if;
 result_revision:=internal.update_roster_person_for_actor(
   target_club_id,target_team_id,target_club_person_id,new_display_name,
   extract(year from new_birth_date)::integer::text,expected_revision,idempotency_key);
 update core.club_people set birth_date=new_birth_date
  where id=target_club_person_id and club_id=target_club_id;
 return result_revision;
end
$$;

create function internal.get_roster_person_details_v2_for_actor(
 target_club_id uuid,target_team_id uuid,target_club_person_id uuid
)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare result jsonb; exact_birth_date date;
begin
 result:=internal.get_roster_person_details_for_actor(
  target_club_id,target_team_id,target_club_person_id);
 if result ? 'person_revision' then
  select birth_date into exact_birth_date from core.club_people
   where id=target_club_person_id and club_id=target_club_id;
  if exact_birth_date is not null then
   result:=jsonb_set(result,'{management,birth_date}',to_jsonb(exact_birth_date),true);
  end if;
 end if;
 return result;
end
$$;

create function api.create_roster_person_v2(target_club_id uuid,target_team_id uuid,
 display_name text,birth_date date,starts_at timestamptz,idempotency_key uuid)
returns uuid language sql security invoker set search_path=''
as $$select internal.create_roster_person_v2_for_actor(target_club_id,target_team_id,display_name,birth_date,starts_at,idempotency_key)$$;

create function api.update_roster_person_v2(target_club_id uuid,target_team_id uuid,
 target_club_person_id uuid,display_name text,birth_date date,expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path=''
as $$select internal.update_roster_person_v2_for_actor(target_club_id,target_team_id,target_club_person_id,display_name,birth_date,expected_revision,idempotency_key)$$;

create function api.get_roster_person_details_v2(target_club_id uuid,target_team_id uuid,target_club_person_id uuid)
returns jsonb language sql stable security invoker set search_path=''
as $$select internal.get_roster_person_details_v2_for_actor(target_club_id,target_team_id,target_club_person_id)$$;

revoke all on function internal.create_roster_person_v2_for_actor(uuid,uuid,text,date,timestamptz,uuid),
 internal.update_roster_person_v2_for_actor(uuid,uuid,uuid,text,date,bigint,uuid),
 internal.get_roster_person_details_v2_for_actor(uuid,uuid,uuid),
 api.create_roster_person_v2(uuid,uuid,text,date,timestamptz,uuid),
 api.update_roster_person_v2(uuid,uuid,uuid,text,date,bigint,uuid),
 api.get_roster_person_details_v2(uuid,uuid,uuid)
from public,anon,authenticated;
grant execute on function internal.create_roster_person_v2_for_actor(uuid,uuid,text,date,timestamptz,uuid),
 internal.update_roster_person_v2_for_actor(uuid,uuid,uuid,text,date,bigint,uuid),
 internal.get_roster_person_details_v2_for_actor(uuid,uuid,uuid),
 api.create_roster_person_v2(uuid,uuid,text,date,timestamptz,uuid),
 api.update_roster_person_v2(uuid,uuid,uuid,text,date,bigint,uuid),
 api.get_roster_person_details_v2(uuid,uuid,uuid)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260913075009_team04_birth_date_picker','greenfield',
 'TEAM-04 typed private birth date; general roster exposes birth year only');
notify pgrst,'reload schema';
