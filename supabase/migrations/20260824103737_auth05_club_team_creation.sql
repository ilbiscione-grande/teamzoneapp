-- AUTH-05 atomic unofficial club and team creation.

create function internal.create_club_with_first_team_for_actor(
  club_name text,team_name text,idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); existing_result jsonb; club_id uuid:=gen_random_uuid();
 team_id uuid:=gen_random_uuid(); person_id uuid; club_person_id uuid;
 assignment_id uuid; normalized_club text:=btrim(club_name); normalized_team text:=btrim(team_name);
 slug_base text; club_slug text; capability text;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not exists(select 1 from auth.users where id=actor_id and email_confirmed_at is not null) then
    raise insufficient_privilege using message='email_not_verified';
  end if;
  if length(normalized_club) not between 2 and 120
     or length(normalized_team) not between 1 and 120 then
    raise invalid_parameter_value using message='invalid_name';
  end if;
  select result into existing_result from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='organization.club.create.v1'
    and internal.command_deduplication.idempotency_key=create_club_with_first_team_for_actor.idempotency_key;
  if existing_result is not null then return existing_result; end if;

  slug_base:=trim(both '-' from regexp_replace(
    translate(lower(normalized_club),'åäö','aao'),'[^a-z0-9]+','-','g'
  ));
  if length(slug_base)<2 then slug_base:='klubb'; end if;
  club_slug:=left(slug_base,70)||'-'||left(club_id::text,8);

  insert into core.clubs(id,name,slug,verification_status,created_by)
  values(club_id,normalized_club,club_slug,'unofficial',actor_id);
  insert into core.teams(id,club_id,name,created_by)
  values(team_id,club_id,normalized_team,actor_id);
  insert into core.persons(created_by) values(actor_id) returning id into person_id;
  insert into core.club_people(club_id,person_id,display_name,created_by)
  select club_id,person_id,coalesce(nullif(display_name,''),'Klubbadministratör'),actor_id
  from core.profiles where id=actor_id returning id into club_person_id;
  insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at,created_by)
  values(club_id,club_person_id,actor_id,'active',now(),actor_id);
  insert into core.assignments(club_id,team_id,club_person_id,role_package,state,starts_at,created_by)
  values(club_id,team_id,club_person_id,'club_functionary','active',now(),actor_id)
  returning id into assignment_id;
  foreach capability in array array['club.memberships.manage','event.manage','development.manage'] loop
    insert into core.capability_grants(
      club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by
    ) values(club_id,assignment_id,capability,'club',club_id,now(),actor_id);
  end loop;
  existing_result:=jsonb_build_object(
    'club_id',club_id,'team_id',team_id,'context_id',assignment_id
  );
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'organization.club.create.v1',existing_result);
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,
    metadata
  ) values(club_id,actor_id,'organization.club.create.v1','club',club_id,1,
    jsonb_build_object('first_team_id',team_id,'verification_status','unofficial'));
  return existing_result;
end
$$;

create function internal.create_team_in_club_for_actor(
  target_club_id uuid,team_name text,idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); normalized_team text:=btrim(team_name);
 existing_result jsonb; team_id uuid;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if length(normalized_team) not between 1 and 120 then
    raise invalid_parameter_value using message='invalid_name';
  end if;
  if not internal.actor_has_capability(target_club_id,null,'club.memberships.manage') then
    raise insufficient_privilege using message='not_found';
  end if;
  select result into existing_result from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='organization.team.create.v1'
    and internal.command_deduplication.idempotency_key=create_team_in_club_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'team_id')::uuid; end if;
  insert into core.teams(club_id,name,created_by)
  values(target_club_id,normalized_team,actor_id) returning id into team_id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'organization.team.create.v1',jsonb_build_object('team_id',team_id));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
  values(target_club_id,actor_id,'organization.team.create.v1','team',team_id,1);
  return team_id;
end
$$;

create function api.create_club_with_first_team(club_name text,team_name text,idempotency_key uuid)
returns jsonb language sql security invoker set search_path=''
as $$select internal.create_club_with_first_team_for_actor(club_name,team_name,idempotency_key)$$;
create function api.create_team_in_club(target_club_id uuid,team_name text,idempotency_key uuid)
returns uuid language sql security invoker set search_path=''
as $$select internal.create_team_in_club_for_actor(target_club_id,team_name,idempotency_key)$$;

revoke all on function internal.create_club_with_first_team_for_actor(text,text,uuid),
  internal.create_team_in_club_for_actor(uuid,text,uuid) from public,anon,authenticated;
revoke all on function api.create_club_with_first_team(text,text,uuid),
  api.create_team_in_club(uuid,text,uuid) from public,anon;
grant execute on function internal.create_club_with_first_team_for_actor(text,text,uuid),
  internal.create_team_in_club_for_actor(uuid,text,uuid) to authenticated;
grant execute on function api.create_club_with_first_team(text,text,uuid),
  api.create_team_in_club(uuid,text,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260824103737_auth05_club_team_creation','greenfield','AUTH-05 atomic unofficial club and team creation');
