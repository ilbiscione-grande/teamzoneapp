-- Säsongsplanering (the module earlier named Team Development Plan, renamed
-- by the product owner 2026-11-22): a third row on the season's timeline
-- with the stretches that affect the planning, beside the periods and the
-- blocks: holidays (Swedish and others), school breaks (sportlov, påsklov,
-- höstlov ...), vacations and other days off.
--  * Per season, kept by the leaders who edit the plan. The app suggests
--    holidays and the usual school breaks; every row can be changed or
--    removed.
--  * They may overlap each other and the periods and blocks; a season
--    changed later only hides the rows outside it.
--  * Not shared with the players.

-- The module's new name and description in the catalogue.
update core.module_catalog set title = 'Säsongsplanering',
  description = 'Säsongens perioder och block, lov och högtider, och lagets utvecklingsplan med mål och spelidé'
where key = 'module.team_development';

create table core.team_development_calendar_periods (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  plan_id uuid not null,
  kind text not null check (kind in ('holiday', 'school_break', 'vacation', 'other')),
  name text not null check (length(btrim(name)) between 1 and 80),
  starts_on date not null,
  ends_on date not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references core.profiles(id) on delete set null,
  check (ends_on >= starts_on and ends_on - starts_on <= 120),
  foreign key (plan_id, club_id) references core.development_plans(id, club_id) on delete cascade
);
create index team_development_calendar_periods_plan
  on core.team_development_calendar_periods (plan_id, club_id, starts_on);
create index team_development_calendar_periods_updated_by
  on core.team_development_calendar_periods (updated_by);

alter table core.team_development_calendar_periods enable row level security;
revoke all on core.team_development_calendar_periods from public, anon, authenticated;
create policy team_development_calendar_periods_no_direct_access on core.team_development_calendar_periods
  for all to authenticated using (false) with check (false);

-- The plan as in 20270128090000, with the calendar periods in the season.
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
    'calendar_periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', item.id, 'kind', item.kind, 'name', item.name,
        'starts_on', item.starts_on, 'ends_on', item.ends_on
      ) order by item.starts_on, item.ends_on desc, item.name)
      from core.team_development_calendar_periods item where item.plan_id = plan.id
        and item.starts_on <= plan.season_ends_on and item.ends_on >= plan.season_starts_on), '[]'::jsonb),
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
        'id', kpi.id, 'title', kpi.title, 'unit', kpi.unit, 'target', kpi.target, 'higher_is_better', kpi.higher_is_better,
        'source', kpi.source
      ) order by kpi.position, kpi.updated_at)
      from core.team_development_kpis kpi where kpi.plan_id = plan.id), '[]'::jsonb),
    'checkins', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', checkin.id, 'goal_id', checkin.goal_id, 'kpi_id', checkin.kpi_id, 'checked_on', checkin.checked_on,
        'event_id', checkin.event_id,
        'status', checkin.status, 'value', checkin.value, 'note', checkin.note,
        'created_at', checkin.created_at, 'created_by', internal.tdp_name(checkin.created_by)
      ) order by checkin.checked_on desc, checkin.created_at desc)
      from (select * from core.team_development_checkins latest where latest.plan_id = plan.id
        order by latest.checked_on desc, latest.created_at desc limit 500) checkin), '[]'::jsonb),
    'matches', internal.tdp_matches(plan),
    'match_buttons', coalesce((select buttons from core.team_match_buttons where team_id = plan.team_id), '[]'::jsonb)
  )
$$;

-- One stretch checked: a kind, a name, at most 121 days, touching the season.
create or replace function internal.tdp_check_calendar_period(
  plan core.development_plans, item_kind text, item_name text, starts date, ends date
) returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(item_kind, '') not in ('holiday', 'school_break', 'vacation', 'other')
    or length(btrim(coalesce(item_name, ''))) not between 1 and 80
    or starts is null or ends is null or ends < starts or ends - starts > 120 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if starts > plan.season_ends_on or ends < plan.season_starts_on then
    raise invalid_parameter_value using message = 'outside_season';
  end if;
end;
$$;

-- A holiday, break or vacation laid out or changed; null id adds one.
create or replace function internal.save_team_development_calendar_period_for_actor(
  target_plan_id uuid, expected_revision bigint, target_item_id uuid, item_kind text, item_name text,
  starts date, ends date
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans; item uuid;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  perform internal.tdp_check_calendar_period(plan, item_kind, item_name, starts, ends);
  if target_item_id is null then
    if (select count(*) from core.team_development_calendar_periods where plan_id = plan.id) >= 150 then
      raise invalid_parameter_value using message = 'too_many';
    end if;
    insert into core.team_development_calendar_periods (club_id, plan_id, kind, name, starts_on, ends_on, updated_by)
    values (plan.club_id, plan.id, item_kind, btrim(item_name), starts, ends, auth.uid());
  else
    update core.team_development_calendar_periods set kind = item_kind, name = btrim(item_name),
      starts_on = starts, ends_on = ends, updated_at = now(), updated_by = auth.uid()
    where id = target_item_id and plan_id = plan.id
    returning id into item;
    if item is null then raise insufficient_privilege using message = 'not_found'; end if;
  end if;
  return internal.tdp_plan_json(plan);
end;
$$;

-- Several at once (the suggested holidays and breaks): each as
-- {kind, name, starts_on, ends_on}; one already there with the same kind,
-- name and first day is left as it is.
create or replace function internal.add_team_development_calendar_periods_for_actor(
  target_plan_id uuid, expected_revision bigint, items jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans; entry jsonb; starts date; ends date;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) not between 1 and 100 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  for entry in select value from jsonb_array_elements(items) loop
    begin
      starts := (entry->>'starts_on')::date;
      ends := (entry->>'ends_on')::date;
    exception when others then
      raise invalid_parameter_value using message = 'invalid_input';
    end;
    perform internal.tdp_check_calendar_period(plan, entry->>'kind', entry->>'name', starts, ends);
    if not exists (select 1 from core.team_development_calendar_periods existing
        where existing.plan_id = plan.id and existing.kind = entry->>'kind'
          and existing.name = btrim(entry->>'name') and existing.starts_on = starts) then
      insert into core.team_development_calendar_periods (club_id, plan_id, kind, name, starts_on, ends_on, updated_by)
      values (plan.club_id, plan.id, entry->>'kind', btrim(entry->>'name'), starts, ends, auth.uid());
    end if;
  end loop;
  if (select count(*) from core.team_development_calendar_periods where plan_id = plan.id) > 150 then
    raise invalid_parameter_value using message = 'too_many';
  end if;
  return internal.tdp_plan_json(plan);
end;
$$;

create or replace function internal.delete_team_development_calendar_period_for_actor(
  target_plan_id uuid, expected_revision bigint, target_item_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  delete from core.team_development_calendar_periods where id = target_item_id and plan_id = plan.id;
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.tdp_plan_json(plan);
end;
$$;

create or replace function api.save_team_development_calendar_period(target_plan_id uuid, expected_revision bigint,
  target_item_id uuid, item_kind text, item_name text, starts date, ends date) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.save_team_development_calendar_period_for_actor(target_plan_id, expected_revision, target_item_id,
    item_kind, item_name, starts, ends) $$;
create or replace function api.add_team_development_calendar_periods(target_plan_id uuid, expected_revision bigint,
  items jsonb) returns jsonb language sql security invoker set search_path = '' as $$
  select internal.add_team_development_calendar_periods_for_actor(target_plan_id, expected_revision, items) $$;
create or replace function api.delete_team_development_calendar_period(target_plan_id uuid, expected_revision bigint,
  target_item_id uuid) returns jsonb language sql security invoker set search_path = '' as $$
  select internal.delete_team_development_calendar_period_for_actor(target_plan_id, expected_revision, target_item_id) $$;

revoke all on function
  internal.tdp_check_calendar_period(core.development_plans, text, text, date, date),
  internal.save_team_development_calendar_period_for_actor(uuid, bigint, uuid, text, text, date, date),
  internal.add_team_development_calendar_periods_for_actor(uuid, bigint, jsonb),
  internal.delete_team_development_calendar_period_for_actor(uuid, bigint, uuid),
  api.save_team_development_calendar_period(uuid, bigint, uuid, text, text, date, date),
  api.add_team_development_calendar_periods(uuid, bigint, jsonb),
  api.delete_team_development_calendar_period(uuid, bigint, uuid)
from public, anon, authenticated;
grant execute on function
  internal.save_team_development_calendar_period_for_actor(uuid, bigint, uuid, text, text, date, date),
  internal.add_team_development_calendar_periods_for_actor(uuid, bigint, jsonb),
  internal.delete_team_development_calendar_period_for_actor(uuid, bigint, uuid),
  api.save_team_development_calendar_period(uuid, bigint, uuid, text, text, date, date),
  api.add_team_development_calendar_periods(uuid, bigint, jsonb),
  api.delete_team_development_calendar_period(uuid, bigint, uuid)
to authenticated;
notify pgrst, 'reload schema';
