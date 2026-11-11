-- Applying to the club itself (2026-11-11): before, an application and a
-- join code always named a team, and a club functionary was tied to that
-- team. Now one can apply to the club, without a team:
-- - member: a member of the club without a team (supporting member,
--   parent, volunteer). A new assignment role, club-wide only, with no
--   capabilities; it gives a club context and counts as a member in the
--   register.
-- - club_functionary: board or functionary, club-wide. Approval gives the
--   club assignment only; offices and rights are still granted by the club
--   admin (Klubbens behörigheter) - no permission is widened here.
-- A club code is a join code without a team. Club applications are
-- reviewed by the club admin (club.memberships.manage) in the same queue.
-- The functions are their live versions with the club added.

alter table core.membership_applications alter column team_id drop not null;
alter table core.membership_applications drop constraint membership_applications_requested_role_check;
alter table core.membership_applications add constraint membership_applications_requested_role_check
  check (requested_role in ('player', 'leader', 'guardian', 'club_functionary', 'member'));
alter table core.membership_applications drop constraint membership_applications_approved_role_check;
alter table core.membership_applications add constraint membership_applications_approved_role_check
  check (approved_role is null or approved_role in ('player', 'leader', 'guardian', 'club_functionary', 'member'));
alter table core.membership_applications add constraint membership_applications_scope_check
  check ((team_id is null and requested_role in ('member', 'club_functionary'))
    or (team_id is not null and requested_role <> 'member'));
create unique index membership_applications_one_pending_club
  on core.membership_applications (applicant_profile_id, club_id, requested_role)
  where status = 'pending' and team_id is null;

alter table core.team_join_codes alter column team_id drop not null;
alter table core.team_join_codes drop constraint team_join_codes_requested_role_check;
alter table core.team_join_codes add constraint team_join_codes_requested_role_check
  check (requested_role in ('player', 'leader', 'guardian', 'club_functionary', 'member'));
alter table core.team_join_codes add constraint team_join_codes_scope_check
  check ((team_id is null and requested_role in ('member', 'club_functionary'))
    or (team_id is not null and requested_role <> 'member'));

alter table core.assignments drop constraint assignments_role_package_check;
alter table core.assignments add constraint assignments_role_package_check
  check (role_package in ('player', 'leader', 'guardian', 'club_functionary', 'guest', 'referee', 'referee_assigner', 'member'));
alter table core.assignments add constraint assignments_member_club_wide check (role_package <> 'member' or team_id is null);

-- As in 20270215090000, with the club members.
create or replace function internal.club_person_is_default_member(target_club_id uuid, target_person_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from core.team_assignments ta
      where ta.club_id = target_club_id and ta.club_person_id = target_person_id and ta.state = 'active')
    or exists (select 1 from core.assignments a
      where a.club_id = target_club_id and a.club_person_id = target_person_id and a.state = 'active'
        and a.role_package in ('player', 'leader', 'club_functionary', 'member')
        and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now()))
$$;

-- Apply to the club: member or club_functionary.
create or replace function internal.request_club_membership_for_actor(target_club_id uuid, requested_role text,
  idempotency_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $function$
#variable_conflict use_column
declare actor_id uuid := auth.uid(); application_id uuid; existing_result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if requested_role is null or requested_role not in ('member', 'club_functionary') then
    raise invalid_parameter_value using message = 'invalid_role';
  end if;
  select result into existing_result from internal.command_deduplication
  where actor_profile_id = actor_id and command_type = 'membership.application.request.v1'
    and internal.command_deduplication.idempotency_key = request_club_membership_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'application_id')::uuid; end if;
  if not exists (select 1 from core.clubs where id = target_club_id and status = 'active') then
    raise invalid_parameter_value using message = 'not_found';
  end if;
  if exists (select 1 from core.person_account_links link where link.profile_id = actor_id
      and link.club_id = target_club_id and link.state = 'active') then
    raise invalid_parameter_value using message = 'relation_exists';
  end if;
  insert into core.membership_applications (applicant_profile_id, club_id, team_id, requested_role)
  values (actor_id, target_club_id, null, request_club_membership_for_actor.requested_role)
  on conflict (applicant_profile_id, club_id, requested_role) where status = 'pending' and team_id is null
  do update set revision = core.membership_applications.revision + 1
  returning id into application_id;
  insert into internal.command_deduplication (actor_profile_id, idempotency_key, command_type, result)
  values (actor_id, idempotency_key, 'membership.application.request.v1', jsonb_build_object('application_id', application_id));
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision)
  values (target_club_id, actor_id, 'membership.application.request.v1', 'membership_application', application_id, 1);
  return application_id;
end
$function$;

create or replace function api.request_club_membership(target_club_id uuid, requested_role text, idempotency_key uuid)
returns uuid language sql security invoker set search_path = '' as $$
  select internal.request_club_membership_for_actor(target_club_id, requested_role, idempotency_key) $$;

-- As live, with codes for the club (no team).
create or replace function internal.claim_team_join_code_for_actor(raw_token text, idempotency_key uuid)
 returns uuid language plpgsql security definer set search_path to '' as $function$
declare actor_id uuid:=auth.uid(); code core.team_join_codes%rowtype; existing jsonb; application_id uuid;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='roster.team_code.claim.v1'
  and internal.command_deduplication.idempotency_key=claim_team_join_code_for_actor.idempotency_key;
 if existing is not null then return (existing->>'application_id')::uuid; end if;
 select * into code from core.team_join_codes where token_hash=extensions.digest(raw_token,'sha256') for update;
 if code.id is null or code.state<>'issued' or code.expires_at<=now() or code.use_count>=code.max_uses
 then raise invalid_parameter_value using message='invalid_or_expired_token'; end if;
 if exists(select 1 from core.person_account_links where profile_id=actor_id and club_id=code.club_id and state='active')
 then raise invalid_parameter_value using message='relation_exists'; end if;
 if code.team_id is null then
  insert into core.membership_applications(applicant_profile_id,club_id,team_id,requested_role)
  values(actor_id,code.club_id,null,code.requested_role)
  on conflict(applicant_profile_id,club_id,requested_role) where status='pending' and team_id is null
  do update set revision=core.membership_applications.revision+1 returning id into application_id;
 else
  insert into core.membership_applications(applicant_profile_id,club_id,team_id,requested_role)
  values(actor_id,code.club_id,code.team_id,code.requested_role)
  on conflict(applicant_profile_id,team_id,requested_role) where status='pending'
  do update set revision=core.membership_applications.revision+1 returning id into application_id;
 end if;
 update core.team_join_codes set use_count=use_count+1,revision=revision+1 where id=code.id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.team_code.claim.v1',jsonb_build_object('application_id',application_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
 values(code.club_id,actor_id,'roster.team_code.claim.v1','membership_application',application_id,1);
 return application_id;
end $function$;

-- As live, with codes for the club: no team, member or club_functionary.
create or replace function internal.issue_team_join_code_for_actor(target_club_id uuid, target_team_id uuid,
  requested_role text, raw_token text, expires_at timestamp with time zone, max_uses integer, idempotency_key uuid)
 returns uuid language plpgsql security definer set search_path to '' as $function$
declare actor_id uuid:=auth.uid(); code_id uuid; secret_id uuid; existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
    or not (
      (target_team_id is null and exists(select 1 from core.clubs where id=target_club_id and status='active'))
      or exists(select 1 from core.teams where id=target_team_id and club_id=target_club_id and status='active'))
 then raise insufficient_privilege using message='not_found'; end if;
 if requested_role is null
    or (target_team_id is null and requested_role not in ('member','club_functionary'))
    or (target_team_id is not null and requested_role not in ('player','leader','guardian','club_functionary'))
    or length(raw_token)<32 or expires_at<=now() or expires_at>now()+interval '90 days'
    or max_uses not between 1 and 500
 then raise invalid_parameter_value using message='invalid_input'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='roster.team_code.issue.v1'
  and internal.command_deduplication.idempotency_key=issue_team_join_code_for_actor.idempotency_key;
 if existing is not null then return (existing->>'code_id')::uuid; end if;
 code_id:=gen_random_uuid();
 select vault.create_secret(raw_token,'team_join_code_'||code_id::text,'Encrypted TeamZone team join code') into secret_id;
 insert into core.team_join_codes(id,club_id,team_id,token_hash,vault_secret_id,requested_role,expires_at,max_uses,created_by)
 values(code_id,target_club_id,target_team_id,extensions.digest(raw_token,'sha256'),secret_id,requested_role,expires_at,max_uses,actor_id);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.team_code.issue.v1',jsonb_build_object('code_id',code_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
 values(target_club_id,actor_id,'roster.team_code.issue.v1','team_join_code',code_id,1);
 return code_id;
end $function$;

-- The club's active codes for the club admin: role, expiry and uses.
create or replace function internal.list_club_join_codes_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_has_capability(target_club_id, null, 'club.memberships.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('code_id', code.id, 'requested_role', code.requested_role,
      'expires_at', code.expires_at, 'use_count', code.use_count, 'max_uses', code.max_uses,
      'recoverable', code.vault_secret_id is not null) order by code.created_at desc)
    from core.team_join_codes code
    where code.club_id = target_club_id and code.team_id is null and code.state = 'issued'
      and code.expires_at > now() and code.use_count < code.max_uses), '[]'::jsonb);
end;
$$;

create or replace function api.list_club_join_codes(target_club_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.list_club_join_codes_for_actor(target_club_id) $$;

-- As live, with the club roles and their scope.
create or replace function internal.decide_membership_application_v2(application_id uuid, decision text, approved_role text, idempotency_key uuid)
 returns text language plpgsql security definer set search_path to '' as $function$
declare
  actor_id uuid:=auth.uid();
  row_value core.membership_applications%rowtype;
  selected_role text;
  result text;
  existing_result jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;
  if decision not in ('approved','rejected') then
    raise invalid_parameter_value using message='invalid_decision';
  end if;

  select dedupe.result into existing_result
  from internal.command_deduplication dedupe
  where dedupe.actor_profile_id=actor_id
    and dedupe.command_type='membership.application.decide.v2'
    and dedupe.idempotency_key=decide_membership_application_v2.idempotency_key;
  if existing_result is not null then
    return existing_result->>'status';
  end if;

  select * into row_value
  from core.membership_applications application
  where application.id=decide_membership_application_v2.application_id
  for update;
  if row_value.id is null or row_value.status<>'pending'
     or not (
       internal.actor_has_capability(
         row_value.club_id,row_value.team_id,'club.memberships.manage'
       )
       or internal.actor_has_capability(
         row_value.club_id,row_value.team_id,'team.roster.manage'
       )
     ) then
    raise insufficient_privilege using message='not_found';
  end if;

  selected_role:=case
    when decision='approved' then coalesce(approved_role,row_value.requested_role)
    else row_value.requested_role
  end;
  if selected_role not in ('player','leader','guardian','club_functionary','member')
     or (row_value.team_id is null and selected_role not in ('member','club_functionary'))
     or (row_value.team_id is not null and selected_role='member') then
    raise invalid_parameter_value using message='invalid_role';
  end if;

  if decision='approved' and selected_role<>row_value.requested_role then
    -- The v1 command creates the assignment from requested_role. Change it
    -- only while holding the row lock, then restore the applicant's request.
    update core.membership_applications
    set requested_role=selected_role
    where id=row_value.id;
  end if;

  result:=internal.decide_membership_application_for_actor(
    row_value.id,decision,idempotency_key
  );

  update core.membership_applications
  set requested_role=row_value.requested_role,
      approved_role=case when decision='approved' then selected_role else null end
  where id=row_value.id;

  if decision='approved' and selected_role<>row_value.requested_role then
    insert into audit.command_events(
      club_id,actor_profile_id,command_type,aggregate_type,
      aggregate_id,aggregate_revision,metadata
    ) values (
      row_value.club_id,actor_id,'membership.application.role_override.v1',
      'membership_application',row_value.id,row_value.revision+1,
      jsonb_build_object(
        'requested_role',row_value.requested_role,
        'approved_role',selected_role,
        'team_id',row_value.team_id
      )
    );
  end if;

  insert into internal.command_deduplication(
    actor_profile_id,idempotency_key,command_type,result
  ) values (
    actor_id,idempotency_key,'membership.application.decide.v2',
    jsonb_build_object('status',result,'approved_role',selected_role)
  );
  return result;
end
$function$;

-- As in 20270219090000; a club application has no team (team_name '').
create or replace function internal.list_pending_membership_applications_for_actor(target_club_id uuid, target_team_id uuid default null)
returns table(application_id uuid, applicant_display_name text, team_name text, requested_role text,
  created_at timestamptz, applicant_email text, source text)
language plpgsql stable security definer set search_path to '' as $function$
declare actor_id uuid:=auth.uid();
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not (
      internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
      or (
        target_team_id is not null
        and internal.actor_has_capability(
          target_club_id,target_team_id,'team.roster.manage'
        )
      )
    ) then
    raise insufficient_privilege using message='not_found';
  end if;
  return query
  select application.id,
    coalesce(nullif(profile.display_name,''),'Ny användare'),coalesce(team.name,''),
    application.requested_role,application.created_at,
    account.email::text,
    case when exists (select 1 from audit.command_events event
        where event.aggregate_type='membership_application' and event.aggregate_id=application.id
          and event.command_type='roster.team_code.claim.v1')
      then 'team_code' else 'search' end
  from core.membership_applications application
  join core.profiles profile on profile.id=application.applicant_profile_id
  left join core.teams team on team.id=application.team_id and team.club_id=application.club_id
  left join auth.users account on account.id=application.applicant_profile_id
  where application.club_id=target_club_id and application.status='pending'
    and (target_team_id is null or application.team_id=target_team_id)
    and (application.team_id is null or team.id is not null)
  order by application.created_at,application.id
  limit 100;
end
$function$;

-- As live; a club application has no team (team_name '').
create or replace function internal.list_my_membership_applications_for_actor()
 returns table(application_id uuid, club_name text, team_name text, requested_role text, status text, created_at timestamp with time zone)
 language plpgsql stable security definer set search_path to '' as $function$
declare actor_id uuid:=auth.uid();
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  return query
  select application.id,club.name,coalesce(team.name,''),application.requested_role,
    application.status,application.created_at
  from core.membership_applications application
  join core.clubs club on club.id=application.club_id
  left join core.teams team on team.id=application.team_id and team.club_id=application.club_id
  where application.applicant_profile_id=actor_id
    and (application.team_id is null or team.id is not null)
  order by application.created_at desc,application.id desc
  limit 100;
end
$function$;

-- As live, with the clubs themselves (team_id null) before their teams.
create or replace function internal.search_joinable_club_teams_for_actor(search_query text)
 returns table(club_id uuid, club_name text, club_is_official boolean, team_id uuid, team_name text)
 language plpgsql stable security definer set search_path to '' as $function$
declare actor_id uuid:=auth.uid(); normalized_query text:=lower(btrim(search_query));
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if length(normalized_query) < 3 or length(normalized_query) > 80 then
    return;
  end if;
  return query
  select found.club_id, found.club_name, found.official, found.team_id, found.team_name from (
    select club.id club_id,club.name club_name,club.verification_status='official' official,
      null::uuid team_id,null::text team_name
    from core.clubs club
    where club.status='active'
      and (lower(club.name) like '%'||normalized_query||'%'
        or lower(club.slug) like '%'||normalized_query||'%')
    union all
    select club.id,club.name,club.verification_status='official',team.id,team.name
    from core.clubs club
    join core.teams team on team.club_id=club.id and team.status='active'
    where club.status='active'
      and (lower(club.name) like '%'||normalized_query||'%'
        or lower(club.slug) like '%'||normalized_query||'%'
        or lower(team.name) like '%'||normalized_query||'%')
  ) found
  order by found.official desc,found.club_name,found.club_id,found.team_name nulls first,found.team_id
  limit 30;
end
$function$;

revoke all on function internal.request_club_membership_for_actor(uuid, text, uuid),
  api.request_club_membership(uuid, text, uuid),
  internal.list_club_join_codes_for_actor(uuid), api.list_club_join_codes(uuid)
from public, anon, authenticated;
grant execute on function internal.request_club_membership_for_actor(uuid, text, uuid),
  api.request_club_membership(uuid, text, uuid),
  internal.list_club_join_codes_for_actor(uuid), api.list_club_join_codes(uuid)
to authenticated;
notify pgrst, 'reload schema';
