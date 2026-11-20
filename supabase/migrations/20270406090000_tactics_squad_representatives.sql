-- Tacticsboard's squad also brings the players who may represent the team now
-- (an active representation, for example juniors who can play for the A team),
-- each with the home team they come from. The team's own players come first;
-- someone in both is listed once, as the team's own.
create or replace function internal.list_tactics_team_players_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if target_team_id is null then raise invalid_parameter_value using message = 'not_found'; end if;
  perform internal.tactics_require_team(target_team_id);
  return coalesce((select jsonb_agg(player order by (player->>'home_team') is not null,
      (player->>'number')::integer nulls last, player->>'name') from (
    (select distinct on (person.id) jsonb_build_object(
      'person_id', person.id, 'name', person.display_name, 'number', details.jersey_number,
      'position', coalesce(nullif(btrim(details.main_position), ''), details.positions[1])
    ) player
    from core.assignments assignment
    join core.club_people person on person.id = assignment.club_person_id
    left join core.team_person_details details on details.team_id = assignment.team_id
      and details.club_person_id = person.id
    where assignment.team_id = target_team_id and assignment.role_package = 'player' and assignment.state = 'active'
      and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
    order by person.id)
    union all
    (select distinct on (person.id) jsonb_build_object(
      'person_id', person.id, 'name', person.display_name,
      'number', coalesce(here.jersey_number, home_details.jersey_number),
      'position', coalesce(nullif(btrim(here.main_position), ''), here.positions[1],
        nullif(btrim(home_details.main_position), ''), home_details.positions[1]),
      'home_team', coalesce(home_team.name, '')
    )
    from core.play_eligibilities eligibility
    join core.club_people person on person.id = eligibility.club_person_id
    left join core.team_assignments home on home.club_person_id = person.id and home.club_id = eligibility.club_id
      and home.state = 'active' and home.starts_at <= now() and (home.ends_at is null or home.ends_at > now())
    left join core.teams home_team on home_team.id = home.team_id
    left join core.team_person_details here on here.team_id = target_team_id and here.club_person_id = person.id
    left join core.team_person_details home_details on home_details.team_id = home.team_id
      and home_details.club_person_id = person.id
    where eligibility.team_id = target_team_id and eligibility.state = 'active'
      and eligibility.starts_at <= now() and coalesce(eligibility.ends_at, eligibility.review_due_at) > now()
      and not exists (select 1 from core.assignments own where own.team_id = target_team_id
        and own.club_person_id = person.id and own.role_package = 'player' and own.state = 'active'
        and own.starts_at <= now() and (own.ends_at is null or own.ends_at > now()))
    order by person.id, home.starts_at desc nulls last)
  ) players), '[]'::jsonb);
end;
$$;
