-- Webtools Turneringsplanerare, part 2: pitches, groups, the schedule,
-- results, tables and play-offs. Webtools plans the groups and times and
-- saves a class's schedule at once; play-off matches name where their teams
-- come from (a group place, or the winner or loser of a match) and are
-- filled in as results come. Pools (the youngest) have no results.

create table core.tournament_pitches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references core.tournaments(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 60),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (id, tournament_id),
  unique (tournament_id, name)
);

alter table core.tournament_classes
  add column points_win integer not null default 3 check (points_win between 0 and 10),
  add column points_draw integer not null default 1 check (points_draw between 0 and 10),
  -- Teams and the public see a class's schedule once it is published.
  add column schedule_published boolean not null default false;

create table core.tournament_groups (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null,
  class_id uuid not null,
  name text not null check (length(btrim(name)) between 1 and 30),
  sort_order integer not null default 0,
  foreign key (class_id, tournament_id) references core.tournament_classes(id, tournament_id) on delete cascade,
  unique (id, class_id)
);

create table core.tournament_group_teams (
  group_id uuid not null references core.tournament_groups(id) on delete cascade,
  registration_id uuid not null unique references core.tournament_registrations(id) on delete cascade,
  seed integer not null default 0,
  primary key (group_id, registration_id)
);

create table core.tournament_matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null,
  class_id uuid not null,
  group_id uuid,
  stage text not null check (stage in ('group', 'playoff')),
  round integer not null default 1 check (round between 1 and 100),
  -- Play-off: "A-final", "Semifinal 1"...
  label text check (label is null or length(btrim(label)) between 1 and 60),
  home_registration_id uuid references core.tournament_registrations(id),
  away_registration_id uuid references core.tournament_registrations(id),
  -- Where a play-off team comes from: {"kind":"group_place","group_id":..,"place":1}
  -- or {"kind":"winner"|"loser","match_id":..}.
  home_source jsonb,
  away_source jsonb,
  pitch_id uuid,
  starts_at timestamptz,
  ends_at timestamptz,
  status text not null default 'scheduled' check (status in ('scheduled', 'played')),
  home_score integer check (home_score is null or home_score between 0 and 999),
  away_score integer check (away_score is null or away_score between 0 and 999),
  home_penalties integer check (home_penalties is null or home_penalties between 0 and 99),
  away_penalties integer check (away_penalties is null or away_penalties between 0 and 99),
  reported_by uuid references core.profiles(id),
  reported_at timestamptz,
  sort_order integer not null default 0,
  revision bigint not null default 1 check (revision > 0),
  foreign key (class_id, tournament_id) references core.tournament_classes(id, tournament_id) on delete cascade,
  foreign key (group_id, class_id) references core.tournament_groups(id, class_id) on delete cascade,
  foreign key (pitch_id, tournament_id) references core.tournament_pitches(id, tournament_id),
  check (ends_at is null or (starts_at is not null and ends_at > starts_at)),
  check ((stage = 'group') = (group_id is not null)),
  check (status = 'scheduled' or (home_score is not null and away_score is not null))
);
create index tournament_matches_class on core.tournament_matches (class_id, stage, round, sort_order);
create index tournament_matches_time on core.tournament_matches (tournament_id, starts_at);

alter table core.tournament_pitches enable row level security;
alter table core.tournament_groups enable row level security;
alter table core.tournament_group_teams enable row level security;
alter table core.tournament_matches enable row level security;
revoke all on core.tournament_pitches, core.tournament_groups, core.tournament_group_teams,
  core.tournament_matches from public, anon, authenticated;

-- A group's table from its played matches: points, goal difference, goals
-- scored, then the name.
create or replace function internal.tournament_group_standings(target_group_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with class as (
    select class.points_win, class.points_draw from core.tournament_groups grp
    join core.tournament_classes class on class.id = grp.class_id where grp.id = target_group_id
  ), tally as (
    select member.registration_id, registration.team_name,
      count(game.id) played,
      count(game.id) filter (where game.mine > game.theirs) won,
      count(game.id) filter (where game.mine = game.theirs) drawn,
      count(game.id) filter (where game.mine < game.theirs) lost,
      coalesce(sum(game.mine), 0) goals_for,
      coalesce(sum(game.theirs), 0) goals_against
    from core.tournament_group_teams member
    join core.tournament_registrations registration on registration.id = member.registration_id
    left join lateral (
      select m.id, case when m.home_registration_id = member.registration_id then m.home_score else m.away_score end mine,
        case when m.home_registration_id = member.registration_id then m.away_score else m.home_score end theirs
      from core.tournament_matches m
      where m.group_id = target_group_id and m.status = 'played'
        and member.registration_id in (m.home_registration_id, m.away_registration_id)
    ) game on true
    where member.group_id = target_group_id
    group by member.registration_id, registration.team_name
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'registration_id', tally.registration_id, 'team_name', tally.team_name, 'played', tally.played,
      'won', tally.won, 'drawn', tally.drawn, 'lost', tally.lost,
      'goals_for', tally.goals_for, 'goals_against', tally.goals_against,
      'points', tally.won * class.points_win + tally.drawn * class.points_draw
    ) order by tally.won * class.points_win + tally.drawn * class.points_draw desc,
      tally.goals_for - tally.goals_against desc, tally.goals_for desc, tally.team_name), '[]'::jsonb)
  from tally, class
$$;

-- Whether every match of the group is played.
create or replace function internal.tournament_group_complete(target_group_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from core.tournament_matches where group_id = target_group_id)
    and not exists (select 1 from core.tournament_matches where group_id = target_group_id and status <> 'played')
$$;

-- The team a source points to, once it is known.
create or replace function internal.tournament_source_team(source jsonb)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare game core.tournament_matches; home_won boolean;
begin
  if source is null then return null; end if;
  if source->>'kind' = 'group_place' then
    if not internal.tournament_group_complete((source->>'group_id')::uuid) then return null; end if;
    return (internal.tournament_group_standings((source->>'group_id')::uuid)
      -> ((source->>'place')::integer - 1) ->> 'registration_id')::uuid;
  end if;
  select * into game from core.tournament_matches where id = (source->>'match_id')::uuid;
  if game.id is null or game.status <> 'played' then return null; end if;
  home_won := game.home_score > game.away_score
    or (game.home_score = game.away_score and coalesce(game.home_penalties, 0) > coalesce(game.away_penalties, 0));
  return case when (source->>'kind' = 'winner') = home_won then game.home_registration_id else game.away_registration_id end;
end;
$$;

-- Fills in the play-off's teams that are known; round by round, so a
-- winner goes on in the same pass. Played matches keep their teams.
create or replace function internal.tournament_resolve_class(target_class_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare game core.tournament_matches;
begin
  for game in select * from core.tournament_matches
    where class_id = target_class_id and stage = 'playoff' and status = 'scheduled'
    order by round, sort_order
  loop
    update core.tournament_matches set
      home_registration_id = coalesce(internal.tournament_source_team(home_source), case when home_source is null then home_registration_id end),
      away_registration_id = coalesce(internal.tournament_source_team(away_source), case when away_source is null then away_registration_id end)
    where id = game.id;
  end loop;
end;
$$;

-- "1:a grupp A", "Vinnare Semifinal 1".
create or replace function internal.tournament_source_label(source jsonb)
returns text language sql stable security definer set search_path = '' as $$
  select case source->>'kind'
    when 'group_place' then (source->>'place') || ':a grupp ' ||
      coalesce((select grp.name from core.tournament_groups grp where grp.id = (source->>'group_id')::uuid), '?')
    when 'winner' then 'Vinnare ' || coalesce((select m.label from core.tournament_matches m where m.id = (source->>'match_id')::uuid), 'match')
    when 'loser' then 'Förlorare ' || coalesce((select m.label from core.tournament_matches m where m.id = (source->>'match_id')::uuid), 'match')
  end
$$;

create or replace function internal.tournament_match_json(game core.tournament_matches)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', game.id, 'class_id', game.class_id, 'group_id', game.group_id, 'stage', game.stage,
    'round', game.round, 'label', game.label, 'sort_order', game.sort_order,
    'home_registration_id', game.home_registration_id, 'away_registration_id', game.away_registration_id,
    'home_name', coalesce((select r.team_name from core.tournament_registrations r where r.id = game.home_registration_id),
      internal.tournament_source_label(game.home_source)),
    'away_name', coalesce((select r.team_name from core.tournament_registrations r where r.id = game.away_registration_id),
      internal.tournament_source_label(game.away_source)),
    'pitch_id', game.pitch_id, 'starts_at', game.starts_at, 'ends_at', game.ends_at,
    'status', game.status, 'home_score', game.home_score, 'away_score', game.away_score,
    'home_penalties', game.home_penalties, 'away_penalties', game.away_penalties
  )
$$;

-- The schedule: staff see every class; others a published tournament's
-- published classes.
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
    'classes', coalesce((select jsonb_agg(jsonb_build_object(
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
      ) order by class.sort_order, class.name)
      from core.tournament_classes class
      where class.tournament_id = tournament.id and (staff or class.schedule_published)), '[]'::jsonb)
  );
end;
$$;

create or replace function internal.save_tournament_pitch_for_actor(target_tournament_id uuid, target_pitch_id uuid, pitch_name text, pitch_sort_order integer)
returns uuid language plpgsql security definer set search_path = '' as $$
declare saved uuid;
begin
  perform internal.tournament_require_organizer(target_tournament_id);
  if exists (select 1 from core.tournament_pitches where tournament_id = target_tournament_id
    and lower(btrim(name)) = lower(btrim(pitch_name)) and id is distinct from target_pitch_id) then
    raise invalid_parameter_value using message = 'pitch_name_taken';
  end if;
  if target_pitch_id is null then
    insert into core.tournament_pitches (tournament_id, name, sort_order)
    values (target_tournament_id, btrim(pitch_name), coalesce(pitch_sort_order, 0)) returning id into saved;
  else
    update core.tournament_pitches set name = btrim(pitch_name), sort_order = coalesce(pitch_sort_order, 0)
    where id = target_pitch_id and tournament_id = target_tournament_id returning id into saved;
    if saved is null then raise invalid_parameter_value using message = 'not_found'; end if;
  end if;
  return saved;
end;
$$;

-- A pitch with matches stays.
create or replace function internal.delete_tournament_pitch_for_actor(target_pitch_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare pitch core.tournament_pitches;
begin
  select * into pitch from core.tournament_pitches where id = target_pitch_id;
  if pitch.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.tournament_require_organizer(pitch.tournament_id);
  if exists (select 1 from core.tournament_matches where pitch_id = pitch.id) then
    raise invalid_parameter_value using message = 'pitch_in_use';
  end if;
  delete from core.tournament_pitches where id = pitch.id;
end;
$$;

-- Saves a class's groups and group matches, replacing what was there, or
-- (stage 'playoff') its play-off, keeping the groups. Nothing that has a
-- result is replaced. Matches refer to each other and to groups by their
-- place in the arrays:
--   groups:  [{"name":"A","registration_ids":[..]}]
--   matches: [{"group":0,"round":1,"home":"<registration>","away":"<registration>",
--              "pitch_id":..,"starts_at":..,"ends_at":..}]
--   play-off sources: {"kind":"group_place","group":0,"place":1} or {"kind":"winner","match":2}
create or replace function internal.save_tournament_class_schedule_for_actor(
  target_class_id uuid, schedule_stage text, schedule_groups jsonb, schedule_matches jsonb
) returns integer language plpgsql security definer set search_path = '' as $$
declare
  class core.tournament_classes;
  group_ids uuid[] := '{}';
  match_ids uuid[] := '{}';
  item jsonb;
  team text;
  created uuid;
  idx integer := 0;
  approved uuid[];
  source_fix jsonb;
begin
  select * into class from core.tournament_classes where id = target_class_id;
  if class.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.tournament_require_organizer(class.tournament_id);
  if schedule_stage not in ('group', 'playoff') then raise invalid_parameter_value using message = 'invalid_schedule'; end if;
  if jsonb_typeof(coalesce(schedule_matches, 'null')) <> 'array' or jsonb_array_length(schedule_matches) > 500 then
    raise invalid_parameter_value using message = 'invalid_schedule';
  end if;
  if class.format = 'pool' and schedule_stage = 'playoff' then raise invalid_parameter_value using message = 'no_playoff_in_pool'; end if;
  if exists (select 1 from core.tournament_matches where class_id = class.id and status = 'played'
    and (schedule_stage = 'group' or stage = 'playoff')) then
    raise invalid_parameter_value using message = 'has_results';
  end if;
  select array_agg(id) into approved from core.tournament_registrations where class_id = class.id and status = 'approved';
  approved := coalesce(approved, '{}');

  if schedule_stage = 'group' then
    delete from core.tournament_matches where class_id = class.id;
    delete from core.tournament_groups where class_id = class.id;
    if jsonb_typeof(coalesce(schedule_groups, 'null')) <> 'array' or jsonb_array_length(schedule_groups) not between 1 and 64 then
      raise invalid_parameter_value using message = 'invalid_schedule';
    end if;
    for item in select value from jsonb_array_elements(schedule_groups) loop
      insert into core.tournament_groups (tournament_id, class_id, name, sort_order)
      values (class.tournament_id, class.id, btrim(item->>'name'), idx) returning id into created;
      group_ids := group_ids || created;
      idx := idx + 1;
      for team in select value from jsonb_array_elements_text(coalesce(item->'registration_ids', '[]')) loop
        if not team::uuid = any(approved) then raise invalid_parameter_value using message = 'team_not_approved'; end if;
        insert into core.tournament_group_teams (group_id, registration_id, seed)
        values (created, team::uuid, (select count(*) from core.tournament_group_teams where group_id = created));
      end loop;
    end loop;
  else
    delete from core.tournament_matches where class_id = class.id and stage = 'playoff';
    select array_agg(id order by sort_order, name) into group_ids from core.tournament_groups where class_id = class.id;
    group_ids := coalesce(group_ids, '{}');
  end if;

  idx := 0;
  for item in select value from jsonb_array_elements(schedule_matches) loop
    if schedule_stage = 'group' and ((item->>'group')::integer is null or (item->>'group')::integer >= coalesce(array_length(group_ids, 1), 0)
      or not (item->>'home')::uuid = any(approved) or not (item->>'away')::uuid = any(approved) or item->>'home' = item->>'away') then
      raise invalid_parameter_value using message = 'invalid_schedule';
    end if;
    if item->>'pitch_id' is not null and not exists (select 1 from core.tournament_pitches
      where id = (item->>'pitch_id')::uuid and tournament_id = class.tournament_id) then
      raise invalid_parameter_value using message = 'invalid_schedule';
    end if;
    insert into core.tournament_matches (tournament_id, class_id, group_id, stage, round, label,
      home_registration_id, away_registration_id, pitch_id, starts_at, ends_at, sort_order)
    values (class.tournament_id, class.id,
      case when schedule_stage = 'group' then group_ids[(item->>'group')::integer + 1] end,
      schedule_stage, coalesce((item->>'round')::integer, 1), nullif(btrim(item->>'label'), ''),
      case when schedule_stage = 'group' then (item->>'home')::uuid end,
      case when schedule_stage = 'group' then (item->>'away')::uuid end,
      (item->>'pitch_id')::uuid, (item->>'starts_at')::timestamptz, (item->>'ends_at')::timestamptz, idx)
    returning id into created;
    match_ids := match_ids || created;
    idx := idx + 1;
  end loop;

  -- Play-off sources, now that every match has its id.
  if schedule_stage = 'playoff' then
    idx := 0;
    for item in select value from jsonb_array_elements(schedule_matches) loop
      idx := idx + 1;
      for source_fix in select jsonb_build_object('side', side, 'source', item->side) from unnest(array['home_source', 'away_source']) side loop
        if source_fix->'source' is null or jsonb_typeof(source_fix->'source') <> 'object' then
          raise invalid_parameter_value using message = 'invalid_schedule';
        end if;
        if source_fix->'source'->>'kind' = 'group_place' then
          if (source_fix->'source'->>'group')::integer not between 0 and coalesce(array_length(group_ids, 1), 0) - 1
            or (source_fix->'source'->>'place')::integer not between 1 and 64 then
            raise invalid_parameter_value using message = 'invalid_schedule';
          end if;
          source_fix := jsonb_set(source_fix, '{source}', jsonb_build_object('kind', 'group_place',
            'group_id', group_ids[(source_fix->'source'->>'group')::integer + 1], 'place', (source_fix->'source'->>'place')::integer));
        elsif source_fix->'source'->>'kind' in ('winner', 'loser') then
          if (source_fix->'source'->>'match')::integer not between 0 and idx - 2 then
            raise invalid_parameter_value using message = 'invalid_schedule';
          end if;
          source_fix := jsonb_set(source_fix, '{source}', jsonb_build_object('kind', source_fix->'source'->>'kind',
            'match_id', match_ids[(source_fix->'source'->>'match')::integer + 1]));
        else
          raise invalid_parameter_value using message = 'invalid_schedule';
        end if;
        if source_fix->>'side' = 'home_source' then
          update core.tournament_matches set home_source = source_fix->'source' where id = match_ids[idx];
        else
          update core.tournament_matches set away_source = source_fix->'source' where id = match_ids[idx];
        end if;
      end loop;
    end loop;
    perform internal.tournament_resolve_class(class.id);
  end if;
  update core.tournament_classes set revision = revision + 1 where id = class.id;
  return coalesce(array_length(match_ids, 1), 0);
end;
$$;

-- Moves a match to another pitch or time.
create or replace function internal.set_tournament_match_time_for_actor(target_match_id uuid, target_pitch_id uuid, match_starts_at timestamptz, match_ends_at timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
declare game core.tournament_matches;
begin
  select * into game from core.tournament_matches where id = target_match_id;
  if game.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.tournament_require_organizer(game.tournament_id);
  if (match_starts_at is null) <> (match_ends_at is null) or match_ends_at <= match_starts_at then
    raise invalid_parameter_value using message = 'invalid_time';
  end if;
  if target_pitch_id is not null and not exists (select 1 from core.tournament_pitches
    where id = target_pitch_id and tournament_id = game.tournament_id) then
    raise invalid_parameter_value using message = 'not_found';
  end if;
  update core.tournament_matches set pitch_id = target_pitch_id, starts_at = match_starts_at, ends_at = match_ends_at,
    revision = revision + 1 where id = game.id;
end;
$$;

-- Organisers and officials report a result; a play-off match needs a
-- winner, by penalties if level. Null scores clear the result.
create or replace function internal.report_tournament_match_result_for_actor(
  target_match_id uuid, result_home integer, result_away integer, result_home_penalties integer, result_away_penalties integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare game core.tournament_matches; class core.tournament_classes;
begin
  select * into game from core.tournament_matches where id = target_match_id;
  if game.id is null or internal.tournament_actor_role(game.tournament_id) is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select * into class from core.tournament_classes where id = game.class_id;
  if class.format = 'pool' then raise invalid_parameter_value using message = 'no_results_in_pool'; end if;
  if game.home_registration_id is null or game.away_registration_id is null then
    raise invalid_parameter_value using message = 'teams_not_known';
  end if;
  -- A play-off match whose winner has played on keeps its result.
  if exists (select 1 from core.tournament_matches later where later.class_id = game.class_id and later.status = 'played'
    and game.id::text in (later.home_source->>'match_id', later.away_source->>'match_id')) then
    raise invalid_parameter_value using message = 'later_match_played';
  end if;
  if game.stage = 'group' and exists (select 1 from core.tournament_matches later where later.class_id = game.class_id
    and later.stage = 'playoff' and later.status = 'played'
    and game.group_id::text in (later.home_source->>'group_id', later.away_source->>'group_id')) then
    raise invalid_parameter_value using message = 'later_match_played';
  end if;
  if result_home is null and result_away is null then
    update core.tournament_matches set status = 'scheduled', home_score = null, away_score = null,
      home_penalties = null, away_penalties = null, reported_by = auth.uid(), reported_at = now(), revision = revision + 1
    where id = game.id;
  else
    if result_home is null or result_away is null or result_home < 0 or result_away < 0 then
      raise invalid_parameter_value using message = 'invalid_result';
    end if;
    if game.stage = 'playoff' and result_home = result_away and (result_home_penalties is null or result_away_penalties is null
      or result_home_penalties = result_away_penalties) then
      raise invalid_parameter_value using message = 'needs_winner';
    end if;
    update core.tournament_matches set status = 'played', home_score = result_home, away_score = result_away,
      home_penalties = case when game.stage = 'playoff' and result_home = result_away then result_home_penalties end,
      away_penalties = case when game.stage = 'playoff' and result_home = result_away then result_away_penalties end,
      reported_by = auth.uid(), reported_at = now(), revision = revision + 1
    where id = game.id;
  end if;
  perform internal.tournament_resolve_class(game.class_id);
  select * into game from core.tournament_matches where id = game.id;
  return internal.tournament_match_json(game);
end;
$$;

create or replace function internal.set_tournament_class_schedule_published_for_actor(target_class_id uuid, is_published boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare class core.tournament_classes;
begin
  select * into class from core.tournament_classes where id = target_class_id;
  if class.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.tournament_require_organizer(class.tournament_id);
  update core.tournament_classes set schedule_published = coalesce(is_published, false), revision = revision + 1 where id = class.id;
end;
$$;

-- As in 20261119090000, with the points for a win and a draw.
create or replace function internal.tournament_class_json(class core.tournament_classes)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', class.id, 'name', class.name, 'description', class.description, 'format', class.format,
    'max_teams', class.max_teams, 'fee_sek', class.fee_sek, 'match_minutes', class.match_minutes,
    'sort_order', class.sort_order, 'points_win', class.points_win, 'points_draw', class.points_draw,
    'schedule_published', class.schedule_published,
    'approved', (select count(*) from core.tournament_registrations registration
      where registration.class_id = class.id and registration.status = 'approved'),
    'pending', (select count(*) from core.tournament_registrations registration
      where registration.class_id = class.id and registration.status = 'pending')
  )
$$;

-- A team in a group or a match stays in it: it is struck from the
-- schedule only by planning the class again.
create or replace function internal.withdraw_tournament_registration_for_actor(target_registration_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare registration core.tournament_registrations;
begin
  select * into registration from core.tournament_registrations where id = target_registration_id;
  if registration.id is null or (registration.registered_by is distinct from auth.uid()
    and internal.tournament_actor_role(registration.tournament_id) is distinct from 'organizer') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if registration.status not in ('pending', 'approved') then raise invalid_parameter_value using message = 'not_active'; end if;
  if exists (select 1 from core.tournament_group_teams where registration_id = registration.id) then
    raise invalid_parameter_value using message = 'team_in_schedule';
  end if;
  update core.tournament_registrations set status = 'withdrawn', revision = revision + 1 where id = registration.id;
end;
$$;

create or replace function api.get_tournament_schedule(target_tournament_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.get_tournament_schedule_for_actor(target_tournament_id) $$;
create or replace function api.save_tournament_pitch(target_tournament_id uuid, target_pitch_id uuid, pitch_name text, pitch_sort_order integer)
returns uuid language sql security invoker set search_path = '' as
$$ select internal.save_tournament_pitch_for_actor(target_tournament_id, target_pitch_id, pitch_name, pitch_sort_order) $$;
create or replace function api.delete_tournament_pitch(target_pitch_id uuid) returns void language sql security invoker set search_path = '' as
$$ select internal.delete_tournament_pitch_for_actor(target_pitch_id) $$;
create or replace function api.save_tournament_class_schedule(target_class_id uuid, schedule_stage text, schedule_groups jsonb, schedule_matches jsonb)
returns integer language sql security invoker set search_path = '' as
$$ select internal.save_tournament_class_schedule_for_actor(target_class_id, schedule_stage, schedule_groups, schedule_matches) $$;
create or replace function api.set_tournament_match_time(target_match_id uuid, target_pitch_id uuid, match_starts_at timestamptz, match_ends_at timestamptz)
returns void language sql security invoker set search_path = '' as
$$ select internal.set_tournament_match_time_for_actor(target_match_id, target_pitch_id, match_starts_at, match_ends_at) $$;
create or replace function api.report_tournament_match_result(target_match_id uuid, result_home integer, result_away integer, result_home_penalties integer, result_away_penalties integer)
returns jsonb language sql security invoker set search_path = '' as
$$ select internal.report_tournament_match_result_for_actor(target_match_id, result_home, result_away, result_home_penalties, result_away_penalties) $$;
create or replace function api.set_tournament_class_schedule_published(target_class_id uuid, is_published boolean)
returns void language sql security invoker set search_path = '' as
$$ select internal.set_tournament_class_schedule_published_for_actor(target_class_id, is_published) $$;

revoke all on function
  internal.tournament_group_standings(uuid), internal.tournament_group_complete(uuid),
  internal.tournament_source_team(jsonb), internal.tournament_resolve_class(uuid),
  internal.tournament_source_label(jsonb), internal.tournament_match_json(core.tournament_matches),
  internal.get_tournament_schedule_for_actor(uuid),
  internal.save_tournament_pitch_for_actor(uuid, uuid, text, integer), internal.delete_tournament_pitch_for_actor(uuid),
  internal.save_tournament_class_schedule_for_actor(uuid, text, jsonb, jsonb),
  internal.set_tournament_match_time_for_actor(uuid, uuid, timestamptz, timestamptz),
  internal.report_tournament_match_result_for_actor(uuid, integer, integer, integer, integer),
  internal.set_tournament_class_schedule_published_for_actor(uuid, boolean),
  api.get_tournament_schedule(uuid), api.save_tournament_pitch(uuid, uuid, text, integer), api.delete_tournament_pitch(uuid),
  api.save_tournament_class_schedule(uuid, text, jsonb, jsonb),
  api.set_tournament_match_time(uuid, uuid, timestamptz, timestamptz),
  api.report_tournament_match_result(uuid, integer, integer, integer, integer),
  api.set_tournament_class_schedule_published(uuid, boolean)
from public, anon, authenticated;
grant execute on function
  internal.tournament_group_standings(uuid), internal.tournament_group_complete(uuid),
  internal.tournament_source_team(jsonb), internal.tournament_resolve_class(uuid),
  internal.tournament_source_label(jsonb), internal.tournament_match_json(core.tournament_matches),
  internal.get_tournament_schedule_for_actor(uuid),
  internal.save_tournament_pitch_for_actor(uuid, uuid, text, integer), internal.delete_tournament_pitch_for_actor(uuid),
  internal.save_tournament_class_schedule_for_actor(uuid, text, jsonb, jsonb),
  internal.set_tournament_match_time_for_actor(uuid, uuid, timestamptz, timestamptz),
  internal.report_tournament_match_result_for_actor(uuid, integer, integer, integer, integer),
  internal.set_tournament_class_schedule_published_for_actor(uuid, boolean),
  api.get_tournament_schedule(uuid), api.save_tournament_pitch(uuid, uuid, text, integer), api.delete_tournament_pitch(uuid),
  api.save_tournament_class_schedule(uuid, text, jsonb, jsonb),
  api.set_tournament_match_time(uuid, uuid, timestamptz, timestamptz),
  api.report_tournament_match_result(uuid, integer, integer, integer, integer),
  api.set_tournament_class_schedule_published(uuid, boolean)
to authenticated;
