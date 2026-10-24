-- Team Development Plan, step 1 (decision package 11, MFD-10/11/15): the
-- team's plan for a season, built on core.development_plans (team). A plan
-- with season dates is the module's; the built-in app's simple team plans
-- have none and stay as they are. The season has long-term goals, periods
-- with a phase, dates, a focus and their own temporary goals, and short-term
-- goals with a date that belong to no period. Every change is made on the
-- revision read and moves the plan's revision, so two leaders never
-- overwrite each other. Read and changed by those with development.manage
-- in the team; the players' view comes in a later step.

alter table core.development_plans
  add column season_starts_on date,
  add column season_ends_on date,
  add constraint development_plans_season_check check (
    (season_starts_on is null and season_ends_on is null)
    or (plan_type = 'team' and season_ends_on - season_starts_on between 28 and 550));
create unique index development_plans_team_season_idx
  on core.development_plans (team_id, season_starts_on) where season_starts_on is not null;

create table core.team_development_periods (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  plan_id uuid not null,
  name text not null check (length(btrim(name)) between 1 and 60),
  phase text not null check (phase in ('preseason', 'competition', 'break', 'other')),
  starts_on date not null,
  ends_on date not null,
  focus text not null default '' check (length(focus) <= 2000),
  updated_at timestamptz not null default now(),
  updated_by uuid references core.profiles(id) on delete set null,
  unique (id, club_id),
  check (ends_on >= starts_on),
  foreign key (plan_id, club_id) references core.development_plans(id, club_id) on delete cascade
);
create index team_development_periods_plan on core.team_development_periods (plan_id, starts_on);

-- A goal of the season, of a period, or short-term with a date.
create table core.team_development_goals (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  plan_id uuid not null,
  horizon text not null check (horizon in ('season', 'period', 'short')),
  period_id uuid,
  title text not null check (length(btrim(title)) between 2 and 160),
  description text not null default '' check (length(description) <= 2000),
  target_on date,
  state text not null default 'open' check (state in ('open', 'achieved', 'dropped')),
  position integer not null default 0,
  updated_at timestamptz not null default now(),
  updated_by uuid references core.profiles(id) on delete set null,
  check ((horizon = 'period') = (period_id is not null)),
  check ((horizon = 'short') = (target_on is not null)),
  foreign key (plan_id, club_id) references core.development_plans(id, club_id) on delete cascade,
  foreign key (period_id, club_id) references core.team_development_periods(id, club_id) on delete cascade
);
create index team_development_goals_plan on core.team_development_goals (plan_id, horizon, position);


create index team_development_periods_plan_club on core.team_development_periods (plan_id, club_id);
create index team_development_periods_updated_by on core.team_development_periods (updated_by);
create index team_development_goals_plan_club on core.team_development_goals (plan_id, club_id);
create index team_development_goals_period_club on core.team_development_goals (period_id, club_id) where period_id is not null;
create index team_development_goals_updated_by on core.team_development_goals (updated_by);

alter table core.team_development_periods enable row level security;
alter table core.team_development_goals enable row level security;
revoke all on core.team_development_periods, core.team_development_goals from public, anon, authenticated;
create policy team_development_periods_no_direct_access on core.team_development_periods
  for all to authenticated using (false) with check (false);
create policy team_development_goals_no_direct_access on core.team_development_goals
  for all to authenticated using (false) with check (false);

-- The team's club, when the one asking may read its plan.
create or replace function internal.tdp_team_club(target_team_id uuid)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare club uuid;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select team.club_id into club from core.teams team where team.id = target_team_id;
  if club is null or not internal.module_allows_read(club, 'module.team_development')
    or not internal.actor_has_capability(club, target_team_id, 'development.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return club;
end;
$$;

create or replace function internal.tdp_can_edit(target_club_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select internal.module_allows_write(target_club_id, 'module.team_development')
$$;

-- A season plan of the module, for one who may read it.
create or replace function internal.tdp_plan(target_plan_id uuid)
returns core.development_plans language plpgsql stable security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  select * into plan from core.development_plans
  where id = target_plan_id and plan_type = 'team' and season_starts_on is not null;
  if plan.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.tdp_team_club(plan.team_id);
  return plan;
end;
$$;

-- Before a change: the one asking may change the plan, and it is still at
-- the revision read. Moves the revision on.
create or replace function internal.tdp_change(target_plan_id uuid, expected_revision bigint)
returns core.development_plans language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_plan(target_plan_id);
  if not internal.tdp_can_edit(plan.club_id) then raise insufficient_privilege using message = 'not_allowed'; end if;
  select * into plan from core.development_plans where id = plan.id for update;
  if plan.revision <> coalesce(expected_revision, -1) then raise serialization_failure using message = 'stale_revision'; end if;
  update core.development_plans set revision = revision + 1, updated_at = now(), updated_by = auth.uid()
  where id = plan.id returning * into plan;
  return plan;
end;
$$;

create or replace function internal.tdp_name(profile uuid)
returns text language sql stable security definer set search_path = '' as $$
  select nullif(btrim(display_name), '') from core.profiles where id = profile
$$;

create or replace function internal.tdp_plan_json(plan core.development_plans)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', plan.id, 'title', plan.title, 'vision', plan.focus,
    'starts_on', plan.season_starts_on, 'ends_on', plan.season_ends_on,
    'revision', plan.revision, 'updated_at', plan.updated_at, 'updated_by', internal.tdp_name(plan.updated_by),
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', period.id, 'name', period.name, 'phase', period.phase,
        'starts_on', period.starts_on, 'ends_on', period.ends_on, 'focus', period.focus
      ) order by period.starts_on)
      from core.team_development_periods period where period.plan_id = plan.id), '[]'::jsonb),
    'goals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', goal.id, 'horizon', goal.horizon, 'period_id', goal.period_id, 'title', goal.title,
        'description', goal.description, 'target_on', goal.target_on, 'state', goal.state,
        'updated_at', goal.updated_at, 'updated_by', internal.tdp_name(goal.updated_by)
      ) order by goal.position, goal.updated_at)
      from core.team_development_goals goal where goal.plan_id = plan.id), '[]'::jsonb)
  )
$$;

-- The team's seasons and one plan: the one asked for, else the season of
-- today, else the next, else the latest.
create or replace function internal.get_team_development_for_actor(target_team_id uuid, target_plan_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  club uuid;
  plan core.development_plans;
begin
  club := internal.tdp_team_club(target_team_id);
  select * into plan from core.development_plans candidate
  where candidate.team_id = target_team_id and candidate.plan_type = 'team' and candidate.season_starts_on is not null
    and (target_plan_id is null or candidate.id = target_plan_id)
  order by (current_date between candidate.season_starts_on and candidate.season_ends_on) desc,
    (candidate.season_starts_on > current_date) desc,
    case when candidate.season_starts_on > current_date then candidate.season_starts_on end asc,
    candidate.season_starts_on desc
  limit 1;
  if target_plan_id is not null and plan.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  return jsonb_build_object(
    'team_id', target_team_id,
    'can_edit', internal.tdp_can_edit(club),
    'seasons', coalesce((
      select jsonb_agg(jsonb_build_object('id', season.id, 'title', season.title,
        'starts_on', season.season_starts_on, 'ends_on', season.season_ends_on) order by season.season_starts_on desc)
      from core.development_plans season
      where season.team_id = target_team_id and season.plan_type = 'team' and season.season_starts_on is not null), '[]'::jsonb),
    'plan', case when plan.id is not null then internal.tdp_plan_json(plan) end
  );
end;
$$;

create or replace function internal.tdp_check_season(plan_title text, starts date, ends date, vision text)
returns void language plpgsql immutable set search_path = '' as $$
begin
  if length(btrim(coalesce(plan_title, ''))) not between 2 and 120 or length(coalesce(vision, '')) > 4000
    or starts is null or ends is null or ends - starts not between 28 and 550 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
end;
$$;

create or replace function internal.create_team_development_plan_for_actor(
  target_team_id uuid, plan_title text, starts date, ends date, vision text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  club uuid;
  plan core.development_plans;
begin
  club := internal.tdp_team_club(target_team_id);
  if not internal.tdp_can_edit(club) then raise insufficient_privilege using message = 'not_allowed'; end if;
  perform internal.tdp_check_season(plan_title, starts, ends, vision);
  if exists (select 1 from core.development_plans other where other.team_id = target_team_id
      and other.season_starts_on is not null and other.season_starts_on <= ends and other.season_ends_on >= starts) then
    raise unique_violation using message = 'overlapping_season';
  end if;
  insert into core.development_plans (club_id, team_id, plan_type, title, focus, state, created_by, updated_by,
    season_starts_on, season_ends_on)
  values (club, target_team_id, 'team', btrim(plan_title), coalesce(vision, ''), 'active', auth.uid(), auth.uid(), starts, ends)
  returning * into plan;
  return internal.tdp_plan_json(plan);
end;
$$;

create or replace function internal.save_team_development_plan_for_actor(
  target_plan_id uuid, expected_revision bigint, plan_title text, starts date, ends date, vision text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  perform internal.tdp_check_season(plan_title, starts, ends, vision);
  if exists (select 1 from core.development_plans other where other.team_id = plan.team_id and other.id <> plan.id
      and other.season_starts_on is not null and other.season_starts_on <= ends and other.season_ends_on >= starts) then
    raise unique_violation using message = 'overlapping_season';
  end if;
  if exists (select 1 from core.team_development_periods period where period.plan_id = plan.id
      and (period.starts_on < starts or period.ends_on > ends))
    or exists (select 1 from core.team_development_goals goal where goal.plan_id = plan.id
      and goal.target_on is not null and goal.target_on not between starts and ends) then
    raise invalid_parameter_value using message = 'outside_season';
  end if;
  update core.development_plans set title = btrim(plan_title), focus = coalesce(vision, ''),
    season_starts_on = starts, season_ends_on = ends
  where id = plan.id returning * into plan;
  return internal.tdp_plan_json(plan);
end;
$$;

-- A new period (target_period_id null) or a change to one: inside the
-- season and not overlapping another; at most 12.
create or replace function internal.save_team_development_period_for_actor(
  target_plan_id uuid, expected_revision bigint, target_period_id uuid,
  period_name text, period_phase text, starts date, ends date, period_focus text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  if length(btrim(coalesce(period_name, ''))) not between 1 and 60 or length(coalesce(period_focus, '')) > 2000
    or period_phase is null or period_phase not in ('preseason', 'competition', 'break', 'other')
    or starts is null or ends is null or ends < starts then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if starts < plan.season_starts_on or ends > plan.season_ends_on then
    raise invalid_parameter_value using message = 'outside_season';
  end if;
  if exists (select 1 from core.team_development_periods other where other.plan_id = plan.id
      and other.id is distinct from target_period_id and other.starts_on <= ends and other.ends_on >= starts) then
    raise unique_violation using message = 'overlapping_period';
  end if;
  if target_period_id is null then
    if (select count(*) from core.team_development_periods where plan_id = plan.id) >= 12 then
      raise invalid_parameter_value using message = 'too_many';
    end if;
    insert into core.team_development_periods (club_id, plan_id, name, phase, starts_on, ends_on, focus, updated_by)
    values (plan.club_id, plan.id, btrim(period_name), period_phase, starts, ends, coalesce(period_focus, ''), auth.uid());
  else
    update core.team_development_periods set name = btrim(period_name), phase = period_phase, starts_on = starts,
      ends_on = ends, focus = coalesce(period_focus, ''), updated_at = now(), updated_by = auth.uid()
    where id = target_period_id and plan_id = plan.id;
    if not found then raise insufficient_privilege using message = 'not_found'; end if;
  end if;
  return internal.tdp_plan_json(plan);
end;
$$;

-- Removes a period and its own goals.
create or replace function internal.delete_team_development_period_for_actor(
  target_plan_id uuid, expected_revision bigint, target_period_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  delete from core.team_development_periods where id = target_period_id and plan_id = plan.id;
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.tdp_plan_json(plan);
end;
$$;

-- A new goal (target_goal_id null) or a change to one; at most 60.
create or replace function internal.save_team_development_goal_for_actor(
  target_plan_id uuid, expected_revision bigint, target_goal_id uuid, goal_horizon text, target_period_id uuid,
  goal_title text, goal_description text, goal_target_on date, goal_state text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  if length(btrim(coalesce(goal_title, ''))) not between 2 and 160 or length(coalesce(goal_description, '')) > 2000
    or goal_horizon is null or goal_horizon not in ('season', 'period', 'short')
    or goal_state is null or goal_state not in ('open', 'achieved', 'dropped')
    or (goal_horizon = 'period') <> (target_period_id is not null)
    or (goal_horizon = 'short') <> (goal_target_on is not null) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if target_period_id is not null and not exists (
      select 1 from core.team_development_periods where id = target_period_id and plan_id = plan.id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if goal_target_on is not null and goal_target_on not between plan.season_starts_on and plan.season_ends_on then
    raise invalid_parameter_value using message = 'outside_season';
  end if;
  if target_goal_id is null then
    if (select count(*) from core.team_development_goals where plan_id = plan.id) >= 60 then
      raise invalid_parameter_value using message = 'too_many';
    end if;
    insert into core.team_development_goals (club_id, plan_id, horizon, period_id, title, description, target_on, state,
      position, updated_by)
    values (plan.club_id, plan.id, goal_horizon, target_period_id, btrim(goal_title), coalesce(goal_description, ''),
      goal_target_on, goal_state,
      coalesce((select max(position) + 1 from core.team_development_goals where plan_id = plan.id), 0), auth.uid());
  else
    update core.team_development_goals set horizon = goal_horizon, period_id = target_period_id, title = btrim(goal_title),
      description = coalesce(goal_description, ''), target_on = goal_target_on, state = goal_state,
      updated_at = now(), updated_by = auth.uid()
    where id = target_goal_id and plan_id = plan.id;
    if not found then raise insufficient_privilege using message = 'not_found'; end if;
  end if;
  return internal.tdp_plan_json(plan);
end;
$$;

create or replace function internal.delete_team_development_goal_for_actor(
  target_plan_id uuid, expected_revision bigint, target_goal_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  delete from core.team_development_goals where id = target_goal_id and plan_id = plan.id;
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.tdp_plan_json(plan);
end;
$$;

create or replace function api.get_team_development(target_team_id uuid, target_plan_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_team_development_for_actor(target_team_id, target_plan_id) $$;
create or replace function api.create_team_development_plan(target_team_id uuid, plan_title text, starts date, ends date, vision text)
returns jsonb language sql security invoker set search_path = '' as $$
  select internal.create_team_development_plan_for_actor(target_team_id, plan_title, starts, ends, vision) $$;
create or replace function api.save_team_development_plan(target_plan_id uuid, expected_revision bigint, plan_title text,
  starts date, ends date, vision text) returns jsonb language sql security invoker set search_path = '' as $$
  select internal.save_team_development_plan_for_actor(target_plan_id, expected_revision, plan_title, starts, ends, vision) $$;
create or replace function api.save_team_development_period(target_plan_id uuid, expected_revision bigint, target_period_id uuid,
  period_name text, period_phase text, starts date, ends date, period_focus text) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.save_team_development_period_for_actor(target_plan_id, expected_revision, target_period_id,
    period_name, period_phase, starts, ends, period_focus) $$;
create or replace function api.delete_team_development_period(target_plan_id uuid, expected_revision bigint, target_period_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  select internal.delete_team_development_period_for_actor(target_plan_id, expected_revision, target_period_id) $$;
create or replace function api.save_team_development_goal(target_plan_id uuid, expected_revision bigint, target_goal_id uuid,
  goal_horizon text, target_period_id uuid, goal_title text, goal_description text, goal_target_on date, goal_state text)
returns jsonb language sql security invoker set search_path = '' as $$
  select internal.save_team_development_goal_for_actor(target_plan_id, expected_revision, target_goal_id, goal_horizon,
    target_period_id, goal_title, goal_description, goal_target_on, goal_state) $$;
create or replace function api.delete_team_development_goal(target_plan_id uuid, expected_revision bigint, target_goal_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  select internal.delete_team_development_goal_for_actor(target_plan_id, expected_revision, target_goal_id) $$;

revoke all on function
  internal.tdp_team_club(uuid), internal.tdp_can_edit(uuid), internal.tdp_plan(uuid), internal.tdp_change(uuid, bigint),
  internal.tdp_name(uuid), internal.tdp_plan_json(core.development_plans), internal.tdp_check_season(text, date, date, text),
  internal.get_team_development_for_actor(uuid, uuid),
  internal.create_team_development_plan_for_actor(uuid, text, date, date, text),
  internal.save_team_development_plan_for_actor(uuid, bigint, text, date, date, text),
  internal.save_team_development_period_for_actor(uuid, bigint, uuid, text, text, date, date, text),
  internal.delete_team_development_period_for_actor(uuid, bigint, uuid),
  internal.save_team_development_goal_for_actor(uuid, bigint, uuid, text, uuid, text, text, date, text),
  internal.delete_team_development_goal_for_actor(uuid, bigint, uuid),
  api.get_team_development(uuid, uuid), api.create_team_development_plan(uuid, text, date, date, text),
  api.save_team_development_plan(uuid, bigint, text, date, date, text),
  api.save_team_development_period(uuid, bigint, uuid, text, text, date, date, text),
  api.delete_team_development_period(uuid, bigint, uuid),
  api.save_team_development_goal(uuid, bigint, uuid, text, uuid, text, text, date, text),
  api.delete_team_development_goal(uuid, bigint, uuid)
from public, anon, authenticated;
grant execute on function
  internal.get_team_development_for_actor(uuid, uuid),
  internal.create_team_development_plan_for_actor(uuid, text, date, date, text),
  internal.save_team_development_plan_for_actor(uuid, bigint, text, date, date, text),
  internal.save_team_development_period_for_actor(uuid, bigint, uuid, text, text, date, date, text),
  internal.delete_team_development_period_for_actor(uuid, bigint, uuid),
  internal.save_team_development_goal_for_actor(uuid, bigint, uuid, text, uuid, text, text, date, text),
  internal.delete_team_development_goal_for_actor(uuid, bigint, uuid),
  api.get_team_development(uuid, uuid), api.create_team_development_plan(uuid, text, date, date, text),
  api.save_team_development_plan(uuid, bigint, text, date, date, text),
  api.save_team_development_period(uuid, bigint, uuid, text, text, date, date, text),
  api.delete_team_development_period(uuid, bigint, uuid),
  api.save_team_development_goal(uuid, bigint, uuid, text, uuid, text, text, date, text),
  api.delete_team_development_goal(uuid, bigint, uuid)
to authenticated;
notify pgrst, 'reload schema';
