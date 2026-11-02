-- Team Development Plan, new design step 8 (2026-11-02): the players'
-- load and the signals the leaders set (PAR-METHOD-01, decided by the
-- product owner 2026-11-02).
--
-- Counted per player: trainings attended, training minutes and match
-- minutes, over the last 7 days and the last 4 weeks. Training minutes
-- come from the attendance (present: the whole session; late: the session
-- less the minutes late; partial: the minutes present). Match minutes are
-- counted as the Match module's analysis counts them: the starters from 0,
-- each of our substitutions ending one spell and starting another, a red
-- card ending one, up to full time. Nothing is kept twice.
--
-- The signals are rules on the facts, never medical conclusions, and the
-- leaders set their values per team (they depend on the age group among
-- other things):
--   load_increase  the last 7 days' minutes are at least N % of the weekly
--                  average over the 4 weeks;
--   low_attendance under N % of the team's trainings with attendance taken
--                  in the 4 weeks;
--   match_minutes  more than N match minutes in the last 7 days.
-- An empty value turns the signal off. Self-rated effort waits for
-- PAR-PRIV-04.

create table core.team_development_load_settings (
  team_id uuid primary key references core.teams(id) on delete cascade,
  club_id uuid not null,
  load_increase_percent integer default 130 check (load_increase_percent between 100 and 400),
  attendance_min_percent integer default 50 check (attendance_min_percent between 1 and 100),
  match_minutes_max integer default 180 check (match_minutes_max between 1 and 1000),
  updated_by uuid references core.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
create index team_development_load_settings_updated_by on core.team_development_load_settings (updated_by);
alter table core.team_development_load_settings enable row level security;
revoke all on core.team_development_load_settings from public, anon, authenticated;
create policy team_development_load_settings_no_direct_access on core.team_development_load_settings
  for all to authenticated using (false) with check (false);

-- Minutes on the pitch per player in one of our matches.
create or replace function internal.tdp_match_minutes(target_event_id uuid)
returns table (club_person_id uuid, minutes integer) language plpgsql stable security definer set search_path = '' as $$
declare finish integer; since jsonb := '{}'; counted jsonb := '{}'; change record; at integer; off_id text; on_id text;
begin
  select coalesce(
      (select max(fact.minute) from core.match_facts fact
       where fact.event_id = target_event_id and fact.state = 'active' and fact.fact_type = 'full_time' and fact.minute > 0),
      (select sum(length)::integer from unnest(workspace.period_minutes) length))
    into finish
  from core.match_workspaces workspace where workspace.event_id = target_event_id;
  if finish is null then return; end if;
  select coalesce(jsonb_object_agg(starter.value->>'person_id', 0), '{}') into since
  from core.event_lineups lineup, jsonb_array_elements(lineup.starters) starter
  where lineup.event_id = target_event_id and starter.value->>'person_id' is not null;
  for change in
    select fact.minute, fact.club_person_id, fact.secondary_club_person_id, fact.fact_type = 'card' sending_off
    from core.match_facts fact
    where fact.event_id = target_event_id and fact.state = 'active' and coalesce(fact.side, 'us') <> 'opponent'
      and (fact.fact_type = 'substitution' or (fact.fact_type = 'card' and fact.detail->>'color' = 'red'))
    order by fact.minute, fact.created_at
  loop
    at := greatest(0, least(change.minute, finish));
    off_id := change.club_person_id::text;
    on_id := case when change.sending_off then null else change.secondary_club_person_id::text end;
    if off_id is not null and since ? off_id then
      counted := counted || jsonb_build_object(off_id, coalesce((counted->>off_id)::integer, 0) + at - (since->>off_id)::integer);
      since := since - off_id;
    end if;
    if on_id is not null and not since ? on_id then since := since || jsonb_build_object(on_id, at); end if;
  end loop;
  for off_id, at in select key, value::integer from jsonb_each_text(since) loop
    counted := counted || jsonb_build_object(off_id, coalesce((counted->>off_id)::integer, 0) + greatest(0, finish - at));
  end loop;
  return query select key::uuid, value::integer from jsonb_each_text(counted);
end;
$$;

-- The team's load settings, the defaults until the leaders set them.
create or replace function internal.tdp_load_settings(target_team_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'load_increase_percent', coalesce(setting.load_increase_percent, case when setting.team_id is null then 130 end),
    'attendance_min_percent', coalesce(setting.attendance_min_percent, case when setting.team_id is null then 50 end),
    'match_minutes_max', coalesce(setting.match_minutes_max, case when setting.team_id is null then 180 end))
  from (select 1) one left join core.team_development_load_settings setting on setting.team_id = target_team_id
$$;

-- The players' load up to [day]: per player the counts over 7 days and 4
-- weeks, and the signals the team's settings raise.
create or replace function internal.tdp_load(plan core.development_plans, day date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare settings jsonb := internal.tdp_load_settings(plan.team_id); players jsonb;
begin
  with held as (
    select event_row.id, event_row.event_type, (event_row.starts_at at time zone event_row.timezone)::date on_day,
      greatest(0, least(600, extract(epoch from event_row.ends_at - event_row.starts_at)::integer / 60)) length
    from core.events event_row
    where event_row.owning_team_id = plan.team_id and event_row.club_id = plan.club_id
      and event_row.event_type in ('training', 'match') and event_row.archived_at is null and event_row.state <> 'cancelled'
      and event_row.starts_at <= now()
      and (event_row.starts_at at time zone event_row.timezone)::date between day - 27 and day
  ), taken as (
    -- Trainings with attendance taken: what the attendance share counts.
    select held.* from held where held.event_type = 'training'
      and exists (select 1 from core.attendance_facts fact where fact.event_id = held.id and fact.status <> 'unknown')
  ), trained as (
    select fact.club_person_id, taken.on_day,
      case fact.status when 'present' then taken.length
        when 'late' then greatest(0, taken.length - coalesce(fact.minutes, 0))
        else least(taken.length, coalesce(fact.minutes, 0)) end minutes
    from taken join core.attendance_facts fact on fact.event_id = taken.id
    where fact.status in ('present', 'late', 'partial')
  ), played as (
    select played.club_person_id, held.on_day, played.minutes
    from held cross join lateral internal.tdp_match_minutes(held.id) played
    where held.event_type = 'match' and played.minutes > 0
  ), squad as (
    select distinct person.id, person.display_name from core.assignments assignment
    join core.club_people person on person.id = assignment.club_person_id
    where assignment.team_id = plan.team_id and assignment.club_id = plan.club_id
      and assignment.role_package = 'player' and assignment.state = 'active' and person.status = 'active'
  ), counted as (
    select squad.id, squad.display_name,
      (select count(*) from trained where trained.club_person_id = squad.id and trained.on_day > day - 7)::integer sessions_7,
      (select count(*) from trained where trained.club_person_id = squad.id)::integer sessions_28,
      (select coalesce(sum(minutes), 0) from trained where trained.club_person_id = squad.id and trained.on_day > day - 7)::integer training_7,
      (select coalesce(sum(minutes), 0) from trained where trained.club_person_id = squad.id)::integer training_28,
      (select coalesce(sum(minutes), 0) from played where played.club_person_id = squad.id and played.on_day > day - 7)::integer match_7,
      (select coalesce(sum(minutes), 0) from played where played.club_person_id = squad.id)::integer match_28,
      (select count(*) from taken)::integer trainings_28
    from squad
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'person_id', counted.id, 'name', counted.display_name,
      'sessions_7', counted.sessions_7, 'sessions_28', counted.sessions_28,
      'training_minutes_7', counted.training_7, 'training_minutes_28', counted.training_28,
      'match_minutes_7', counted.match_7, 'match_minutes_28', counted.match_28,
      'trainings_28', counted.trainings_28,
      'attendance_percent', case when counted.trainings_28 > 0
        then round(100.0 * counted.sessions_28 / counted.trainings_28)::integer end,
      'load_percent', case when counted.training_28 + counted.match_28 > 0
        then round(400.0 * (counted.training_7 + counted.match_7) / (counted.training_28 + counted.match_28))::integer end,
      'signals', to_jsonb(array_remove(array[
        case when (settings->>'load_increase_percent') is not null
          and counted.training_28 + counted.match_28 > counted.training_7 + counted.match_7
          and 400.0 * (counted.training_7 + counted.match_7) / (counted.training_28 + counted.match_28)
            >= (settings->>'load_increase_percent')::integer then 'load_increase' end,
        case when (settings->>'attendance_min_percent') is not null and counted.trainings_28 >= 3
          and 100.0 * counted.sessions_28 / counted.trainings_28 < (settings->>'attendance_min_percent')::integer
          then 'low_attendance' end,
        case when (settings->>'match_minutes_max') is not null
          and counted.match_7 > (settings->>'match_minutes_max')::integer then 'match_minutes' end
      ], null))
    ) order by counted.display_name, counted.id), '[]'::jsonb)
  into players from counted;
  return jsonb_build_object('day', day, 'settings', settings, 'players', players);
end;
$$;

-- The load for the one who reads the plan, up to [day] (today when none).
create or replace function internal.get_team_development_load_for_actor(target_plan_id uuid, target_day date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_plan(target_plan_id);
  return internal.tdp_load(plan, coalesce(target_day, (now() at time zone 'Europe/Stockholm')::date));
end;
$$;

-- The team's signal values; an empty value turns the signal off. No
-- revision: the settings sit beside the plan, as a check-in.
create or replace function internal.set_team_development_load_settings_for_actor(target_plan_id uuid,
  load_increase integer, attendance_min integer, match_minutes integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_checkin_plan(target_plan_id);
  if load_increase not between 100 and 400 or attendance_min not between 1 and 100
    or match_minutes not between 1 and 1000 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  insert into core.team_development_load_settings (team_id, club_id, load_increase_percent, attendance_min_percent,
    match_minutes_max, updated_by)
  values (plan.team_id, plan.club_id, load_increase, attendance_min, match_minutes, auth.uid())
  on conflict (team_id) do update set load_increase_percent = excluded.load_increase_percent,
    attendance_min_percent = excluded.attendance_min_percent, match_minutes_max = excluded.match_minutes_max,
    updated_by = excluded.updated_by, updated_at = now();
  return internal.tdp_load(plan, (now() at time zone 'Europe/Stockholm')::date);
end;
$$;

create or replace function api.get_team_development_load(target_plan_id uuid, target_day date) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select internal.get_team_development_load_for_actor(target_plan_id, target_day) $$;
create or replace function api.set_team_development_load_settings(target_plan_id uuid,
  load_increase integer, attendance_min integer, match_minutes integer) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.set_team_development_load_settings_for_actor(target_plan_id, load_increase, attendance_min, match_minutes) $$;

revoke all on function
  internal.tdp_match_minutes(uuid),
  internal.tdp_load_settings(uuid),
  internal.tdp_load(core.development_plans, date),
  internal.get_team_development_load_for_actor(uuid, date),
  internal.set_team_development_load_settings_for_actor(uuid, integer, integer, integer),
  api.get_team_development_load(uuid, date),
  api.set_team_development_load_settings(uuid, integer, integer, integer)
from public, anon, authenticated;
grant execute on function
  internal.get_team_development_load_for_actor(uuid, date),
  internal.set_team_development_load_settings_for_actor(uuid, integer, integer, integer),
  api.get_team_development_load(uuid, date),
  api.set_team_development_load_settings(uuid, integer, integer, integer)
to authenticated;
notify pgrst, 'reload schema';
