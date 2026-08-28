-- AUTH-04 membership discovery and reviewed application flow.
-- This migration is local-only until a separate hosted approval is given.

alter table core.clubs
  add column verification_status text not null default 'unofficial'
  check (verification_status in ('unofficial','pending','official','rejected','revoked'));

create table core.membership_applications (
  id uuid primary key default gen_random_uuid(),
  applicant_profile_id uuid not null references core.profiles(id),
  club_id uuid not null references core.clubs(id),
  team_id uuid not null,
  requested_role text not null
    check (requested_role in ('player','leader','guardian','club_functionary')),
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','withdrawn')),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references core.profiles(id),
  withdrawn_at timestamptz,
  revision bigint not null default 1 check (revision > 0),
  foreign key (team_id,club_id) references core.teams(id,club_id),
  check (
    (status='pending' and decided_at is null and decided_by is null and withdrawn_at is null)
    or (status in ('approved','rejected') and decided_at is not null and decided_by is not null and withdrawn_at is null)
    or (status='withdrawn' and withdrawn_at is not null and decided_at is null and decided_by is null)
  )
);

create unique index membership_applications_one_pending_target
  on core.membership_applications(applicant_profile_id,team_id,requested_role)
  where status='pending';
create index membership_applications_applicant_created
  on core.membership_applications(applicant_profile_id,created_at desc,id desc);
create index membership_applications_reviewer_queue
  on core.membership_applications(club_id,team_id,created_at,id)
  where status='pending';

alter table core.membership_applications enable row level security;
revoke all on table core.membership_applications from public,anon,authenticated;

create function internal.search_joinable_club_teams_for_actor(search_query text)
returns table(
  club_id uuid,club_name text,club_is_official boolean,team_id uuid,team_name text
)
language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); normalized_query text:=lower(btrim(search_query));
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if length(normalized_query) < 3 or length(normalized_query) > 80 then
    return;
  end if;
  return query
  select club.id,club.name,club.verification_status='official',team.id,team.name
  from core.clubs club
  join core.teams team on team.club_id=club.id and team.status='active'
  where club.status='active'
    and (lower(club.name) like '%'||normalized_query||'%'
      or lower(club.slug) like '%'||normalized_query||'%'
      or lower(team.name) like '%'||normalized_query||'%')
  order by club.verification_status='official' desc,club.name,team.name,team.id
  limit 20;
end
$$;

create function internal.list_my_membership_applications_for_actor()
returns table(
  application_id uuid,club_name text,team_name text,requested_role text,
  status text,created_at timestamptz
)
language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  return query
  select application.id,club.name,team.name,application.requested_role,
    application.status,application.created_at
  from core.membership_applications application
  join core.clubs club on club.id=application.club_id
  join core.teams team on team.id=application.team_id and team.club_id=application.club_id
  where application.applicant_profile_id=actor_id
  order by application.created_at desc,application.id desc
  limit 100;
end
$$;

create function internal.request_team_membership_for_actor(
  target_team_id uuid,requested_role text,idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); target_club_id uuid; application_id uuid; existing_result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if requested_role not in ('player','leader','guardian','club_functionary') then
    raise invalid_parameter_value using message='invalid_role';
  end if;
  select result into existing_result from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='membership.application.request.v1'
    and internal.command_deduplication.idempotency_key=request_team_membership_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'application_id')::uuid; end if;
  select club_id into target_club_id from core.teams
  where id=target_team_id and status='active';
  if target_club_id is null then raise invalid_parameter_value using message='not_found'; end if;
  if exists(select 1 from core.person_account_links link where link.profile_id=actor_id
      and link.club_id=target_club_id and link.state='active') then
    raise invalid_parameter_value using message='relation_exists';
  end if;
  insert into core.membership_applications(applicant_profile_id,club_id,team_id,requested_role)
  values(actor_id,target_club_id,target_team_id,requested_role)
  on conflict(applicant_profile_id,team_id,requested_role) where status='pending'
  do update set revision=core.membership_applications.revision+1
  returning id into application_id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'membership.application.request.v1',jsonb_build_object('application_id',application_id));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
  values(target_club_id,actor_id,'membership.application.request.v1','membership_application',application_id,1);
  return application_id;
end
$$;

create function internal.list_pending_membership_applications_for_actor(
  target_club_id uuid,target_team_id uuid default null
)
returns table(
  application_id uuid,applicant_display_name text,team_name text,
  requested_role text,created_at timestamptz
)
language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage') then
    raise insufficient_privilege using message='not_found';
  end if;
  return query
  select application.id,
    coalesce(nullif(profile.display_name,''),'Ny användare'),team.name,
    application.requested_role,application.created_at
  from core.membership_applications application
  join core.profiles profile on profile.id=application.applicant_profile_id
  join core.teams team on team.id=application.team_id and team.club_id=application.club_id
  where application.club_id=target_club_id and application.status='pending'
    and (target_team_id is null or application.team_id=target_team_id)
  order by application.created_at,application.id
  limit 100;
end
$$;

create function internal.withdraw_membership_application_for_actor(
  application_id uuid,idempotency_key uuid
)
returns void language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); row_value core.membership_applications%rowtype; existing_result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select result into existing_result from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='membership.application.withdraw.v1'
    and internal.command_deduplication.idempotency_key=withdraw_membership_application_for_actor.idempotency_key;
  if existing_result is not null then return; end if;
  select * into row_value from core.membership_applications
  where id=application_id and applicant_profile_id=actor_id for update;
  if row_value.id is null or row_value.status<>'pending' then
    raise invalid_parameter_value using message='not_found';
  end if;
  update core.membership_applications set status='withdrawn',withdrawn_at=now(),revision=revision+1
  where id=row_value.id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'membership.application.withdraw.v1',jsonb_build_object('status','withdrawn'));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
  values(row_value.club_id,actor_id,'membership.application.withdraw.v1','membership_application',row_value.id,row_value.revision+1);
end
$$;

create function internal.decide_membership_application_for_actor(
  application_id uuid,decision text,idempotency_key uuid
)
returns text language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); row_value core.membership_applications%rowtype;
 existing_result jsonb; person_id uuid; club_person_id uuid; role_assignment_id uuid;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if decision not in ('approved','rejected') then raise invalid_parameter_value using message='invalid_decision'; end if;
  select result into existing_result from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='membership.application.decide.v1'
    and internal.command_deduplication.idempotency_key=decide_membership_application_for_actor.idempotency_key;
  if existing_result is not null then return existing_result->>'status'; end if;
  select * into row_value from core.membership_applications where id=application_id for update;
  if row_value.id is null or row_value.status<>'pending'
     or not internal.actor_has_capability(row_value.club_id,row_value.team_id,'club.memberships.manage') then
    raise insufficient_privilege using message='not_found';
  end if;
  if decision='approved' then
    if exists(select 1 from core.person_account_links where profile_id=row_value.applicant_profile_id
        and club_id=row_value.club_id and state='active') then
      raise invalid_parameter_value using message='relation_exists';
    end if;
    insert into core.persons(created_by) values(actor_id) returning id into person_id;
    insert into core.club_people(club_id,person_id,display_name,created_by)
    select row_value.club_id,person_id,coalesce(nullif(profile.display_name,''),'Ny medlem'),actor_id
    from core.profiles profile where profile.id=row_value.applicant_profile_id
    returning id into club_person_id;
    insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at,created_by)
    values(row_value.club_id,club_person_id,row_value.applicant_profile_id,'active',now(),actor_id);
    insert into core.assignments(club_id,team_id,club_person_id,role_package,state,starts_at,created_by)
    values(row_value.club_id,row_value.team_id,club_person_id,row_value.requested_role,'active',now(),actor_id)
    returning id into role_assignment_id;
    if row_value.requested_role='player' then
      insert into core.team_assignments(club_id,team_id,club_person_id,starts_at,created_by)
      values(row_value.club_id,row_value.team_id,club_person_id,now(),actor_id);
    end if;
  end if;
  update core.membership_applications set status=decision,decided_at=now(),decided_by=actor_id,revision=revision+1
  where id=row_value.id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'membership.application.decide.v1',jsonb_build_object('status',decision));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
  values(row_value.club_id,actor_id,'membership.application.decide.v1','membership_application',row_value.id,row_value.revision+1);
  return decision;
end
$$;

create function api.search_joinable_club_teams(search_query text)
returns table(club_id uuid,club_name text,club_is_official boolean,team_id uuid,team_name text)
language sql stable security invoker set search_path=''
as $$select * from internal.search_joinable_club_teams_for_actor(search_query)$$;
create function api.list_my_membership_applications()
returns table(application_id uuid,club_name text,team_name text,requested_role text,status text,created_at timestamptz)
language sql stable security invoker set search_path=''
as $$select * from internal.list_my_membership_applications_for_actor()$$;
create function api.request_team_membership(target_team_id uuid,requested_role text,idempotency_key uuid)
returns uuid language sql security invoker set search_path=''
as $$select internal.request_team_membership_for_actor(target_team_id,requested_role,idempotency_key)$$;
create function api.list_pending_membership_applications(target_club_id uuid,target_team_id uuid default null)
returns table(application_id uuid,applicant_display_name text,team_name text,requested_role text,created_at timestamptz)
language sql stable security invoker set search_path=''
as $$select * from internal.list_pending_membership_applications_for_actor(target_club_id,target_team_id)$$;
create function api.withdraw_membership_application(application_id uuid,idempotency_key uuid)
returns void language sql security invoker set search_path=''
as $$select internal.withdraw_membership_application_for_actor(application_id,idempotency_key)$$;
create function api.decide_membership_application(application_id uuid,decision text,idempotency_key uuid)
returns text language sql security invoker set search_path=''
as $$select internal.decide_membership_application_for_actor(application_id,decision,idempotency_key)$$;

revoke all on function internal.search_joinable_club_teams_for_actor(text),
  internal.list_my_membership_applications_for_actor(),
  internal.list_pending_membership_applications_for_actor(uuid,uuid),
  internal.request_team_membership_for_actor(uuid,text,uuid),
  internal.withdraw_membership_application_for_actor(uuid,uuid),
  internal.decide_membership_application_for_actor(uuid,text,uuid)
from public,anon,authenticated;
revoke all on function api.search_joinable_club_teams(text),
  api.list_my_membership_applications(),api.request_team_membership(uuid,text,uuid),
  api.list_pending_membership_applications(uuid,uuid),
  api.withdraw_membership_application(uuid,uuid),api.decide_membership_application(uuid,text,uuid)
from public,anon;
grant execute on function internal.search_joinable_club_teams_for_actor(text),
  internal.list_my_membership_applications_for_actor(),
  internal.list_pending_membership_applications_for_actor(uuid,uuid),
  internal.request_team_membership_for_actor(uuid,text,uuid),
  internal.withdraw_membership_application_for_actor(uuid,uuid),
  internal.decide_membership_application_for_actor(uuid,text,uuid)
to authenticated;
grant execute on function api.search_joinable_club_teams(text),
  api.list_my_membership_applications(),api.request_team_membership(uuid,text,uuid),
  api.list_pending_membership_applications(uuid,uuid),
  api.withdraw_membership_application(uuid,uuid),api.decide_membership_application(uuid,text,uuid)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260824044909_auth04_membership_applications','greenfield','AUTH-04 local membership application flow');
