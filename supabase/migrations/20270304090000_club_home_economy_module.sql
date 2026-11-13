-- Home shows the economy card only where the club has the economy module;
-- a board mandate gives economy rights in any club, but the page says the
-- module is not active. The function is its live version with this change.

CREATE OR REPLACE FUNCTION internal.get_club_home_for_actor(target_context_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_context record;
  own_person_ids uuid[];
  own_name text;
  can_board boolean;
  can_economy boolean;
  can_members boolean;
  can_publication boolean;
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
  -- The economy only where the club has the module, as on the page.
  can_economy := internal.actor_has_capability(actor_context.club_id, null, 'economy.read')
    and internal.entitlement_allows_write(actor_context.club_id, 'module.economy');
  can_members := internal.actor_has_capability(actor_context.club_id, null, 'club.memberships.manage');
  can_publication := internal.actor_has_capability(actor_context.club_id, null, 'publication.manage');

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
    'publication', case when can_publication then jsonb_build_object(
      'pending_team_pages', (select count(*) from core.team_publication_requests request
        where request.club_id = actor_context.club_id and request.status = 'pending')
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
$function$;

notify pgrst, 'reload schema';
