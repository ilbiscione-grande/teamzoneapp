-- Webtools Turneringsplanerare: a published tournament is searchable from
-- the start (the organiser may turn it off), and has a public page anyone
-- opens without an account: the tournament, its classes and teams, and the
-- published schedules with results and tables. Webtools' server reads it
-- with the secret key; the database stays closed to anonymous callers.

alter table core.tournaments alter column searchable set default true;
update core.tournaments set searchable = true where not searchable;

-- A class's groups, tables and matches, as the schedule shows them.
create or replace function internal.tournament_class_schedule_json(class core.tournament_classes)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', class.id, 'name', class.name, 'format', class.format, 'match_minutes', class.match_minutes,
    'points_win', class.points_win, 'points_draw', class.points_draw,
    'schedule_published', class.schedule_published,
    'teams', coalesce((select jsonb_agg(jsonb_build_object('registration_id', r.id, 'team_name', r.team_name, 'club_name', r.club_name)
      order by r.created_at) from core.tournament_registrations r
      where r.class_id = class.id and r.status = 'approved'), '[]'::jsonb),
    'groups', coalesce((select jsonb_agg(jsonb_build_object(
        'id', grp.id, 'name', grp.name, 'sort_order', grp.sort_order,
        'team_ids', coalesce((select jsonb_agg(member.registration_id order by member.seed)
          from core.tournament_group_teams member where member.group_id = grp.id), '[]'::jsonb),
        'complete', internal.tournament_group_complete(grp.id),
        'standings', case when class.format = 'groups_playoff' then internal.tournament_group_standings(grp.id) end
      ) order by grp.sort_order, grp.name) from core.tournament_groups grp where grp.class_id = class.id), '[]'::jsonb),
    'matches', coalesce((select jsonb_agg(internal.tournament_match_json(game)
      order by game.starts_at nulls last, game.stage, game.round, game.sort_order)
      from core.tournament_matches game where game.class_id = class.id), '[]'::jsonb)
  )
$$;

-- As in 20261120090000, through the shared class shape.
create or replace function internal.get_tournament_schedule_for_actor(target_tournament_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  tournament core.tournaments;
  staff boolean := internal.tournament_actor_role(target_tournament_id) is not null;
begin
  select * into tournament from core.tournaments where id = target_tournament_id;
  if tournament.id is null or auth.uid() is null or (not staff and tournament.status = 'draft') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object(
    'pitches', coalesce((select jsonb_agg(jsonb_build_object('id', pitch.id, 'name', pitch.name, 'sort_order', pitch.sort_order)
      order by pitch.sort_order, pitch.name) from core.tournament_pitches pitch where pitch.tournament_id = tournament.id), '[]'::jsonb),
    'classes', coalesce((select jsonb_agg(internal.tournament_class_schedule_json(class) order by class.sort_order, class.name)
      from core.tournament_classes class
      where class.tournament_id = tournament.id and (staff or class.schedule_published)), '[]'::jsonb)
  );
end;
$$;

-- The public page: a published or finished tournament by its id, or null.
-- No contact details of the teams; the organiser's e-mail only if given.
create or replace function internal.get_public_tournament(target_tournament_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', tournament.id, 'name', tournament.name, 'sport', tournament.sport, 'location', tournament.location,
    'starts_on', tournament.starts_on, 'ends_on', tournament.ends_on, 'description', tournament.description,
    'contact_email', tournament.contact_email, 'status', tournament.status,
    'organizer_name', internal.booking_person_name(tournament.created_by),
    'registration_is_open', internal.tournament_registration_is_open(tournament),
    'registration_closes_at', tournament.registration_closes_at,
    'classes', coalesce((select jsonb_agg(internal.tournament_class_json(class)
        || jsonb_build_object('teams', coalesce((select jsonb_agg(jsonb_build_object('team_name', r.team_name, 'club_name', r.club_name)
          order by r.created_at) from core.tournament_registrations r
          where r.class_id = class.id and r.status = 'approved'), '[]'::jsonb))
      order by class.sort_order, class.name)
      from core.tournament_classes class where class.tournament_id = tournament.id), '[]'::jsonb),
    'pitches', coalesce((select jsonb_agg(jsonb_build_object('id', pitch.id, 'name', pitch.name, 'sort_order', pitch.sort_order)
      order by pitch.sort_order, pitch.name) from core.tournament_pitches pitch where pitch.tournament_id = tournament.id), '[]'::jsonb),
    'schedule', coalesce((select jsonb_agg(internal.tournament_class_schedule_json(class) order by class.sort_order, class.name)
      from core.tournament_classes class where class.tournament_id = tournament.id and class.schedule_published), '[]'::jsonb)
  )
  from core.tournaments tournament
  where tournament.id = target_tournament_id and tournament.status in ('published', 'finished')
$$;

create or replace function api.get_public_tournament(target_tournament_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.get_public_tournament(target_tournament_id) $$;

revoke all on function internal.tournament_class_schedule_json(core.tournament_classes) from public, anon, authenticated;
grant execute on function internal.tournament_class_schedule_json(core.tournament_classes) to authenticated;
-- The public page is read by Webtools' server only.
revoke all on function internal.get_public_tournament(uuid), api.get_public_tournament(uuid) from public, anon, authenticated;
grant execute on function internal.get_public_tournament(uuid), api.get_public_tournament(uuid) to service_role;
notify pgrst, 'reload schema';
