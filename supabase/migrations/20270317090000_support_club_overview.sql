-- Supportens klubböversikt (adminsidan för TeamZones support, del 1).
--
-- Support could only see clubs, their admins and their boards by querying
-- the database. Two read functions, for support administrators only:
--
-- * api.list_clubs_for_support(): every club with its status, verification,
--   active teams and people, accounts, admins who can sign in (the rule from
--   20270316090000_club_keeps_an_admin), board mandates, whether the board is
--   forming, and pending board changes with the oldest one. Counts only, no
--   names. Clubs that need support come first.
-- * api.get_club_for_support(club): the names of the club's admins, board
--   and pending board changes, and its teams. Names across every club is a
--   wider right than any club role has, so each opening is written to
--   audit.command_events (support.club_viewed).
--
-- Neither changes anything in the club.

create or replace function internal.list_clubs_for_support_for_actor()
returns table(
  club_id uuid, club_name text, club_status text, verification_status text,
  created_at timestamptz, team_count integer, people_count integer,
  account_count integer, admin_count integer, board_mandate_count integer,
  board_forming boolean, pending_board_changes integer,
  oldest_pending_board_change timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return query
    select club.id, club.name, club.status, club.verification_status, club.created_at,
      (select count(*)::integer from core.teams team
        where team.club_id = club.id and team.status = 'active'),
      (select count(*)::integer from core.club_people person
        where person.club_id = club.id and person.status = 'active'),
      (select count(distinct link.profile_id)::integer from core.person_account_links link
        where link.club_id = club.id and link.state = 'active'),
      (select count(distinct link.profile_id)::integer from core.capability_grants grant_row
        join core.assignments assignment on assignment.id = grant_row.assignment_id
          and assignment.club_id = grant_row.club_id and assignment.state = 'active'
          and assignment.starts_at <= now() and assignment.ends_at is null
        join core.person_account_links link on link.club_person_id = assignment.club_person_id
          and link.club_id = assignment.club_id and link.state = 'active'
        where grant_row.club_id = club.id and grant_row.capability = 'club.memberships.manage'
          and grant_row.scope_type = 'club' and grant_row.scope_id = club.id
          and grant_row.starts_at <= now() and grant_row.ends_at is null),
      (select count(*)::integer from core.board_mandates mandate
        where mandate.club_id = club.id and mandate.state = 'active'
          and mandate.starts_at <= now() and mandate.ends_at > now()),
      internal.board_forming(club.id),
      pending.n, pending.oldest
    from core.clubs club
    cross join lateral (select count(*)::integer n, min(change.created_at) oldest
      from core.board_mandate_changes change
      where change.club_id = club.id and change.state = 'pending') pending
    order by
      case when club.status = 'active' and not internal.club_has_admin_with_account(club.id)
        then 0 when pending.n > 0 then 1 else 2 end,
      club.name, club.id;
end
$$;

create or replace function internal.get_club_for_support_for_actor(target_club_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  club_row core.clubs%rowtype;
  result jsonb;
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select * into club_row from core.clubs club where club.id = target_club_id;
  if club_row.id is null then
    raise invalid_parameter_value using message = 'not_found';
  end if;

  result := jsonb_build_object(
    'club_id', club_row.id,
    'club_name', club_row.name,
    'club_status', club_row.status,
    'verification_status', club_row.verification_status,
    'created_at', club_row.created_at,
    'has_admin_with_account', internal.club_has_admin_with_account(club_row.id),
    'board_forming', internal.board_forming(club_row.id),
    -- Everyone holding Medlemmar och lag over the club, also those who
    -- would not count (no account, or a right with an end date).
    'admins', coalesce((select jsonb_agg(jsonb_build_object(
        'name', admin.display_name, 'has_account', admin.has_account,
        'ends_at', admin.ends_at) order by admin.display_name)
      from (select person.display_name,
          bool_or(link.id is not null) has_account,
          max(coalesce(grant_row.ends_at, assignment.ends_at)) ends_at
        from core.capability_grants grant_row
        join core.assignments assignment on assignment.id = grant_row.assignment_id
          and assignment.club_id = grant_row.club_id and assignment.state = 'active'
        join core.club_people person on person.id = assignment.club_person_id
        left join core.person_account_links link on link.club_person_id = person.id
          and link.club_id = person.club_id and link.state = 'active'
        where grant_row.club_id = club_row.id and grant_row.capability = 'club.memberships.manage'
          and grant_row.scope_type = 'club' and grant_row.scope_id = club_row.id
          and (grant_row.ends_at is null or grant_row.ends_at > now())
        group by person.id, person.display_name) admin), '[]'::jsonb),
    'board', coalesce((select jsonb_agg(jsonb_build_object(
        'name', person.display_name, 'office', mandate.office,
        'starts_at', mandate.starts_at, 'ends_at', mandate.ends_at,
        'has_account', exists (select 1 from core.person_account_links link
          where link.club_person_id = person.id and link.club_id = person.club_id
            and link.state = 'active'))
        order by mandate.office, person.display_name)
      from core.board_mandates mandate
      join core.assignments assignment on assignment.id = mandate.assignment_id
        and assignment.club_id = mandate.club_id
      join core.club_people person on person.id = assignment.club_person_id
      where mandate.club_id = club_row.id and mandate.state = 'active'
        and mandate.ends_at > now()), '[]'::jsonb),
    'pending_board_changes', coalesce((select jsonb_agg(jsonb_build_object(
        'action', change.action, 'office', change.office, 'name', person.display_name,
        'created_at', change.created_at,
        'approvals', (select count(*) from core.board_mandate_change_approvals approval
          where approval.change_id = change.id and approval.decision = 'approved'))
        order by change.created_at)
      from core.board_mandate_changes change
      left join core.assignments assignment on assignment.id = change.target_assignment_id
      left join core.club_people person on person.id = assignment.club_person_id
      where change.club_id = club_row.id and change.state = 'pending'), '[]'::jsonb),
    'teams', coalesce((select jsonb_agg(jsonb_build_object(
        'name', team.name, 'status', team.status,
        'people', (select count(distinct assignment.club_person_id)
          from core.assignments assignment
          where assignment.team_id = team.id and assignment.state = 'active'))
        order by team.name)
      from core.teams team where team.club_id = club_row.id), '[]'::jsonb)
  );

  insert into audit.command_events(club_id, actor_profile_id, command_type,
    aggregate_type, aggregate_id, metadata)
  values (club_row.id, auth.uid(), 'support.club_viewed', 'club', club_row.id,
    jsonb_build_object('source', 'support_admin'));
  return result;
end
$$;

create or replace function api.list_clubs_for_support()
returns table(
  club_id uuid, club_name text, club_status text, verification_status text,
  created_at timestamptz, team_count integer, people_count integer,
  account_count integer, admin_count integer, board_mandate_count integer,
  board_forming boolean, pending_board_changes integer,
  oldest_pending_board_change timestamptz
)
language sql stable security invoker set search_path = ''
as $$select * from internal.list_clubs_for_support_for_actor()$$;

create or replace function api.get_club_for_support(target_club_id uuid)
returns jsonb language sql volatile security invoker set search_path = ''
as $$select internal.get_club_for_support_for_actor(target_club_id)$$;

revoke all on function
  internal.list_clubs_for_support_for_actor(),
  internal.get_club_for_support_for_actor(uuid),
  api.list_clubs_for_support(),
  api.get_club_for_support(uuid)
from public, anon, authenticated;

grant execute on function
  internal.list_clubs_for_support_for_actor(),
  internal.get_club_for_support_for_actor(uuid),
  api.list_clubs_for_support(),
  api.get_club_for_support(uuid)
to authenticated;

notify pgrst, 'reload schema';
