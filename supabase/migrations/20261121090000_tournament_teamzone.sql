-- Webtools Turneringsplanerare, part 3: TeamZone. An organiser may make a
-- published tournament searchable; a TeamZone leader finds it and registers
-- one of their teams, in the app or in Webtools. Once the class's schedule
-- is published the leader puts the tournament in the team's calendar: an
-- activity per day with the team's matches, from the first match to the
-- last, kept in step when synced again. The activity shows the matches.

alter table core.tournaments add column searchable boolean not null default false;

-- A team's tournament day in its calendar.
create table core.tournament_team_events (
  registration_id uuid not null references core.tournament_registrations(id) on delete cascade,
  day date not null,
  event_id uuid not null unique references core.events(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (registration_id, day)
);
alter table core.tournament_team_events enable row level security;
revoke all on core.tournament_team_events from public, anon, authenticated;

-- Teams whose activities you manage: those you lead.
create or replace function internal.tournament_actor_teams()
returns table(team_id uuid, team_name text, club_id uuid, club_name text)
language sql stable security definer set search_path = '' as $$
  select distinct team.id, team.name, club.id, club.name
  from core.person_account_links link
  join core.assignments assignment on assignment.club_id = link.club_id
    and assignment.club_person_id = link.club_person_id and assignment.state = 'active'
    and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
    and assignment.role_package = 'leader'
  join core.teams team on team.id = assignment.team_id and team.club_id = link.club_id and team.status = 'active'
  join core.clubs club on club.id = team.club_id
  where link.profile_id = auth.uid() and link.state = 'active'
    and internal.actor_has_capability(team.club_id, team.id, 'event.manage')
$$;

create or replace function internal.list_tournament_leader_teams_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('team_id', t.team_id, 'team_name', t.team_name,
    'club_id', t.club_id, 'club_name', t.club_name) order by t.club_name, t.team_name), '[]'::jsonb)
  from internal.tournament_actor_teams() t
$$;

-- Published, searchable tournaments that have not ended, by name, place or
-- sport; with their classes and places left.
create or replace function internal.search_tournaments_for_actor(search_text text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare pattern text := '%' || replace(replace(replace(coalesce(btrim(search_text), ''), '\', '\\'), '%', '\%'), '_', '\_') || '%';
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  return coalesce((select jsonb_agg(item order by (item->>'starts_on'), item->>'name') from (
    select jsonb_build_object(
      'id', tournament.id, 'name', tournament.name, 'sport', tournament.sport, 'location', tournament.location,
      'starts_on', tournament.starts_on, 'ends_on', tournament.ends_on, 'description', tournament.description,
      'payment_info', tournament.payment_info, 'contact_email', tournament.contact_email,
      'organizer_name', internal.booking_person_name(tournament.created_by),
      'registration_is_open', internal.tournament_registration_is_open(tournament),
      'registration_closes_at', tournament.registration_closes_at,
      'classes', coalesce((select jsonb_agg(internal.tournament_class_json(class) order by class.sort_order, class.name)
        from core.tournament_classes class where class.tournament_id = tournament.id), '[]'::jsonb)
    ) item
    from core.tournaments tournament
    where tournament.status = 'published' and tournament.searchable and tournament.ends_on >= current_date
      and (tournament.name ilike pattern or coalesce(tournament.location, '') ilike pattern or coalesce(tournament.sport, '') ilike pattern)
    order by tournament.starts_on, tournament.name
    limit 30
  ) found), '[]'::jsonb);
end;
$$;

-- As register_tournament_team, for one of your teams in TeamZone when a
-- team is given: the registration remembers it, once per class.
create or replace function internal.register_tournament_team_v2_for_actor(
  target_class_id uuid, target_team_id uuid, registration_team_name text, registration_club_name text,
  registration_contact_name text, registration_contact_email text, registration_contact_phone text, registration_notes text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare created jsonb;
begin
  if target_team_id is not null then
    if not exists (select 1 from internal.tournament_actor_teams() t where t.team_id = target_team_id) then
      raise insufficient_privilege using message = 'not_team_leader';
    end if;
    if exists (select 1 from core.tournament_registrations where class_id = target_class_id
      and teamzone_team_id = target_team_id and status in ('pending', 'approved')) then
      raise invalid_parameter_value using message = 'team_already_registered';
    end if;
  end if;
  created := internal.register_tournament_team_for_actor(target_class_id, registration_team_name, registration_club_name,
    registration_contact_name, registration_contact_email, registration_contact_phone, registration_notes);
  if target_team_id is not null then
    update core.tournament_registrations set teamzone_team_id = target_team_id where id = (created->>'id')::uuid;
    created := created || jsonb_build_object('teamzone_team_id', target_team_id);
  end if;
  return created;
end;
$$;

-- Registrations of the teams you lead, wherever they were made.
create or replace function internal.list_my_team_tournaments_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'registration_id', registration.id, 'tournament_id', tournament.id, 'tournament_name', tournament.name,
    'starts_on', tournament.starts_on, 'ends_on', tournament.ends_on, 'location', tournament.location,
    'class_name', class.name, 'team_name', registration.team_name, 'team_id', registration.teamzone_team_id,
    'teamzone_team_name', t.team_name, 'status', registration.status, 'paid', registration.paid,
    'fee_sek', class.fee_sek, 'payment_info', tournament.payment_info,
    'schedule_published', class.schedule_published and tournament.status <> 'draft',
    'calendar_days', (select count(*) from core.tournament_team_events link where link.registration_id = registration.id)
  ) order by tournament.starts_on desc, tournament.name, class.name), '[]'::jsonb)
  from core.tournament_registrations registration
  join internal.tournament_actor_teams() t on t.team_id = registration.teamzone_team_id
  join core.tournaments tournament on tournament.id = registration.tournament_id
  join core.tournament_classes class on class.id = registration.class_id
  where registration.status in ('pending', 'approved') and tournament.status <> 'cancelled'
$$;

-- Puts the team's tournament days in its calendar, or moves them to the
-- matches' new times. A day is one activity from the first match to the
-- last; days already there keep their activity, a cancelled one stays.
create or replace function internal.sync_tournament_team_calendar_for_actor(target_registration_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  registration core.tournament_registrations;
  tournament core.tournaments;
  class core.tournament_classes;
  team core.teams;
  zone text := 'Europe/Stockholm';
  day_row record;
  linked core.tournament_team_events;
  existing core.events;
  new_event uuid;
  total_days integer;
  day_number integer := 0;
  created integer := 0;
  moved integer := 0;
begin
  select * into registration from core.tournament_registrations where id = target_registration_id;
  if registration.id is null or registration.teamzone_team_id is null
    or not exists (select 1 from internal.tournament_actor_teams() t where t.team_id = registration.teamzone_team_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select * into tournament from core.tournaments where id = registration.tournament_id;
  select * into class from core.tournament_classes where id = registration.class_id;
  select * into team from core.teams where id = registration.teamzone_team_id;
  if registration.status <> 'approved' then raise invalid_parameter_value using message = 'not_approved'; end if;
  if not class.schedule_published or tournament.status = 'draft' then
    raise invalid_parameter_value using message = 'schedule_not_published';
  end if;
  select count(distinct (game.starts_at at time zone zone)::date) into total_days
  from core.tournament_matches game
  where game.class_id = class.id and game.starts_at is not null
    and registration.id in (game.home_registration_id, game.away_registration_id);
  if total_days = 0 then raise invalid_parameter_value using message = 'no_matches'; end if;
  for day_row in
    select (game.starts_at at time zone zone)::date local_day, min(game.starts_at) first_start,
      max(coalesce(game.ends_at, game.starts_at + interval '30 minutes')) last_end
    from core.tournament_matches game
    where game.class_id = class.id and game.starts_at is not null
      and registration.id in (game.home_registration_id, game.away_registration_id)
    group by 1 order by 1
  loop
    day_number := day_number + 1;
    select * into linked from core.tournament_team_events where registration_id = registration.id and day = day_row.local_day;
    if linked.event_id is not null then
      select * into existing from core.events where id = linked.event_id;
      if existing.state = 'scheduled' and (existing.starts_at <> day_row.first_start or existing.ends_at <> day_row.last_end) then
        perform internal.revise_event_v3_for_actor(existing.id, 'one',
          jsonb_build_object('starts_at', day_row.first_start, 'ends_at', day_row.last_end), existing.revision, gen_random_uuid());
        moved := moved + 1;
      end if;
    else
      new_event := internal.create_event_v2_for_actor(team.club_id, team.id,
        left(tournament.name || case when total_days > 1 then ' · dag ' || day_number else '' end, 160),
        'Turnering i TeamZone Webtools, klass ' || class.name || '. Matcherna står på aktiviteten.',
        'activity', 'scheduled', day_row.first_start, day_row.last_end, false, zone,
        array['players', 'leaders', 'guardians'], tournament.location, null, null, null, '{}'::jsonb, gen_random_uuid());
      insert into core.tournament_team_events (registration_id, day, event_id) values (registration.id, day_row.local_day, new_event);
      created := created + 1;
    end if;
  end loop;
  return jsonb_build_object('created', created, 'moved', moved, 'days', total_days);
end;
$$;

-- The activity's tournament: the team's matches that day, and its group.
create or replace function internal.get_event_tournament_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  linked core.tournament_team_events;
  registration core.tournament_registrations;
  class core.tournament_classes;
  tournament core.tournaments;
begin
  if not internal.actor_can_read_event(target_event_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select * into linked from core.tournament_team_events where event_id = target_event_id;
  if linked.event_id is null then return null; end if;
  select * into registration from core.tournament_registrations where id = linked.registration_id;
  select * into class from core.tournament_classes where id = registration.class_id;
  select * into tournament from core.tournaments where id = registration.tournament_id;
  if not class.schedule_published or tournament.status = 'draft' then return null; end if;
  return jsonb_build_object(
    'tournament_id', tournament.id, 'tournament_name', tournament.name, 'class_name', class.name,
    'format', class.format, 'team_name', registration.team_name, 'registration_id', registration.id,
    'matches', coalesce((select jsonb_agg(internal.tournament_match_json(game)
        || jsonb_build_object('pitch_name', (select pitch.name from core.tournament_pitches pitch where pitch.id = game.pitch_id),
          'group_name', (select grp.name from core.tournament_groups grp where grp.id = game.group_id))
        order by game.starts_at)
      from core.tournament_matches game
      where game.class_id = class.id and registration.id in (game.home_registration_id, game.away_registration_id)
        and (game.starts_at at time zone 'Europe/Stockholm')::date = linked.day), '[]'::jsonb),
    'groups', case when class.format = 'groups_playoff' then coalesce((select jsonb_agg(jsonb_build_object(
        'name', grp.name, 'standings', internal.tournament_group_standings(grp.id)))
      from core.tournament_groups grp join core.tournament_group_teams member on member.group_id = grp.id
      where member.registration_id = registration.id), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;

-- As in 20261119090000, with whether the tournament is searchable.
create or replace function internal.update_tournament_v2_for_actor(
  target_tournament_id uuid, tournament_name text, tournament_sport text, tournament_location text,
  tournament_starts_on date, tournament_ends_on date, tournament_description text, tournament_contact_email text,
  tournament_payment_info text, tournament_status text, tournament_registration_open boolean,
  tournament_registration_closes_at timestamptz, tournament_searchable boolean
) returns void language plpgsql security definer set search_path = '' as $$
begin
  perform internal.update_tournament_for_actor(target_tournament_id, tournament_name, tournament_sport, tournament_location,
    tournament_starts_on, tournament_ends_on, tournament_description, tournament_contact_email, tournament_payment_info,
    tournament_status, tournament_registration_open, tournament_registration_closes_at);
  update core.tournaments set searchable = coalesce(tournament_searchable, false) where id = target_tournament_id;
end;
$$;

-- As in 20261119090000, with searchable.
create or replace function internal.get_tournament_for_actor(target_tournament_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  tournament core.tournaments;
  actor_role text := internal.tournament_actor_role(target_tournament_id);
begin
  select * into tournament from core.tournaments where id = target_tournament_id;
  if tournament.id is null or (actor_role is null and tournament.status = 'draft') or auth.uid() is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object(
    'id', tournament.id, 'name', tournament.name, 'sport', tournament.sport, 'location', tournament.location,
    'starts_on', tournament.starts_on, 'ends_on', tournament.ends_on, 'description', tournament.description,
    'contact_email', tournament.contact_email, 'payment_info', tournament.payment_info,
    'status', tournament.status, 'registration_open', tournament.registration_open,
    'registration_closes_at', tournament.registration_closes_at,
    'registration_is_open', internal.tournament_registration_is_open(tournament),
    'searchable', tournament.searchable,
    'role', actor_role,
    'organizer_name', internal.booking_person_name(tournament.created_by),
    'classes', coalesce((select jsonb_agg(internal.tournament_class_json(class) order by class.sort_order, class.name)
      from core.tournament_classes class where class.tournament_id = tournament.id), '[]'::jsonb),
    'my_registrations', coalesce((select jsonb_agg(internal.tournament_registration_json(registration, false)
        || jsonb_build_object('calendar_days', (select count(*) from core.tournament_team_events link where link.registration_id = registration.id),
          'can_sync', registration.teamzone_team_id is not null and exists (select 1 from internal.tournament_actor_teams() t where t.team_id = registration.teamzone_team_id))
        order by registration.created_at)
      from core.tournament_registrations registration
      where registration.tournament_id = tournament.id and registration.registered_by = auth.uid()), '[]'::jsonb),
    'staff', case when actor_role = 'organizer' then coalesce((select jsonb_agg(jsonb_build_object(
        'profile_id', staff.profile_id, 'name', internal.booking_person_name(staff.profile_id),
        'role', staff.role, 'is_self', staff.profile_id = auth.uid()) order by staff.role desc, staff.created_at)
      from core.tournament_staff staff where staff.tournament_id = tournament.id), '[]'::jsonb) end
  );
end;
$$;

create or replace function api.list_tournament_leader_teams() returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_tournament_leader_teams_for_actor() $$;
create or replace function api.search_tournaments(search_text text) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.search_tournaments_for_actor(search_text) $$;
create or replace function api.register_tournament_team_v2(
  target_class_id uuid, target_team_id uuid, registration_team_name text, registration_club_name text,
  registration_contact_name text, registration_contact_email text, registration_contact_phone text, registration_notes text
) returns jsonb language sql security invoker set search_path = '' as
$$ select internal.register_tournament_team_v2_for_actor(target_class_id, target_team_id, registration_team_name, registration_club_name,
  registration_contact_name, registration_contact_email, registration_contact_phone, registration_notes) $$;
create or replace function api.list_my_team_tournaments() returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_my_team_tournaments_for_actor() $$;
create or replace function api.sync_tournament_team_calendar(target_registration_id uuid) returns jsonb language sql security invoker set search_path = '' as
$$ select internal.sync_tournament_team_calendar_for_actor(target_registration_id) $$;
create or replace function api.get_event_tournament(target_event_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.get_event_tournament_for_actor(target_event_id) $$;
create or replace function api.update_tournament_v2(
  target_tournament_id uuid, tournament_name text, tournament_sport text, tournament_location text,
  tournament_starts_on date, tournament_ends_on date, tournament_description text, tournament_contact_email text,
  tournament_payment_info text, tournament_status text, tournament_registration_open boolean,
  tournament_registration_closes_at timestamptz, tournament_searchable boolean
) returns void language sql security invoker set search_path = '' as
$$ select internal.update_tournament_v2_for_actor(target_tournament_id, tournament_name, tournament_sport, tournament_location,
  tournament_starts_on, tournament_ends_on, tournament_description, tournament_contact_email, tournament_payment_info,
  tournament_status, tournament_registration_open, tournament_registration_closes_at, tournament_searchable) $$;

revoke all on function
  internal.tournament_actor_teams(), internal.list_tournament_leader_teams_for_actor(),
  internal.search_tournaments_for_actor(text),
  internal.register_tournament_team_v2_for_actor(uuid, uuid, text, text, text, text, text, text),
  internal.list_my_team_tournaments_for_actor(), internal.sync_tournament_team_calendar_for_actor(uuid),
  internal.get_event_tournament_for_actor(uuid),
  internal.update_tournament_v2_for_actor(uuid, text, text, text, date, date, text, text, text, text, boolean, timestamptz, boolean),
  api.list_tournament_leader_teams(), api.search_tournaments(text),
  api.register_tournament_team_v2(uuid, uuid, text, text, text, text, text, text),
  api.list_my_team_tournaments(), api.sync_tournament_team_calendar(uuid), api.get_event_tournament(uuid),
  api.update_tournament_v2(uuid, text, text, text, date, date, text, text, text, text, boolean, timestamptz, boolean)
from public, anon, authenticated;
grant execute on function
  internal.tournament_actor_teams(), internal.list_tournament_leader_teams_for_actor(),
  internal.search_tournaments_for_actor(text),
  internal.register_tournament_team_v2_for_actor(uuid, uuid, text, text, text, text, text, text),
  internal.list_my_team_tournaments_for_actor(), internal.sync_tournament_team_calendar_for_actor(uuid),
  internal.get_event_tournament_for_actor(uuid),
  internal.update_tournament_v2_for_actor(uuid, text, text, text, date, date, text, text, text, text, boolean, timestamptz, boolean),
  api.list_tournament_leader_teams(), api.search_tournaments(text),
  api.register_tournament_team_v2(uuid, uuid, text, text, text, text, text, text),
  api.list_my_team_tournaments(), api.sync_tournament_team_calendar(uuid), api.get_event_tournament(uuid),
  api.update_tournament_v2(uuid, text, text, text, date, date, text, text, text, text, boolean, timestamptz, boolean)
to authenticated;
