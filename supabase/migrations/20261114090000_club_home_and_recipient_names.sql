-- UX review, club functionary without a team: a Home for the club (the
-- tasks your club permissions give, the club's teams with their next
-- activities, your name and board offices), and recipient names that fall
-- back to the person's name in the club, with the teams they belong to.

-- The club's Home for a context without a team. Counts only for the
-- permissions you hold; the teams and their coming activities (title, type,
-- time and place only) for those with a club-wide role.
create or replace function internal.get_club_home_for_actor(target_context_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  actor_context record;
  own_person_ids uuid[];
  own_name text;
  can_board boolean;
  can_economy boolean;
  can_members boolean;
begin
  if auth.uid() is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  select * into actor_context from internal.get_my_contexts_for_actor()
  where context_id = target_context_id;
  if actor_context.context_id is null or actor_context.team_id is not null then
    raise insufficient_privilege using message = 'not_found';
  end if;

  select array_agg(link.club_person_id), min(person.display_name)
  into own_person_ids, own_name
  from core.person_account_links link
  join core.club_people person on person.id = link.club_person_id and person.club_id = link.club_id
  where link.profile_id = auth.uid() and link.club_id = actor_context.club_id and link.state = 'active';

  can_board := internal.actor_has_capability(actor_context.club_id, null, 'board.read');
  can_economy := internal.actor_has_capability(actor_context.club_id, null, 'economy.read');
  can_members := internal.actor_has_capability(actor_context.club_id, null, 'club.memberships.manage');

  return jsonb_build_object(
    'club_id', actor_context.club_id,
    'own_name', own_name,
    'own_offices', coalesce((
      select jsonb_agg(distinct mandate.office)
      from core.board_mandates mandate
      join core.assignments assignment on assignment.id = mandate.assignment_id and assignment.club_id = mandate.club_id
      where mandate.club_id = actor_context.club_id and mandate.state = 'active'
        and mandate.starts_at <= now() and mandate.ends_at > now()
        and assignment.club_person_id = any(own_person_ids)
    ), '[]'::jsonb),
    'board', case when can_board then jsonb_build_object(
      'active_mandates', (select count(*) from core.board_mandates mandate
        where mandate.club_id = actor_context.club_id and mandate.state = 'active'
          and mandate.starts_at <= now() and mandate.ends_at > now()),
      'pending_changes', (select count(*) from core.board_mandate_changes change
        where change.club_id = actor_context.club_id and change.state = 'pending')
    ) end,
    'economy', case when can_economy then jsonb_build_object(
      'accounts', (select count(*) from core.economy_accounts account
        where account.club_id = actor_context.club_id and account.state = 'active'),
      'pending_entries', (select count(*) from core.economy_ledger_entries entry
        where entry.club_id = actor_context.club_id and entry.state = 'pending')
    ) end,
    'members', case when can_members then jsonb_build_object(
      'pending_applications', (select count(*) from core.membership_applications application
        where application.club_id = actor_context.club_id and application.status = 'pending'),
      'pending_team_requests', (select count(*) from core.team_creation_requests request
        where request.club_id = actor_context.club_id and request.state = 'pending')
    ) end,
    'can_announce', internal.actor_has_capability(actor_context.club_id, null, 'club.messaging.manage'),
    'teams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'team_id', team.id,
        'name', team.name,
        'member_count', (select count(*) from core.assignments assignment
          where assignment.club_id = team.club_id and assignment.team_id = team.id
            and assignment.state = 'active' and assignment.starts_at <= now()
            and (assignment.ends_at is null or assignment.ends_at > now())),
        'upcoming', coalesce((
          select jsonb_agg(jsonb_build_object(
            'title', upcoming.title, 'event_type', upcoming.event_type,
            'starts_at', upcoming.starts_at, 'ends_at', upcoming.ends_at,
            'all_day', upcoming.all_day, 'location_name', upcoming.location_name
          ) order by upcoming.starts_at)
          from (
            select event_row.title, event_row.event_type, event_row.starts_at,
              event_row.ends_at, event_row.all_day, location.name location_name
            from core.events event_row
            join core.event_teams relation on relation.event_id = event_row.id
              and relation.club_id = event_row.club_id and relation.team_id = team.id
            left join core.event_locations location on location.id = event_row.location_id
            where event_row.club_id = team.club_id and event_row.state = 'scheduled'
              and event_row.archived_at is null and event_row.ends_at > now()
            order by event_row.starts_at
            limit 5
          ) upcoming
        ), '[]'::jsonb)
      ) order by team.name)
      from core.teams team
      where team.club_id = actor_context.club_id and team.status = 'active'
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function api.get_club_home(target_context_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select internal.get_club_home_for_actor(target_context_id)
$$;

revoke all on function internal.get_club_home_for_actor(uuid), api.get_club_home(uuid) from public, anon, authenticated;
grant execute on function internal.get_club_home_for_actor(uuid), api.get_club_home(uuid) to authenticated;

-- As in 20260831045035, with the person's name in the club when the account
-- has none, and the teams they are in. One row per account and role.
drop function if exists api.resolve_allowed_recipients(uuid, text);
drop function if exists internal.resolve_allowed_recipients_for_actor(uuid, text);

create function internal.resolve_allowed_recipients_for_actor(
  target_context_id uuid,
  search_text text default null
)
returns table(profile_id uuid, display_name text, role_package text, team_names text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_context record;
begin
  if auth.uid() is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;

  select * into actor_context
  from internal.get_my_contexts_for_actor()
  where context_id = target_context_id;

  if actor_context.context_id is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if search_text is not null and length(search_text) > 80 then
    raise invalid_parameter_value using message = 'invalid_search';
  end if;

  return query
  select candidate.profile_id, candidate.display_name, candidate.role_package,
    string_agg(distinct candidate.team_name, ', ' order by candidate.team_name)
  from (
    select link.profile_id,
      coalesce(nullif(btrim(profile.display_name), ''), person.display_name) display_name,
      assignment.role_package,
      team.name team_name
    from core.assignments assignment
    join core.person_account_links link
      on link.club_id = assignment.club_id
     and link.club_person_id = assignment.club_person_id
     and link.state = 'active'
    join core.profiles profile on profile.id = link.profile_id
    join core.club_people person on person.id = link.club_person_id and person.club_id = link.club_id
    left join core.teams team on team.id = assignment.team_id and team.club_id = assignment.club_id
    where assignment.club_id = actor_context.club_id
      and (actor_context.team_id is null or assignment.team_id = actor_context.team_id)
      and assignment.state = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
      and internal.messaging_relationship_allowed(
        auth.uid(),
        link.profile_id,
        actor_context.club_id,
        actor_context.team_id
      )
  ) candidate
  where search_text is null
    or candidate.display_name ilike
      '%' || replace(replace(left(btrim(search_text), 80), '%', '\%'), '_', '\_') || '%'
      escape '\'
  group by candidate.profile_id, candidate.display_name, candidate.role_package
  order by candidate.display_name
  limit 50;
end;
$$;

create function api.resolve_allowed_recipients(context_id uuid, query text default null)
returns table(profile_id uuid, display_name text, role_package text, team_names text)
language sql stable security invoker set search_path = '' as $$
  select * from internal.resolve_allowed_recipients_for_actor(context_id, query)
$$;

revoke all on function internal.resolve_allowed_recipients_for_actor(uuid, text) from public, anon, authenticated;
revoke all on function api.resolve_allowed_recipients(uuid, text) from public, anon;
grant execute on function internal.resolve_allowed_recipients_for_actor(uuid, text) to authenticated;
grant execute on function api.resolve_allowed_recipients(uuid, text) to authenticated;
