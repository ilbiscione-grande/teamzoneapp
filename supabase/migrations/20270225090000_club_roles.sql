-- Roles in the member register's person card (2026-11-11): the club admin
-- (club.memberships.manage) gives and takes back the club-wide roles -
-- Styrelse eller funktionär (club_functionary) and Medlem i klubben
-- (member) - and, through the existing team role commands, leader and
-- player in a team. Before, a club-wide role came only from an approved
-- application and could not be changed anywhere.
-- - Ending a functionary role ends its club areas (Klubbens behörigheter);
--   the club always keeps someone with members and teams, and you cannot
--   take back your own functionary role (it holds the rights you use).
-- - Areas are still given under Klubbens behörigheter: no permission is
--   widened here.

-- As in 20270223090000, with the club-wide roles and whether it is you.
create or replace function internal.get_club_member_register_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not internal.actor_has_capability(target_club_id, null, 'club.memberships.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object('people', coalesce((select jsonb_agg(entry order by entry->>'name', entry->>'person_id') from (
    select jsonb_build_object(
      'person_id', person.id,
      'name', person.display_name,
      'birth_year', person.birth_year,
      'has_account', exists (select 1 from core.person_account_links link
        where link.club_person_id = person.id and link.club_id = target_club_id and link.state = 'active'),
      'club_role', exists (select 1 from core.assignments a
        where a.club_id = target_club_id and a.club_person_id = person.id and a.team_id is null
          and a.role_package = 'club_functionary' and a.state = 'active'
          and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())),
      'club_roles', coalesce((select jsonb_agg(distinct a.role_package)
        from core.assignments a
        where a.club_id = target_club_id and a.club_person_id = person.id and a.team_id is null
          and a.role_package in ('club_functionary', 'member') and a.state = 'active'
          and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())), '[]'::jsonb),
      'is_self', internal.actor_owns_club_person(target_club_id, person.id),
      'teams', coalesce((select jsonb_agg(distinct jsonb_build_object('team_id', team.id, 'name', team.name, 'role', role_row.role))
        from (
          select ta.team_id, 'player'::text as role from core.team_assignments ta
          where ta.club_id = target_club_id and ta.club_person_id = person.id and ta.state = 'active'
          union
          select a.team_id, a.role_package from core.assignments a
          where a.club_id = target_club_id and a.club_person_id = person.id and a.team_id is not null
            and a.state = 'active' and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())
        ) role_row
        join core.teams team on team.id = role_row.team_id and team.club_id = target_club_id), '[]'::jsonb),
      'guardians', coalesce((select jsonb_agg(distinct guardian.display_name)
        from core.guardian_relations relation
        join core.club_people guardian on guardian.id = relation.guardian_person_id and guardian.status = 'active'
        where relation.club_id = target_club_id and relation.child_person_id = person.id and relation.state = 'active'
          and (relation.ends_at is null or relation.ends_at > now())), '[]'::jsonb),
      'children', coalesce((select jsonb_agg(distinct child.display_name)
        from core.guardian_relations relation
        join core.club_people child on child.id = relation.child_person_id and child.status = 'active'
        where relation.club_id = target_club_id and relation.guardian_person_id = person.id and relation.state = 'active'
          and (relation.ends_at is null or relation.ends_at > now())), '[]'::jsonb),
      'is_member', coalesce(membership.is_member, internal.club_person_is_default_member(target_club_id, person.id)),
      'member_set', membership.club_person_id is not null,
      'category', coalesce(membership.category, internal.club_member_default_category(person.birth_year)),
      'category_set', membership.category is not null,
      'revision', coalesce(membership.revision, 0),
      -- The address fee reminders go to, for someone without an account; not
      -- for a protected person.
      'email', case when not person_has_account and not coalesce(person.safeguarding_required, false)
        then person.contact_email end,
      'email_editable', not person_has_account and not coalesce(person.safeguarding_required, false)) as entry
    from core.club_people person
    cross join lateral (select exists (select 1 from core.person_account_links link
      where link.club_person_id = person.id and link.club_id = target_club_id and link.state = 'active') as person_has_account) account
    left join core.club_memberships membership on membership.club_person_id = person.id
    where person.club_id = target_club_id and person.status = 'active') register_rows), '[]'::jsonb));
end;
$$;

create or replace function internal.set_club_role_for_actor(target_club_id uuid, target_person_id uuid,
  target_role text, make_active boolean, idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); cached jsonb; result jsonb; ended uuid[];
begin
  if actor_id is null or not internal.actor_has_capability(target_club_id, null, 'club.memberships.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if idempotency_key is null or make_active is null or target_role is null
     or target_role not in ('club_functionary', 'member') then
    raise invalid_parameter_value using message = 'invalid_role';
  end if;
  select d.result into cached from internal.command_deduplication d where d.actor_profile_id = actor_id
    and d.command_type = 'club.role.set.v1' and d.idempotency_key = set_club_role_for_actor.idempotency_key;
  if cached is not null then return cached; end if;
  perform pg_advisory_xact_lock(hashtextextended('club-permissions:' || target_club_id::text, 0));
  if not exists (select 1 from core.club_people person where person.id = target_person_id
      and person.club_id = target_club_id and person.status = 'active') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if make_active then
    if not exists (select 1 from core.assignments a where a.club_id = target_club_id
        and a.club_person_id = target_person_id and a.team_id is null and a.role_package = target_role
        and a.state = 'active' and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())) then
      insert into core.assignments (club_id, team_id, club_person_id, role_package, state, starts_at, created_by)
      values (target_club_id, null, target_person_id, target_role, 'active', now(), actor_id);
    end if;
  else
    if target_role = 'club_functionary' and internal.actor_owns_club_person(target_club_id, target_person_id) then
      raise check_violation using message = 'own_club_role';
    end if;
    with closed as (
      update core.assignments a set state = 'ended', ends_at = greatest(now(), a.starts_at + interval '1 microsecond'),
        revision = a.revision + 1
      where a.club_id = target_club_id and a.club_person_id = target_person_id and a.team_id is null
        and a.role_package = target_role and a.state = 'active'
      returning a.id)
    select coalesce(array_agg(id), '{}') into ended from closed;
    -- The role's club areas end with it.
    update core.capability_grants grant_row set ends_at = greatest(now(), grant_row.starts_at + interval '1 microsecond'),
      revision = grant_row.revision + 1
    where grant_row.assignment_id = any(ended) and (grant_row.ends_at is null or grant_row.ends_at > now());
    if not internal.club_has_memberships_manager(target_club_id) then
      raise check_violation using message = 'last_memberships_manager';
    end if;
  end if;
  result := jsonb_build_object('person_id', target_person_id, 'role', target_role, 'active', make_active);
  insert into internal.command_deduplication (actor_profile_id, idempotency_key, command_type, result)
  values (actor_id, idempotency_key, 'club.role.set.v1', result);
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id,
    aggregate_revision, metadata)
  values (target_club_id, actor_id, 'club.role.set.v1', 'club_person', target_person_id, 1,
    jsonb_build_object('role', target_role, 'active', make_active));
  return result;
end;
$$;

create or replace function api.set_club_role(target_club_id uuid, target_person_id uuid, target_role text,
  make_active boolean, idempotency_key uuid)
returns jsonb language sql security invoker set search_path = '' as
$$ select internal.set_club_role_for_actor(target_club_id, target_person_id, target_role, make_active, idempotency_key) $$;

revoke all on function internal.set_club_role_for_actor(uuid, uuid, text, boolean, uuid),
  api.set_club_role(uuid, uuid, text, boolean, uuid) from public, anon, authenticated;
grant execute on function internal.set_club_role_for_actor(uuid, uuid, text, boolean, uuid),
  api.set_club_role(uuid, uuid, text, boolean, uuid) to authenticated;
notify pgrst, 'reload schema';
