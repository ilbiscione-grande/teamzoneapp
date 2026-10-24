-- Team Development Plan, step 2 (decision package 11, MFD-10): the team's
-- way of playing and its key figures, with recurring check-ins.
--  * Principles per area of the game (attack, defence, the transitions, set
--    pieces, general).
--  * Key figures (e.g. shots per match) with a target, which direction is
--    better, and values recorded over time.
--  * Check-ins on goals (on track, at risk, off track, with a note) and
--    values on key figures, kept as history with who made them.
--  * How often the goals are checked: every one to four weeks, or never; the
--    assistant reminds when goals are due (list_my_team_development_checkins_due).
-- Principles and key figures change the plan on its revision, as in step 1;
-- check-ins are added beside it and never make another leader's plan stale.

alter table core.development_plans
  add column checkin_every_days integer check (checkin_every_days in (7, 14, 21, 28));

create table core.team_development_principles (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  plan_id uuid not null,
  area text not null check (area in ('attack', 'defence', 'transition_attack', 'transition_defence', 'set_pieces', 'general')),
  title text not null check (length(btrim(title)) between 2 and 120),
  description text not null default '' check (length(description) <= 2000),
  position integer not null default 0,
  updated_at timestamptz not null default now(),
  updated_by uuid references core.profiles(id) on delete set null,
  foreign key (plan_id, club_id) references core.development_plans(id, club_id) on delete cascade
);

create table core.team_development_kpis (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  plan_id uuid not null,
  title text not null check (length(btrim(title)) between 2 and 80),
  unit text not null default '' check (length(unit) <= 20),
  target numeric check (target between -1000000 and 1000000),
  higher_is_better boolean not null default true,
  position integer not null default 0,
  updated_at timestamptz not null default now(),
  updated_by uuid references core.profiles(id) on delete set null,
  unique (id, club_id),
  foreign key (plan_id, club_id) references core.development_plans(id, club_id) on delete cascade
);

-- A check-in on a goal (its status) or a key figure (its value).
create table core.team_development_checkins (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  plan_id uuid not null,
  goal_id uuid references core.team_development_goals(id) on delete cascade,
  kpi_id uuid,
  checked_on date not null,
  status text check (status in ('on_track', 'at_risk', 'off_track')),
  value numeric check (value between -1000000 and 1000000),
  note text not null default '' check (length(note) <= 2000),
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id) on delete set null,
  check ((goal_id is not null and status is not null and value is null and kpi_id is null)
      or (kpi_id is not null and value is not null and status is null and goal_id is null)),
  foreign key (plan_id, club_id) references core.development_plans(id, club_id) on delete cascade,
  foreign key (kpi_id, club_id) references core.team_development_kpis(id, club_id) on delete cascade
);

create index team_development_principles_plan on core.team_development_principles (plan_id, club_id, area, position);
create index team_development_principles_updated_by on core.team_development_principles (updated_by);
create index team_development_kpis_plan on core.team_development_kpis (plan_id, club_id, position);
create index team_development_kpis_updated_by on core.team_development_kpis (updated_by);
create index team_development_checkins_plan on core.team_development_checkins (plan_id, club_id, checked_on desc);
create index team_development_checkins_goal on core.team_development_checkins (goal_id, checked_on desc) where goal_id is not null;
create index team_development_checkins_kpi on core.team_development_checkins (kpi_id, club_id, checked_on desc) where kpi_id is not null;
create index team_development_checkins_created_by on core.team_development_checkins (created_by);

alter table core.team_development_principles enable row level security;
alter table core.team_development_kpis enable row level security;
alter table core.team_development_checkins enable row level security;
revoke all on core.team_development_principles, core.team_development_kpis, core.team_development_checkins
  from public, anon, authenticated;
create policy team_development_principles_no_direct_access on core.team_development_principles
  for all to authenticated using (false) with check (false);
create policy team_development_kpis_no_direct_access on core.team_development_kpis
  for all to authenticated using (false) with check (false);
create policy team_development_checkins_no_direct_access on core.team_development_checkins
  for all to authenticated using (false) with check (false);

-- As in step 1, with the check-in interval, principles, key figures and check-ins.
create or replace function internal.tdp_plan_json(plan core.development_plans)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', plan.id, 'title', plan.title, 'vision', plan.focus,
    'starts_on', plan.season_starts_on, 'ends_on', plan.season_ends_on,
    'checkin_every_days', plan.checkin_every_days,
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
      from core.team_development_goals goal where goal.plan_id = plan.id), '[]'::jsonb),
    'principles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', principle.id, 'area', principle.area, 'title', principle.title, 'description', principle.description
      ) order by principle.position, principle.updated_at)
      from core.team_development_principles principle where principle.plan_id = plan.id), '[]'::jsonb),
    'kpis', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', kpi.id, 'title', kpi.title, 'unit', kpi.unit, 'target', kpi.target, 'higher_is_better', kpi.higher_is_better
      ) order by kpi.position, kpi.updated_at)
      from core.team_development_kpis kpi where kpi.plan_id = plan.id), '[]'::jsonb),
    'checkins', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', checkin.id, 'goal_id', checkin.goal_id, 'kpi_id', checkin.kpi_id, 'checked_on', checkin.checked_on,
        'status', checkin.status, 'value', checkin.value, 'note', checkin.note,
        'created_at', checkin.created_at, 'created_by', internal.tdp_name(checkin.created_by)
      ) order by checkin.checked_on desc, checkin.created_at desc)
      from (select * from core.team_development_checkins latest where latest.plan_id = plan.id
        order by latest.checked_on desc, latest.created_at desc limit 500) checkin), '[]'::jsonb)
  )
$$;

-- The season with how often its goals are checked (null: never).
drop function api.save_team_development_plan(uuid, bigint, text, date, date, text);
drop function internal.save_team_development_plan_for_actor(uuid, bigint, text, date, date, text);
create function internal.save_team_development_plan_for_actor(
  target_plan_id uuid, expected_revision bigint, plan_title text, starts date, ends date, vision text, checkin_days integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  perform internal.tdp_check_season(plan_title, starts, ends, vision);
  if checkin_days is not null and checkin_days not in (7, 14, 21, 28) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
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
    season_starts_on = starts, season_ends_on = ends, checkin_every_days = checkin_days
  where id = plan.id returning * into plan;
  return internal.tdp_plan_json(plan);
end;
$$;

-- A principle (new when target_principle_id is null); at most 40.
create or replace function internal.save_team_development_principle_for_actor(
  target_plan_id uuid, expected_revision bigint, target_principle_id uuid, principle_area text,
  principle_title text, principle_description text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  if principle_area is null
    or principle_area not in ('attack', 'defence', 'transition_attack', 'transition_defence', 'set_pieces', 'general')
    or length(btrim(coalesce(principle_title, ''))) not between 2 and 120
    or length(coalesce(principle_description, '')) > 2000 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if target_principle_id is null then
    if (select count(*) from core.team_development_principles where plan_id = plan.id) >= 40 then
      raise invalid_parameter_value using message = 'too_many';
    end if;
    insert into core.team_development_principles (club_id, plan_id, area, title, description, position, updated_by)
    values (plan.club_id, plan.id, principle_area, btrim(principle_title), coalesce(principle_description, ''),
      coalesce((select max(position) + 1 from core.team_development_principles where plan_id = plan.id), 0), auth.uid());
  else
    update core.team_development_principles set area = principle_area, title = btrim(principle_title),
      description = coalesce(principle_description, ''), updated_at = now(), updated_by = auth.uid()
    where id = target_principle_id and plan_id = plan.id;
    if not found then raise insufficient_privilege using message = 'not_found'; end if;
  end if;
  return internal.tdp_plan_json(plan);
end;
$$;

create or replace function internal.delete_team_development_principle_for_actor(
  target_plan_id uuid, expected_revision bigint, target_principle_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  delete from core.team_development_principles where id = target_principle_id and plan_id = plan.id;
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.tdp_plan_json(plan);
end;
$$;

-- A key figure (new when target_kpi_id is null); at most 12.
create or replace function internal.save_team_development_kpi_for_actor(
  target_plan_id uuid, expected_revision bigint, target_kpi_id uuid, kpi_title text, kpi_unit text,
  kpi_target numeric, higher_better boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  if length(btrim(coalesce(kpi_title, ''))) not between 2 and 80 or length(coalesce(kpi_unit, '')) > 20
    or higher_better is null or (kpi_target is not null and kpi_target not between -1000000 and 1000000) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if target_kpi_id is null then
    if (select count(*) from core.team_development_kpis where plan_id = plan.id) >= 12 then
      raise invalid_parameter_value using message = 'too_many';
    end if;
    insert into core.team_development_kpis (club_id, plan_id, title, unit, target, higher_is_better, position, updated_by)
    values (plan.club_id, plan.id, btrim(kpi_title), btrim(coalesce(kpi_unit, '')), kpi_target, higher_better,
      coalesce((select max(position) + 1 from core.team_development_kpis where plan_id = plan.id), 0), auth.uid());
  else
    update core.team_development_kpis set title = btrim(kpi_title), unit = btrim(coalesce(kpi_unit, '')),
      target = kpi_target, higher_is_better = higher_better, updated_at = now(), updated_by = auth.uid()
    where id = target_kpi_id and plan_id = plan.id;
    if not found then raise insufficient_privilege using message = 'not_found'; end if;
  end if;
  return internal.tdp_plan_json(plan);
end;
$$;

create or replace function internal.delete_team_development_kpi_for_actor(
  target_plan_id uuid, expected_revision bigint, target_kpi_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  delete from core.team_development_kpis where id = target_kpi_id and plan_id = plan.id;
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.tdp_plan_json(plan);
end;
$$;

-- Before a check-in: the one asking may change the plan. No revision: a
-- check-in is added beside the plan and never conflicts with an edit.
create or replace function internal.tdp_checkin_plan(target_plan_id uuid)
returns core.development_plans language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_plan(target_plan_id);
  if not internal.tdp_can_edit(plan.club_id) then raise insufficient_privilege using message = 'not_allowed'; end if;
  perform pg_advisory_xact_lock(hashtextextended(plan.id::text, 1));
  return plan;
end;
$$;

-- A check-in on a goal (status) or a key figure (value), dated in the
-- season and not in the future; at most 2000 per plan.
create or replace function internal.add_team_development_checkin_for_actor(
  target_plan_id uuid, target_goal_id uuid, target_kpi_id uuid, checked date, checkin_status text,
  checkin_value numeric, checkin_note text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_checkin_plan(target_plan_id);
  if checked is null or length(coalesce(checkin_note, '')) > 2000
    or not ((target_goal_id is not null and target_kpi_id is null and checkin_value is null
          and checkin_status in ('on_track', 'at_risk', 'off_track'))
        or (target_kpi_id is not null and target_goal_id is null and checkin_status is null
          and checkin_value between -1000000 and 1000000)) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if checked < plan.season_starts_on or checked > least(plan.season_ends_on, current_date + 1) then
    raise invalid_parameter_value using message = 'outside_season';
  end if;
  if (target_goal_id is not null and not exists (
        select 1 from core.team_development_goals where id = target_goal_id and plan_id = plan.id))
    or (target_kpi_id is not null and not exists (
        select 1 from core.team_development_kpis where id = target_kpi_id and plan_id = plan.id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if (select count(*) from core.team_development_checkins where plan_id = plan.id) >= 2000 then
    raise invalid_parameter_value using message = 'too_many';
  end if;
  insert into core.team_development_checkins (club_id, plan_id, goal_id, kpi_id, checked_on, status, value, note, created_by)
  values (plan.club_id, plan.id, target_goal_id, target_kpi_id, checked, checkin_status, checkin_value,
    btrim(coalesce(checkin_note, '')), auth.uid());
  return internal.tdp_plan_json(plan);
end;
$$;

create or replace function internal.delete_team_development_checkin_for_actor(target_plan_id uuid, target_checkin_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_checkin_plan(target_plan_id);
  delete from core.team_development_checkins where id = target_checkin_id and plan_id = plan.id;
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.tdp_plan_json(plan);
end;
$$;

-- For the assistant: in each team where you plan the team's development and
-- today's season checks its goals, the open goals due for a check-in (the
-- season's, today's period's and short-term ones not yet passed) whose last
-- check-in, or change when never checked, is an interval ago.
create or replace function internal.list_my_team_development_checkins_due_for_actor()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('plan_id', due.plan_id, 'club_id', due.club_id, 'team_id', due.team_id,
      'title', due.title, 'due', due.due) order by due.title)
    from (
      select plan.id plan_id, plan.club_id, plan.team_id, plan.title, (
        select count(*) from core.team_development_goals goal
        where goal.plan_id = plan.id and goal.state = 'open'
          and (goal.horizon = 'season'
            or (goal.horizon = 'short' and goal.target_on >= current_date)
            or (goal.horizon = 'period' and exists (select 1 from core.team_development_periods period
              where period.id = goal.period_id and current_date between period.starts_on and period.ends_on)))
          and coalesce((select max(checkin.checked_on) from core.team_development_checkins checkin where checkin.goal_id = goal.id),
            goal.updated_at::date) <= current_date - plan.checkin_every_days
      ) due
      from core.development_plans plan
      where plan.plan_type = 'team' and plan.checkin_every_days is not null
        and current_date between plan.season_starts_on and plan.season_ends_on
        and exists (select 1 from core.person_account_links link
          where link.profile_id = auth.uid() and link.club_id = plan.club_id and link.state = 'active')
        and internal.module_allows_write(plan.club_id, 'module.team_development')
        and internal.actor_has_capability(plan.club_id, plan.team_id, 'development.manage')
    ) due
    where due.due > 0
  ), '[]'::jsonb);
end;
$$;

create function api.save_team_development_plan(target_plan_id uuid, expected_revision bigint, plan_title text,
  starts date, ends date, vision text, checkin_days integer) returns jsonb language sql security invoker set search_path = '' as $$
  select internal.save_team_development_plan_for_actor(target_plan_id, expected_revision, plan_title, starts, ends, vision, checkin_days) $$;
create or replace function api.save_team_development_principle(target_plan_id uuid, expected_revision bigint,
  target_principle_id uuid, principle_area text, principle_title text, principle_description text) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.save_team_development_principle_for_actor(target_plan_id, expected_revision, target_principle_id,
    principle_area, principle_title, principle_description) $$;
create or replace function api.delete_team_development_principle(target_plan_id uuid, expected_revision bigint,
  target_principle_id uuid) returns jsonb language sql security invoker set search_path = '' as $$
  select internal.delete_team_development_principle_for_actor(target_plan_id, expected_revision, target_principle_id) $$;
create or replace function api.save_team_development_kpi(target_plan_id uuid, expected_revision bigint, target_kpi_id uuid,
  kpi_title text, kpi_unit text, kpi_target numeric, higher_better boolean) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.save_team_development_kpi_for_actor(target_plan_id, expected_revision, target_kpi_id, kpi_title,
    kpi_unit, kpi_target, higher_better) $$;
create or replace function api.delete_team_development_kpi(target_plan_id uuid, expected_revision bigint, target_kpi_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  select internal.delete_team_development_kpi_for_actor(target_plan_id, expected_revision, target_kpi_id) $$;
create or replace function api.add_team_development_checkin(target_plan_id uuid, target_goal_id uuid, target_kpi_id uuid,
  checked date, checkin_status text, checkin_value numeric, checkin_note text) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.add_team_development_checkin_for_actor(target_plan_id, target_goal_id, target_kpi_id, checked,
    checkin_status, checkin_value, checkin_note) $$;
create or replace function api.delete_team_development_checkin(target_plan_id uuid, target_checkin_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.delete_team_development_checkin_for_actor(target_plan_id, target_checkin_id) $$;
create or replace function api.list_my_team_development_checkins_due() returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.list_my_team_development_checkins_due_for_actor() $$;

revoke all on function
  internal.tdp_checkin_plan(uuid),
  internal.save_team_development_plan_for_actor(uuid, bigint, text, date, date, text, integer),
  internal.save_team_development_principle_for_actor(uuid, bigint, uuid, text, text, text),
  internal.delete_team_development_principle_for_actor(uuid, bigint, uuid),
  internal.save_team_development_kpi_for_actor(uuid, bigint, uuid, text, text, numeric, boolean),
  internal.delete_team_development_kpi_for_actor(uuid, bigint, uuid),
  internal.add_team_development_checkin_for_actor(uuid, uuid, uuid, date, text, numeric, text),
  internal.delete_team_development_checkin_for_actor(uuid, uuid),
  internal.list_my_team_development_checkins_due_for_actor(),
  api.save_team_development_plan(uuid, bigint, text, date, date, text, integer),
  api.save_team_development_principle(uuid, bigint, uuid, text, text, text),
  api.delete_team_development_principle(uuid, bigint, uuid),
  api.save_team_development_kpi(uuid, bigint, uuid, text, text, numeric, boolean),
  api.delete_team_development_kpi(uuid, bigint, uuid),
  api.add_team_development_checkin(uuid, uuid, uuid, date, text, numeric, text),
  api.delete_team_development_checkin(uuid, uuid),
  api.list_my_team_development_checkins_due()
from public, anon, authenticated;
grant execute on function
  internal.save_team_development_plan_for_actor(uuid, bigint, text, date, date, text, integer),
  internal.save_team_development_principle_for_actor(uuid, bigint, uuid, text, text, text),
  internal.delete_team_development_principle_for_actor(uuid, bigint, uuid),
  internal.save_team_development_kpi_for_actor(uuid, bigint, uuid, text, text, numeric, boolean),
  internal.delete_team_development_kpi_for_actor(uuid, bigint, uuid),
  internal.add_team_development_checkin_for_actor(uuid, uuid, uuid, date, text, numeric, text),
  internal.delete_team_development_checkin_for_actor(uuid, uuid),
  internal.list_my_team_development_checkins_due_for_actor(),
  api.save_team_development_plan(uuid, bigint, text, date, date, text, integer),
  api.save_team_development_principle(uuid, bigint, uuid, text, text, text),
  api.delete_team_development_principle(uuid, bigint, uuid),
  api.save_team_development_kpi(uuid, bigint, uuid, text, text, numeric, boolean),
  api.delete_team_development_kpi(uuid, bigint, uuid),
  api.add_team_development_checkin(uuid, uuid, uuid, date, text, numeric, text),
  api.delete_team_development_checkin(uuid, uuid),
  api.list_my_team_development_checkins_due()
to authenticated;
notify pgrst, 'reload schema';
