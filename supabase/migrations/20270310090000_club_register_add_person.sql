-- Medlemsregistret: whoever holds Medlemmar och lag adds a new person to the
-- club directly, without an application and without a team roster: a new
-- board member, a club functionary, a club member, or a leader in one or
-- more teams with a title (Huvudtränare, Lagledare …). An e-mail address is
-- kept as the person's contact; the app then offers an invitation code so
-- they can connect their account. The roles go through the same commands
-- as the register's person card.

create or replace function internal.create_club_person_for_actor(
  target_club_id uuid, new_display_name text, new_email text, club_roles text[],
  leader_team_ids uuid[], leader_title text, idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := auth.uid();
  cached jsonb;
  contact jsonb;
  clean_name text := btrim(coalesce(new_display_name, ''));
  clean_title text := nullif(btrim(coalesce(leader_title, '')), '');
  new_person_id uuid;
  role_value text;
  team_value uuid;
  details_revision bigint;
  result jsonb;
begin
  if actor_id is null or not internal.actor_has_capability(target_club_id, null, 'club.memberships.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  club_roles := coalesce(club_roles, '{}');
  leader_team_ids := coalesce(leader_team_ids, '{}');
  if idempotency_key is null or length(clean_name) not between 1 and 120
    or exists (select 1 from unnest(club_roles) value where value not in ('club_functionary', 'member'))
  then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if cardinality(club_roles) = 0 and cardinality(leader_team_ids) = 0 then
    raise invalid_parameter_value using message = 'no_role';
  end if;
  if exists (select 1 from unnest(leader_team_ids) value where not exists (
      select 1 from core.teams team where team.id = value and team.club_id = target_club_id
        and team.status = 'active')) then
    raise invalid_parameter_value using message = 'invalid_team';
  end if;
  select d.result into cached from internal.command_deduplication d
  where d.actor_profile_id = actor_id and d.command_type = 'club.person.create.v1'
    and d.idempotency_key = create_club_person_for_actor.idempotency_key;
  if cached is not null then return cached; end if;
  contact := internal.normalized_contact(new_email, null);

  insert into core.club_people (club_id, display_name, contact_email, created_by)
  values (target_club_id, clean_name, contact->>'email', actor_id)
  returning id into new_person_id;

  foreach role_value in array (select coalesce(array_agg(distinct value), '{}') from unnest(club_roles) value) loop
    perform internal.set_club_role_for_actor(target_club_id, new_person_id, role_value, true, gen_random_uuid());
  end loop;
  foreach team_value in array (select coalesce(array_agg(distinct value), '{}') from unnest(leader_team_ids) value) loop
    perform internal.team_role_command(target_club_id, team_value, new_person_id, null, 'leader', gen_random_uuid());
    if clean_title is not null then
      select coalesce((select detail.revision from core.team_person_details detail
        where detail.team_id = team_value and detail.club_person_id = new_person_id), 0)
      into details_revision;
      perform internal.set_team_person_details_v6_for_actor(target_club_id, team_value, new_person_id,
        array[clean_title], '{}', '{}', '{}', clean_title, null, null, null, false, details_revision,
        gen_random_uuid());
    end if;
  end loop;

  result := jsonb_build_object('person_id', new_person_id, 'email', contact->>'email');
  insert into internal.command_deduplication (actor_profile_id, idempotency_key, command_type, result)
  values (actor_id, idempotency_key, 'club.person.create.v1', result);
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id,
    aggregate_revision, metadata)
  values (target_club_id, actor_id, 'club.person.create.v1', 'club_person', new_person_id, 1,
    jsonb_build_object('club_roles', club_roles, 'leader_teams', cardinality(leader_team_ids),
      'title', clean_title, 'has_email', contact->>'email' is not null, 'source', 'member_register'));
  return result;
end
$$;

create function api.create_club_person(
  target_club_id uuid, new_display_name text, new_email text, club_roles text[],
  leader_team_ids uuid[], leader_title text, idempotency_key uuid
)
returns jsonb language sql security invoker set search_path = '' as $$
  select internal.create_club_person_for_actor(target_club_id, new_display_name, new_email, club_roles,
    leader_team_ids, leader_title, idempotency_key)
$$;

revoke all on function internal.create_club_person_for_actor(uuid, text, text, text[], uuid[], text, uuid)
  from public, anon;
grant execute on function internal.create_club_person_for_actor(uuid, text, text, text[], uuid[], text, uuid)
  to authenticated;
revoke all on function api.create_club_person(uuid, text, text, text[], uuid[], text, uuid) from public, anon;
grant execute on function api.create_club_person(uuid, text, text, text[], uuid[], text, uuid) to authenticated;

notify pgrst, 'reload schema';
