-- Lagkapten och spelarråd i medlemsregistrets personkort (2026-11-11): the
-- club admin sees and sets a player's captain role and player council per
-- team in the person card, as leaders do in the player's team details
-- (20270226090000). A small command changes only those two, so the rest of
-- the team details stay untouched.

-- As in 20270225090000, with captain_role and player_council on player rows.
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
      'teams', coalesce((select jsonb_agg(distinct jsonb_build_object('team_id', team.id, 'name', team.name, 'role', role_row.role,
          'captain_role', case when role_row.role = 'player' then details.captain_role end,
          'player_council', role_row.role = 'player' and coalesce(details.player_council, false)))
        from (
          select ta.team_id, 'player'::text as role from core.team_assignments ta
          where ta.club_id = target_club_id and ta.club_person_id = person.id and ta.state = 'active'
          union
          select a.team_id, a.role_package from core.assignments a
          where a.club_id = target_club_id and a.club_person_id = person.id and a.team_id is not null
            and a.state = 'active' and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())
        ) role_row
        join core.teams team on team.id = role_row.team_id and team.club_id = target_club_id
        left join core.team_person_details details on details.team_id = role_row.team_id
          and details.club_person_id = person.id), '[]'::jsonb),
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

create or replace function internal.set_team_player_roles_for_actor(target_club_id uuid, target_team_id uuid,
  target_person_id uuid, new_captain_role text, new_player_council boolean, idempotency_key uuid)
returns bigint language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); cached jsonb; saved_revision bigint;
  armband text := nullif(btrim(new_captain_role), ''); council boolean := coalesce(new_player_council, false);
begin
  perform internal.assert_team_role_manager(target_club_id, target_team_id);
  if idempotency_key is null or (armband is not null and armband not in ('captain', 'vice_captain')) then
    raise invalid_parameter_value using message = 'invalid_captain_role';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('team-captains:' || target_team_id::text, 0));
  select d.result into cached from internal.command_deduplication d
  where d.actor_profile_id = actor_id and d.command_type = 'team.player_roles.updated.v1'
    and d.idempotency_key = set_team_player_roles_for_actor.idempotency_key;
  if cached is not null then return (cached->>'revision')::bigint; end if;
  if not internal.team_role_active(target_club_id, target_team_id, target_person_id, 'player') then
    raise check_violation using message = 'captain_needs_player_role';
  end if;
  if armband is not null then
    update core.team_person_details set captain_role = null, revision = revision + 1, updated_by = actor_id, updated_at = now()
    where team_id = target_team_id and captain_role = armband and club_person_id <> target_person_id;
  end if;
  insert into core.team_person_details (club_id, team_id, club_person_id, functions, positions, custom_titles,
    custom_positions, captain_role, player_council, revision, updated_by)
  values (target_club_id, target_team_id, target_person_id, '{}', '{}', '{}', '{}', armband, council, 1, actor_id)
  on conflict (team_id, club_person_id) do update
  set captain_role = excluded.captain_role, player_council = excluded.player_council,
    revision = core.team_person_details.revision + 1, updated_by = actor_id, updated_at = now()
  returning revision into saved_revision;
  insert into internal.command_deduplication (actor_profile_id, idempotency_key, command_type, result)
  values (actor_id, idempotency_key, 'team.player_roles.updated.v1', jsonb_build_object('revision', saved_revision));
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision, metadata)
  values (target_club_id, actor_id, 'team.player_roles.updated.v1', 'team_person', target_person_id, saved_revision,
    jsonb_build_object('team_id', target_team_id, 'captain_role', armband, 'player_council', council));
  return saved_revision;
end;
$$;

create or replace function api.set_team_player_roles(target_club_id uuid, target_team_id uuid,
  target_person_id uuid, new_captain_role text, new_player_council boolean, idempotency_key uuid)
returns bigint language sql security invoker set search_path = '' as
$$ select internal.set_team_player_roles_for_actor(target_club_id, target_team_id, target_person_id,
  new_captain_role, new_player_council, idempotency_key) $$;

revoke all on function
  internal.set_team_player_roles_for_actor(uuid, uuid, uuid, text, boolean, uuid),
  api.set_team_player_roles(uuid, uuid, uuid, text, boolean, uuid)
from public, anon, authenticated;
grant execute on function
  internal.set_team_player_roles_for_actor(uuid, uuid, uuid, text, boolean, uuid),
  api.set_team_player_roles(uuid, uuid, uuid, text, boolean, uuid)
to authenticated;

notify pgrst, 'reload schema';
