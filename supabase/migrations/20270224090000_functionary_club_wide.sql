-- Klubbfunktionär is a club-wide role (2026-11-11). Approving a team
-- application as Klubbfunktionär (or Medlem i klubben) placed the role in
-- the team: the person got the team's calendar but was not in its squad, and
-- no club page could change it. The club admin's approval now places such a
-- role in the club, without a team; a team placement takes team roles only.

create or replace function internal.decide_membership_application_v3(application_id uuid, decision text,
  approved_role text, target_team_id uuid, to_club boolean, idempotency_key uuid)
returns text language plpgsql security definer set search_path = '' as $function$
declare actor_id uuid := auth.uid(); row_value core.membership_applications%rowtype; result text;
  moving boolean; new_team uuid; selected_role text; existing_result jsonb; club_wide boolean;
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select dedupe.result into existing_result from internal.command_deduplication dedupe
  where dedupe.actor_profile_id = actor_id and dedupe.command_type = 'membership.application.decide.v3'
    and dedupe.idempotency_key = decide_membership_application_v3.idempotency_key;
  if existing_result is not null then return existing_result->>'status'; end if;
  select * into row_value from core.membership_applications application
  where application.id = decide_membership_application_v3.application_id for update;
  if row_value.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  club_wide := decision = 'approved'
    and coalesce(approved_role, row_value.requested_role) in ('club_functionary', 'member');
  if club_wide and target_team_id is not null then
    raise invalid_parameter_value using message = 'invalid_role';
  end if;
  new_team := case when coalesce(to_club, false) or club_wide then null
    else coalesce(target_team_id, row_value.team_id) end;
  moving := decision = 'approved' and new_team is distinct from row_value.team_id;
  if coalesce(to_club, false) and target_team_id is not null then
    raise invalid_parameter_value using message = 'invalid_placement';
  end if;
  if moving then
    if row_value.status <> 'pending'
       or not internal.actor_has_capability(row_value.club_id, null, 'club.memberships.manage') then
      raise insufficient_privilege using message = 'not_found';
    end if;
    if new_team is not null and not exists (select 1 from core.teams team
        where team.id = new_team and team.club_id = row_value.club_id and team.status = 'active') then
      raise insufficient_privilege using message = 'not_found';
    end if;
    selected_role := coalesce(approved_role, row_value.requested_role);
    if (new_team is null and selected_role not in ('member', 'club_functionary'))
       or (new_team is not null and selected_role not in ('player', 'leader', 'guardian')) then
      raise invalid_parameter_value using message = 'invalid_role';
    end if;
    -- The first decision step places from team_id and requested_role:
    -- change them under the row lock, then restore what was asked for.
    update core.membership_applications set team_id = new_team, requested_role = selected_role
    where id = row_value.id;
  end if;
  result := internal.decide_membership_application_v2(row_value.id, decision,
    case when moving then null else approved_role end, idempotency_key);
  if moving then
    update core.membership_applications
    set team_id = row_value.team_id, requested_role = row_value.requested_role,
      approved_role = selected_role, approved_team_id = new_team, approved_to_club = new_team is null
    where id = row_value.id;
    insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id,
      aggregate_revision, metadata)
    values (row_value.club_id, actor_id, 'membership.application.placed.v1', 'membership_application', row_value.id,
      row_value.revision + 1, jsonb_build_object('requested_team_id', row_value.team_id,
        'requested_role', row_value.requested_role, 'approved_team_id', new_team, 'approved_role', selected_role));
  end if;
  insert into internal.command_deduplication (actor_profile_id, idempotency_key, command_type, result)
  values (actor_id, idempotency_key, 'membership.application.decide.v3', jsonb_build_object('status', result));
  return result;
end
$function$;

notify pgrst, 'reload schema';
