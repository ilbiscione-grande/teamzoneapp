-- Club permissions: the club's administrators give the club's areas to its
-- functionaries, as team leaders' permissions are given in a team (TEAM-10).
-- The areas: publication (publication.manage), members and teams
-- (club.memberships.manage), announcements (club.messaging.manage) and
-- referee assignment (club.referees.manage). Board, economy and safeguarding
-- stay with their own rules. Whoever holds members and teams decides, and
-- gives or takes back only what they hold themselves; the club is never left
-- without someone holding members and teams. Grants sit on the person's
-- club functionary assignment, as every capability does (never role names).

create or replace function internal.club_permission_catalog()
returns text[] language sql immutable set search_path = '' as $$
  select array['publication.manage', 'club.memberships.manage', 'club.messaging.manage', 'club.referees.manage']::text[]
$$;

-- A person's club-wide areas now, on any of their active assignments.
create or replace function internal.club_panel_capabilities(target_club_id uuid, target_person_id uuid)
returns text[] language sql stable security definer set search_path = '' as $$
  select coalesce(array(
    select distinct grant_row.capability
    from core.capability_grants grant_row
    join core.assignments assignment on assignment.id = grant_row.assignment_id and assignment.state = 'active'
      and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
    where grant_row.club_id = target_club_id and assignment.club_person_id = target_person_id
      and grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id
      and grant_row.capability = any(internal.club_permission_catalog())
      and grant_row.starts_at <= now() and (grant_row.ends_at is null or grant_row.ends_at > now())
    order by 1), '{}')
$$;

-- Someone in the club still holds members and teams.
create or replace function internal.club_has_memberships_manager(target_club_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from core.capability_grants grant_row
    join core.assignments assignment on assignment.id = grant_row.assignment_id and assignment.state = 'active'
      and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
    where grant_row.club_id = target_club_id and grant_row.capability = 'club.memberships.manage'
      and grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id
      and grant_row.starts_at <= now() and (grant_row.ends_at is null or grant_row.ends_at > now()))
$$;

-- The club's functionaries and their areas, for those who decide them.
create or replace function internal.get_club_permissions_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not internal.actor_has_capability(target_club_id, null, 'club.memberships.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object(
    'grantable', to_jsonb(array(select capability from unnest(internal.club_permission_catalog()) capability
      where internal.actor_has_capability(target_club_id, null, capability))),
    'people', coalesce((select jsonb_agg(jsonb_build_object(
        'person_id', person.id, 'name', person.display_name,
        'capabilities', to_jsonb(internal.club_panel_capabilities(target_club_id, person.id)),
        'is_self', internal.actor_owns_club_person(target_club_id, person.id))
        order by person.display_name)
      from core.club_people person
      where person.club_id = target_club_id and person.status = 'active'
        and exists (select 1 from core.assignments assignment
          where assignment.club_id = target_club_id and assignment.club_person_id = person.id
            and assignment.team_id is null and assignment.role_package = 'club_functionary'
            and assignment.state = 'active' and assignment.starts_at <= now()
            and (assignment.ends_at is null or assignment.ends_at > now()))), '[]'::jsonb));
end;
$$;

create or replace function internal.set_club_permissions_for_actor(target_club_id uuid, target_person_id uuid,
  new_capabilities text[], expected_capabilities text[], idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); cached jsonb; functionary_assignment uuid; current_caps text[]; wanted text[];
  change text; result jsonb;
begin
  if actor_id is null or not internal.actor_has_capability(target_club_id, null, 'club.memberships.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if idempotency_key is null or new_capabilities is null or expected_capabilities is null
    or array_position(new_capabilities, null) is not null
    or not new_capabilities <@ internal.club_permission_catalog() then
    raise invalid_parameter_value using message = 'invalid_permissions';
  end if;
  select d.result into cached from internal.command_deduplication d where d.actor_profile_id = actor_id
    and d.command_type = 'club.permissions.updated.v1' and d.idempotency_key = set_club_permissions_for_actor.idempotency_key;
  if cached is not null then return cached; end if;
  perform pg_advisory_xact_lock(hashtextextended('club-permissions:' || target_club_id::text, 0));
  select assignment.id into functionary_assignment from core.assignments assignment
  join core.club_people person on person.id = assignment.club_person_id and person.club_id = assignment.club_id
    and person.status = 'active'
  where assignment.club_id = target_club_id and assignment.club_person_id = target_person_id
    and assignment.team_id is null and assignment.role_package = 'club_functionary' and assignment.state = 'active'
    and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
  order by assignment.starts_at limit 1;
  if functionary_assignment is null then raise insufficient_privilege using message = 'not_found'; end if;
  current_caps := internal.club_panel_capabilities(target_club_id, target_person_id);
  wanted := coalesce(array(select distinct v from unnest(new_capabilities) v order by 1), '{}');
  if current_caps <> coalesce(array(select distinct v from unnest(expected_capabilities) v order by 1), '{}') then
    raise serialization_failure using message = 'stale_permissions';
  end if;
  -- Only what you hold yourself can be given or taken away.
  foreach change in array coalesce(array(
      select v from unnest(wanted) v where not v = any(current_caps)
      union select v from unnest(current_caps) v where not v = any(wanted)), '{}') loop
    if not internal.actor_has_capability(target_club_id, null, change) then
      raise check_violation using message = 'not_grantable';
    end if;
  end loop;
  -- Taken away: ended on every assignment of the person (deleted when it had
  -- not started yet, granted in this same instant).
  delete from core.capability_grants grant_row
  using core.assignments assignment
  where assignment.id = grant_row.assignment_id and assignment.club_person_id = target_person_id
    and grant_row.club_id = target_club_id and grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id
    and grant_row.capability = any(current_caps) and not grant_row.capability = any(wanted)
    and grant_row.starts_at >= now();
  update core.capability_grants grant_row set ends_at = now(), revision = grant_row.revision + 1
  from core.assignments assignment
  where assignment.id = grant_row.assignment_id and assignment.club_person_id = target_person_id
    and grant_row.club_id = target_club_id and grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id
    and grant_row.capability = any(current_caps) and not grant_row.capability = any(wanted)
    and grant_row.starts_at < now() and (grant_row.ends_at is null or grant_row.ends_at > now());
  insert into core.capability_grants (club_id, assignment_id, capability, scope_type, scope_id, starts_at, created_by)
  select target_club_id, functionary_assignment, v, 'club', target_club_id, now(), actor_id
  from unnest(wanted) v where not v = any(current_caps)
  on conflict (assignment_id, capability, scope_type, scope_id) do update
  set starts_at = now(), ends_at = null, revision = core.capability_grants.revision + 1, created_by = excluded.created_by;
  if not internal.club_has_memberships_manager(target_club_id) then
    raise check_violation using message = 'last_memberships_manager';
  end if;
  result := jsonb_build_object('capabilities', to_jsonb(wanted));
  insert into internal.command_deduplication (actor_profile_id, idempotency_key, command_type, result)
  values (actor_id, idempotency_key, 'club.permissions.updated.v1', result);
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision, metadata)
  values (target_club_id, actor_id, 'club.permissions.updated.v1', 'club_person', target_person_id, 1,
    jsonb_build_object('from', to_jsonb(current_caps), 'to', to_jsonb(wanted)));
  return result;
end;
$$;

create or replace function api.get_club_permissions(target_club_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_club_permissions_for_actor(target_club_id) $$;
create or replace function api.set_club_permissions(target_club_id uuid, target_person_id uuid,
  new_capabilities text[], expected_capabilities text[], idempotency_key uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.set_club_permissions_for_actor(target_club_id, target_person_id, new_capabilities,
    expected_capabilities, idempotency_key) $$;

revoke all on function
  internal.club_permission_catalog(), internal.club_panel_capabilities(uuid, uuid), internal.club_has_memberships_manager(uuid),
  internal.get_club_permissions_for_actor(uuid), internal.set_club_permissions_for_actor(uuid, uuid, text[], text[], uuid),
  api.get_club_permissions(uuid), api.set_club_permissions(uuid, uuid, text[], text[], uuid)
from public, anon, authenticated;
grant execute on function
  internal.get_club_permissions_for_actor(uuid), internal.set_club_permissions_for_actor(uuid, uuid, text[], text[], uuid),
  api.get_club_permissions(uuid), api.set_club_permissions(uuid, uuid, text[], text[], uuid)
to authenticated;
notify pgrst, 'reload schema';
