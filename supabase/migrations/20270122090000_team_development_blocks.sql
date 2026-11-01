-- Team Development Plan, new design step 1 (the product owner's decisions
-- 2026-11-01, docs/implementation/tdp-redesign.md):
--  * Blocks: a period is split into blocks of a few weeks, each with a name,
--    a focus, the principles in focus and its own short-term goals. Blocks
--    lie inside their period and never overlap; a period moved with the same
--    length takes its blocks along.
--  * Goals in levels: the season's (long-term), a period's and a block's
--    (short-term). The earlier dated short-term goals stay as they are.
--  * Sharing also covers the blocks; the block goals follow the goals'
--    sharing.
--  * Check-ins follow the plan: the goals of a block, a period or the season
--    are due when it ends (within four weeks after), unless checked from a
--    week before its end. The interval in days is no longer read.
--  * The suggestion for an event's preparation names the day's block with
--    its focus, principles and goals.
-- The earlier signatures of save_team_development_goal and
-- set_team_development_sharing stay as wrappers until the app no longer
-- calls them.

create table core.team_development_blocks (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  plan_id uuid not null,
  period_id uuid not null,
  name text not null check (length(btrim(name)) between 1 and 80),
  starts_on date not null,
  ends_on date not null,
  focus text not null default '' check (length(focus) <= 2000),
  updated_at timestamptz not null default now(),
  updated_by uuid references core.profiles(id) on delete set null,
  unique (id, club_id),
  check (ends_on >= starts_on),
  foreign key (plan_id, club_id) references core.development_plans(id, club_id) on delete cascade,
  foreign key (period_id, club_id) references core.team_development_periods(id, club_id) on delete cascade
);
create index team_development_blocks_plan on core.team_development_blocks (plan_id, club_id, starts_on);
create index team_development_blocks_period on core.team_development_blocks (period_id, club_id);
create index team_development_blocks_updated_by on core.team_development_blocks (updated_by);

-- The principles in focus in a block, in the order chosen.
create table core.team_development_block_principles (
  block_id uuid not null references core.team_development_blocks(id) on delete cascade,
  principle_id uuid not null references core.team_development_principles(id) on delete cascade,
  position integer not null default 0,
  primary key (block_id, principle_id)
);
create index team_development_block_principles_principle on core.team_development_block_principles (principle_id);

alter table core.team_development_blocks enable row level security;
alter table core.team_development_block_principles enable row level security;
revoke all on core.team_development_blocks, core.team_development_block_principles from public, anon, authenticated;
create policy team_development_blocks_no_direct_access on core.team_development_blocks
  for all to authenticated using (false) with check (false);
create policy team_development_block_principles_no_direct_access on core.team_development_block_principles
  for all to authenticated using (false) with check (false);

-- A goal of a block.
alter table core.team_development_goals add column block_id uuid;
alter table core.team_development_goals add constraint team_development_goals_block_fk
  foreign key (block_id, club_id) references core.team_development_blocks(id, club_id) on delete cascade;
create index team_development_goals_block_club on core.team_development_goals (block_id, club_id) where block_id is not null;
do $$
declare constraint_name text;
begin
  for constraint_name in
    select con.conname from pg_constraint con
    where con.conrelid = 'core.team_development_goals'::regclass and con.contype = 'c'
      and pg_get_constraintdef(con.oid) like '%horizon%'
      and pg_get_constraintdef(con.oid) not like '%target_on%'
  loop
    execute format('alter table core.team_development_goals drop constraint %I', constraint_name);
  end loop;
end $$;
alter table core.team_development_goals
  add constraint team_development_goals_horizon_check check (horizon in ('season', 'period', 'block', 'short')),
  add constraint team_development_goals_period_check check ((horizon = 'period') = (period_id is not null)),
  add constraint team_development_goals_block_check check ((horizon = 'block') = (block_id is not null));

alter table core.development_plans
  add column share_blocks boolean not null default false;

create or replace function internal.tdp_block_principles(target_block_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', principle.id, 'area', principle.area, 'title', principle.title)
      order by chosen.position), '[]'::jsonb)
  from core.team_development_block_principles chosen
  join core.team_development_principles principle on principle.id = chosen.principle_id
  where chosen.block_id = target_block_id
$$;

-- As in the sharing step, with the blocks, the block goals and the blocks' sharing.
create or replace function internal.tdp_plan_json(plan core.development_plans)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', plan.id, 'title', plan.title, 'vision', plan.focus,
    'starts_on', plan.season_starts_on, 'ends_on', plan.season_ends_on,
    'checkin_every_days', plan.checkin_every_days,
    'sharing', jsonb_build_object('vision', plan.share_vision, 'periods', plan.share_periods,
      'principles', plan.share_principles, 'goals', plan.share_goals, 'blocks', plan.share_blocks),
    'revision', plan.revision, 'updated_at', plan.updated_at, 'updated_by', internal.tdp_name(plan.updated_by),
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', period.id, 'name', period.name, 'phase', period.phase,
        'starts_on', period.starts_on, 'ends_on', period.ends_on, 'focus', period.focus
      ) order by period.starts_on)
      from core.team_development_periods period where period.plan_id = plan.id), '[]'::jsonb),
    'blocks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', block.id, 'period_id', block.period_id, 'name', block.name,
        'starts_on', block.starts_on, 'ends_on', block.ends_on, 'focus', block.focus,
        'principles', internal.tdp_block_principles(block.id)
      ) order by block.starts_on)
      from core.team_development_blocks block where block.plan_id = plan.id), '[]'::jsonb),
    'goals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', goal.id, 'horizon', goal.horizon, 'period_id', goal.period_id, 'block_id', goal.block_id,
        'title', goal.title, 'description', goal.description, 'target_on', goal.target_on, 'state', goal.state,
        'updated_at', goal.updated_at, 'updated_by', internal.tdp_name(goal.updated_by),
        'links', internal.tdp_goal_links(goal.id, false)
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

-- A period as in step 1, but its blocks stay inside it: moved with the same
-- length, the blocks go along; otherwise no block may fall outside.
create or replace function internal.save_team_development_period_for_actor(
  target_plan_id uuid, expected_revision bigint, target_period_id uuid,
  period_name text, period_phase text, starts date, ends date, period_focus text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans; old core.team_development_periods;
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
    select * into old from core.team_development_periods where id = target_period_id and plan_id = plan.id;
    if old.id is null then raise insufficient_privilege using message = 'not_found'; end if;
    if starts - old.starts_on = ends - old.ends_on then
      update core.team_development_blocks set starts_on = starts_on + (starts - old.starts_on),
        ends_on = ends_on + (starts - old.starts_on)
      where period_id = old.id;
    elsif exists (select 1 from core.team_development_blocks block where block.period_id = old.id
        and (block.starts_on < starts or block.ends_on > ends)) then
      raise invalid_parameter_value using message = 'outside_period';
    end if;
    update core.team_development_periods set name = btrim(period_name), phase = period_phase, starts_on = starts,
      ends_on = ends, focus = coalesce(period_focus, ''), updated_at = now(), updated_by = auth.uid()
    where id = old.id;
  end if;
  return internal.tdp_plan_json(plan);
end;
$$;

-- A new block (target_block_id null) or a change to one: inside its period,
-- not overlapping another block, with up to eight of the plan's principles;
-- at most 60 in a plan.
create or replace function internal.save_team_development_block_for_actor(
  target_plan_id uuid, expected_revision bigint, target_block_id uuid, target_period_id uuid,
  block_name text, starts date, ends date, block_focus text, principle_ids uuid[]
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans; period core.team_development_periods; block uuid;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  if length(btrim(coalesce(block_name, ''))) not between 1 and 80 or length(coalesce(block_focus, '')) > 2000
    or starts is null or ends is null or ends < starts
    or coalesce(cardinality(principle_ids), 0) > 8
    or (select count(distinct chosen) from unnest(coalesce(principle_ids, '{}')) chosen)
      <> coalesce(cardinality(principle_ids), 0) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select * into period from core.team_development_periods where id = target_period_id and plan_id = plan.id;
  if period.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  if starts < period.starts_on or ends > period.ends_on then
    raise invalid_parameter_value using message = 'outside_period';
  end if;
  if exists (select 1 from core.team_development_blocks other where other.plan_id = plan.id
      and other.id is distinct from target_block_id and other.starts_on <= ends and other.ends_on >= starts) then
    raise unique_violation using message = 'overlapping_block';
  end if;
  if exists (select 1 from unnest(coalesce(principle_ids, '{}')) chosen
      where not exists (select 1 from core.team_development_principles principle
        where principle.id = chosen and principle.plan_id = plan.id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if target_block_id is null then
    if (select count(*) from core.team_development_blocks where plan_id = plan.id) >= 60 then
      raise invalid_parameter_value using message = 'too_many';
    end if;
    insert into core.team_development_blocks (club_id, plan_id, period_id, name, starts_on, ends_on, focus, updated_by)
    values (plan.club_id, plan.id, period.id, btrim(block_name), starts, ends, coalesce(block_focus, ''), auth.uid())
    returning id into block;
  else
    update core.team_development_blocks set period_id = period.id, name = btrim(block_name), starts_on = starts,
      ends_on = ends, focus = coalesce(block_focus, ''), updated_at = now(), updated_by = auth.uid()
    where id = target_block_id and plan_id = plan.id
    returning id into block;
    if block is null then raise insufficient_privilege using message = 'not_found'; end if;
    delete from core.team_development_block_principles where block_id = block;
  end if;
  insert into core.team_development_block_principles (block_id, principle_id, position)
  select block, chosen.principle_id, chosen.position - 1
  from unnest(coalesce(principle_ids, '{}')) with ordinality as chosen(principle_id, position);
  return internal.tdp_plan_json(plan);
end;
$$;

-- Removes a block and its own goals.
create or replace function internal.delete_team_development_block_for_actor(
  target_plan_id uuid, expected_revision bigint, target_block_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  delete from core.team_development_blocks where id = target_block_id and plan_id = plan.id;
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.tdp_plan_json(plan);
end;
$$;

-- A goal as in step 1, also of a block (horizon 'block' with its block).
create or replace function internal.save_team_development_goal_for_actor(
  target_plan_id uuid, expected_revision bigint, target_goal_id uuid, goal_horizon text, target_period_id uuid,
  target_block_id uuid, goal_title text, goal_description text, goal_target_on date, goal_state text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  if length(btrim(coalesce(goal_title, ''))) not between 2 and 160 or length(coalesce(goal_description, '')) > 2000
    or goal_horizon is null or goal_horizon not in ('season', 'period', 'block', 'short')
    or goal_state is null or goal_state not in ('open', 'achieved', 'dropped')
    or (goal_horizon = 'period') <> (target_period_id is not null)
    or (goal_horizon = 'block') <> (target_block_id is not null)
    or (goal_horizon = 'short') <> (goal_target_on is not null) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if (target_period_id is not null and not exists (
        select 1 from core.team_development_periods where id = target_period_id and plan_id = plan.id))
    or (target_block_id is not null and not exists (
        select 1 from core.team_development_blocks where id = target_block_id and plan_id = plan.id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if goal_target_on is not null and goal_target_on not between plan.season_starts_on and plan.season_ends_on then
    raise invalid_parameter_value using message = 'outside_season';
  end if;
  if target_goal_id is null then
    if (select count(*) from core.team_development_goals where plan_id = plan.id) >= 120 then
      raise invalid_parameter_value using message = 'too_many';
    end if;
    insert into core.team_development_goals (club_id, plan_id, horizon, period_id, block_id, title, description,
      target_on, state, position, updated_by)
    values (plan.club_id, plan.id, goal_horizon, target_period_id, target_block_id, btrim(goal_title),
      coalesce(goal_description, ''), goal_target_on, goal_state,
      coalesce((select max(position) + 1 from core.team_development_goals where plan_id = plan.id), 0), auth.uid());
  else
    update core.team_development_goals set horizon = goal_horizon, period_id = target_period_id,
      block_id = target_block_id, title = btrim(goal_title), description = coalesce(goal_description, ''),
      target_on = goal_target_on, state = goal_state, updated_at = now(), updated_by = auth.uid()
    where id = target_goal_id and plan_id = plan.id;
    if not found then raise insufficient_privilege using message = 'not_found'; end if;
  end if;
  return internal.tdp_plan_json(plan);
end;
$$;

-- The earlier signature: a goal of the season, a period or a date.
create or replace function internal.save_team_development_goal_for_actor(
  target_plan_id uuid, expected_revision bigint, target_goal_id uuid, goal_horizon text, target_period_id uuid,
  goal_title text, goal_description text, goal_target_on date, goal_state text
) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if goal_horizon = 'block' then raise invalid_parameter_value using message = 'invalid_input'; end if;
  return internal.save_team_development_goal_for_actor(target_plan_id, expected_revision, target_goal_id, goal_horizon,
    target_period_id, null, goal_title, goal_description, goal_target_on, goal_state);
end;
$$;

create or replace function internal.set_team_development_sharing_for_actor(
  target_plan_id uuid, expected_revision bigint, vision boolean, periods boolean, principles boolean, goals boolean,
  blocks boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  if vision is null or periods is null or principles is null or goals is null or blocks is null then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  update core.development_plans set share_vision = vision, share_periods = periods,
    share_principles = principles, share_goals = goals, share_blocks = blocks
  where id = plan.id returning * into plan;
  return internal.tdp_plan_json(plan);
end;
$$;

-- The earlier signature leaves the blocks' sharing as it is.
create or replace function internal.set_team_development_sharing_for_actor(
  target_plan_id uuid, expected_revision bigint, vision boolean, periods boolean, principles boolean, goals boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare blocks boolean;
begin
  select share_blocks into blocks from core.development_plans where id = target_plan_id;
  return internal.set_team_development_sharing_for_actor(target_plan_id, expected_revision, vision, periods,
    principles, goals, coalesce(blocks, false));
end;
$$;

-- What the players and guardians see, as in the sharing step, with the
-- blocks when shared and the block goals among the goals.
create or replace function internal.get_shared_team_development_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare club uuid; plan core.development_plans;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select team.club_id into club from core.teams team where team.id = target_team_id;
  if club is null or not (internal.actor_has_capability(club, target_team_id, 'team.roster.view')
      or internal.actor_has_capability(club, target_team_id, 'development.manage')) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if not internal.module_allows_read(club, 'module.team_development') then return null; end if;
  select * into plan from core.development_plans candidate
  where candidate.team_id = target_team_id and candidate.plan_type = 'team' and candidate.season_starts_on is not null
    and candidate.season_ends_on >= current_date
  order by candidate.season_starts_on limit 1;
  if plan.id is null or not (plan.share_vision or plan.share_periods or plan.share_principles or plan.share_goals
      or plan.share_blocks) then
    return null;
  end if;
  return jsonb_build_object(
    'title', plan.title, 'starts_on', plan.season_starts_on, 'ends_on', plan.season_ends_on,
    'vision', case when plan.share_vision and btrim(plan.focus) <> '' then plan.focus end,
    'periods', case when plan.share_periods then coalesce((
      select jsonb_agg(jsonb_build_object('id', period.id, 'name', period.name, 'phase', period.phase,
        'starts_on', period.starts_on, 'ends_on', period.ends_on, 'focus', period.focus) order by period.starts_on)
      from core.team_development_periods period where period.plan_id = plan.id), '[]'::jsonb) end,
    'blocks', case when plan.share_blocks then coalesce((
      select jsonb_agg(jsonb_build_object('id', block.id, 'period_id', block.period_id, 'name', block.name,
        'starts_on', block.starts_on, 'ends_on', block.ends_on, 'focus', block.focus,
        'principles', internal.tdp_block_principles(block.id)) order by block.starts_on)
      from core.team_development_blocks block where block.plan_id = plan.id), '[]'::jsonb) end,
    'principles', case when plan.share_principles then coalesce((
      select jsonb_agg(jsonb_build_object('id', principle.id, 'area', principle.area, 'title', principle.title,
        'description', principle.description) order by principle.position, principle.updated_at)
      from core.team_development_principles principle where principle.plan_id = plan.id), '[]'::jsonb) end,
    -- The season's, periods' and blocks' goals; dated short-term ones stay the leaders'.
    'goals', case when plan.share_goals then coalesce((
      select jsonb_agg(jsonb_build_object('id', goal.id, 'horizon', goal.horizon, 'period_id', goal.period_id,
        'block_id', goal.block_id, 'title', goal.title, 'description', goal.description, 'state', goal.state,
        'links', internal.tdp_goal_links(goal.id, true)) order by goal.position, goal.updated_at)
      from core.team_development_goals goal
      where goal.plan_id = plan.id and goal.horizon in ('season', 'period', 'block') and goal.state <> 'dropped'), '[]'::jsonb) end
  );
end;
$$;

-- For an event's preparation, as in the sharing step, with the day's block:
-- its focus, its principles and its open goals first.
create or replace function internal.get_team_plan_suggestion_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events; plan core.development_plans; period core.team_development_periods;
  block core.team_development_blocks; day date;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into event_row from core.events where id = target_event_id;
  if event_row.id is null or event_row.owning_team_id is null
    or not internal.module_allows_read(event_row.club_id, 'module.team_development')
    or not (internal.actor_has_event_capability(event_row.id, 'training.plan')
      or internal.actor_has_event_capability(event_row.id, 'match.plan')) then
    return null;
  end if;
  day := (event_row.starts_at at time zone 'Europe/Stockholm')::date;
  select * into plan from core.development_plans candidate
  where candidate.team_id = event_row.owning_team_id and candidate.plan_type = 'team'
    and day between candidate.season_starts_on and candidate.season_ends_on
  limit 1;
  if plan.id is null then return null; end if;
  select * into period from core.team_development_periods
  where plan_id = plan.id and day between starts_on and ends_on limit 1;
  select * into block from core.team_development_blocks
  where plan_id = plan.id and day between starts_on and ends_on limit 1;
  return jsonb_build_object(
    'plan_title', plan.title,
    'period', case when period.id is not null then
      jsonb_build_object('name', period.name, 'phase', period.phase, 'focus', period.focus) end,
    'block', case when block.id is not null then
      jsonb_build_object('name', block.name, 'focus', block.focus, 'starts_on', block.starts_on,
        'ends_on', block.ends_on, 'principles', internal.tdp_block_principles(block.id)) end,
    'principles', coalesce((
      select jsonb_agg(jsonb_build_object('area', principle.area, 'title', principle.title)
        order by principle.position, principle.updated_at)
      from core.team_development_principles principle where principle.plan_id = plan.id), '[]'::jsonb),
    -- The open goals of the day's block and period, and the dated ones ahead within three weeks.
    'goals', coalesce((
      select jsonb_agg(jsonb_build_object('horizon', goal.horizon, 'title', goal.title, 'target_on', goal.target_on)
        order by case goal.horizon when 'block' then 0 when 'period' then 1 else 2 end,
          goal.target_on nulls first, goal.position)
      from core.team_development_goals goal
      where goal.plan_id = plan.id and goal.state = 'open'
        and ((goal.horizon = 'block' and goal.block_id = block.id)
          or (goal.horizon = 'period' and goal.period_id = period.id)
          or (goal.horizon = 'short' and goal.target_on between day and day + 21))), '[]'::jsonb)
  );
end;
$$;

-- Whether an open goal is due for its check-in: what it belongs to ended
-- within four weeks, and it was not checked from a week before that end.
create or replace function internal.tdp_goal_due(target_goal_id uuid, ended date)
returns boolean language sql stable security definer set search_path = '' as $$
  select ended between current_date - 28 and current_date
    and not exists (select 1 from core.team_development_checkins checkin
      where checkin.goal_id = target_goal_id and checkin.checked_on >= ended - 7)
$$;

-- For the assistant: in each team where you plan the team's development, the
-- open goals of a block, a period or a season that has just ended, and the
-- dated ones just passed, not yet checked.
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
        left join core.team_development_blocks block on block.id = goal.block_id
        left join core.team_development_periods period on period.id = goal.period_id
        where goal.plan_id = plan.id and goal.state = 'open'
          and internal.tdp_goal_due(goal.id, case goal.horizon
            when 'block' then block.ends_on
            when 'period' then period.ends_on
            when 'season' then plan.season_ends_on
            else goal.target_on end)
      ) due
      from core.development_plans plan
      where plan.plan_type = 'team' and plan.season_starts_on <= current_date
        and plan.season_ends_on >= current_date - 28
        and exists (select 1 from core.person_account_links link
          where link.profile_id = auth.uid() and link.club_id = plan.club_id and link.state = 'active')
        and internal.module_allows_write(plan.club_id, 'module.team_development')
        and internal.actor_has_capability(plan.club_id, plan.team_id, 'development.manage')
    ) due
    where due.due > 0
  ), '[]'::jsonb);
end;
$$;

create or replace function api.save_team_development_block(target_plan_id uuid, expected_revision bigint,
  target_block_id uuid, target_period_id uuid, block_name text, starts date, ends date, block_focus text,
  principle_ids uuid[]) returns jsonb language sql security invoker set search_path = '' as $$
  select internal.save_team_development_block_for_actor(target_plan_id, expected_revision, target_block_id,
    target_period_id, block_name, starts, ends, block_focus, principle_ids) $$;
create or replace function api.delete_team_development_block(target_plan_id uuid, expected_revision bigint,
  target_block_id uuid) returns jsonb language sql security invoker set search_path = '' as $$
  select internal.delete_team_development_block_for_actor(target_plan_id, expected_revision, target_block_id) $$;
create or replace function api.save_team_development_goal(target_plan_id uuid, expected_revision bigint,
  target_goal_id uuid, goal_horizon text, target_period_id uuid, target_block_id uuid, goal_title text,
  goal_description text, goal_target_on date, goal_state text) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.save_team_development_goal_for_actor(target_plan_id, expected_revision, target_goal_id, goal_horizon,
    target_period_id, target_block_id, goal_title, goal_description, goal_target_on, goal_state) $$;
create or replace function api.set_team_development_sharing(target_plan_id uuid, expected_revision bigint,
  vision boolean, periods boolean, principles boolean, goals boolean, blocks boolean) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.set_team_development_sharing_for_actor(target_plan_id, expected_revision, vision, periods,
    principles, goals, blocks) $$;

revoke all on function
  internal.tdp_block_principles(uuid),
  internal.tdp_goal_due(uuid, date),
  internal.save_team_development_block_for_actor(uuid, bigint, uuid, uuid, text, date, date, text, uuid[]),
  internal.delete_team_development_block_for_actor(uuid, bigint, uuid),
  internal.save_team_development_goal_for_actor(uuid, bigint, uuid, text, uuid, uuid, text, text, date, text),
  internal.set_team_development_sharing_for_actor(uuid, bigint, boolean, boolean, boolean, boolean, boolean),
  api.save_team_development_block(uuid, bigint, uuid, uuid, text, date, date, text, uuid[]),
  api.delete_team_development_block(uuid, bigint, uuid),
  api.save_team_development_goal(uuid, bigint, uuid, text, uuid, uuid, text, text, date, text),
  api.set_team_development_sharing(uuid, bigint, boolean, boolean, boolean, boolean, boolean)
from public, anon, authenticated;
grant execute on function
  internal.save_team_development_block_for_actor(uuid, bigint, uuid, uuid, text, date, date, text, uuid[]),
  internal.delete_team_development_block_for_actor(uuid, bigint, uuid),
  internal.save_team_development_goal_for_actor(uuid, bigint, uuid, text, uuid, uuid, text, text, date, text),
  internal.set_team_development_sharing_for_actor(uuid, bigint, boolean, boolean, boolean, boolean, boolean),
  api.save_team_development_block(uuid, bigint, uuid, uuid, text, date, date, text, uuid[]),
  api.delete_team_development_block(uuid, bigint, uuid),
  api.save_team_development_goal(uuid, bigint, uuid, text, uuid, uuid, text, text, date, text),
  api.set_team_development_sharing(uuid, bigint, boolean, boolean, boolean, boolean, boolean)
to authenticated;
notify pgrst, 'reload schema';
