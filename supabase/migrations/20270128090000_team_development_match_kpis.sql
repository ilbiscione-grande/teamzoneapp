-- Team Development Plan, new design step 6 (2026-11-02): key figures from
-- the matches (decision 15).
--
-- A key figure can take its values from the team's matches instead of by
-- hand: a source names what is counted (goals for and against, points, clean
-- sheets, shots, shots on target, shots against, corners, saves, yellow
-- cards, or one of the team's own Live buttons as button:<id>). The plan
-- carries the season's played matches with what they add up to, so the app
-- shows a value per match. The score counts every played match, also one
-- registered with its result only; what is counted from the events only
-- matches whose events were registered. A value can be set by hand for a
-- match (a check-in tied to the match, replacing the counted value), and
-- values without a match are still added by hand as before.

alter table core.team_development_kpis add column source text
  check (source is null or source in ('goals_for', 'goals_against', 'points', 'clean_sheet', 'shots',
    'shots_on_target', 'shots_against', 'corners', 'saves', 'yellow_cards')
    or source ~ '^button:[A-Za-z0-9_-]{1,64}$');

alter table core.team_development_checkins add column event_id uuid references core.events(id) on delete cascade;
alter table core.team_development_checkins add constraint team_development_checkins_event_kpi
  check (event_id is null or kpi_id is not null);
create unique index team_development_checkins_kpi_event on core.team_development_checkins (kpi_id, event_id)
  where event_id is not null;
create index team_development_checkins_event on core.team_development_checkins (event_id) where event_id is not null;

-- The season's played matches of the plan's team, oldest first, with their
-- score and, when their events were registered, what the events add up to.
create or replace function internal.tdp_matches(plan core.development_plans)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'event_id', played.id, 'played_on', played.played_on, 'title', played.title,
      'registered', played.registered, 'metrics', played.metrics, 'buttons', played.buttons
    ) order by played.starts_at), '[]'::jsonb)
  from (
    select event_row.id, event_row.starts_at, event_row.title,
      (event_row.starts_at at time zone event_row.timezone)::date played_on,
      counted.registered,
      jsonb_build_object(
        'goals_for', coalesce(projection.score_us, 0),
        'goals_against', coalesce(projection.score_opponent, 0),
        'points', case when coalesce(projection.score_us, 0) > coalesce(projection.score_opponent, 0) then 3
          when coalesce(projection.score_us, 0) = coalesce(projection.score_opponent, 0) then 1 else 0 end,
        'clean_sheet', case when coalesce(projection.score_opponent, 0) = 0 then 1 else 0 end
      ) || case when counted.registered then jsonb_build_object(
        'shots', counted.shots, 'shots_on_target', counted.on_target, 'shots_against', counted.shots_against,
        'corners', counted.corners, 'saves', counted.saves, 'yellow_cards', counted.yellow_cards)
        else '{}'::jsonb end metrics,
      case when counted.registered then counted.buttons else '{}'::jsonb end buttons
    from core.events event_row
    join core.match_workspaces workspace on workspace.event_id = event_row.id and workspace.state = 'completed'
    left join core.match_projections projection on projection.event_id = event_row.id
    cross join lateral (
      select
        coalesce(bool_or(fact.fact_type in ('goal', 'shot', 'penalty', 'card', 'corner', 'free_kick', 'save',
          'substitution', 'kpi')), false) registered,
        count(*) filter (where ours and (fact.fact_type in ('shot', 'penalty')
          or (fact.fact_type = 'goal' and coalesce(fact.detail->>'own_goal', '') <> 'true')))::int shots,
        count(*) filter (where ours and ((fact.fact_type = 'shot' and fact.detail->>'result' in ('on_target', 'scored'))
          or (fact.fact_type = 'goal' and coalesce(fact.detail->>'own_goal', '') <> 'true')
          or (fact.fact_type = 'penalty' and coalesce(fact.detail->>'result', 'scored') in ('scored', 'saved'))))::int on_target,
        count(*) filter (where not ours and (fact.fact_type in ('shot', 'penalty')
          or (fact.fact_type = 'goal' and coalesce(fact.detail->>'own_goal', '') <> 'true')))::int shots_against,
        count(*) filter (where ours and fact.fact_type = 'corner')::int corners,
        count(*) filter (where ours and fact.fact_type = 'save')::int saves,
        count(*) filter (where ours and fact.fact_type = 'card'
          and (fact.detail->>'color' = 'yellow' or fact.detail->>'second_yellow' = 'true'))::int yellow_cards,
        coalesce((select jsonb_object_agg(tap.button_id, tap.taps) from (
          select button.detail->>'button_id' button_id, count(*)::int taps from core.match_facts button
          where button.event_id = event_row.id and button.state = 'active' and button.fact_type = 'kpi'
            and button.detail->>'button_id' is not null
          group by button.detail->>'button_id') tap), '{}'::jsonb) buttons
      from core.match_facts fact
      cross join lateral (select coalesce(fact.side, 'us') = 'us' ours) side
      where fact.event_id = event_row.id and fact.state = 'active'
    ) counted
    where event_row.owning_team_id = plan.team_id and event_row.club_id = plan.club_id
      and event_row.event_type = 'match' and event_row.archived_at is null and event_row.state <> 'cancelled'
      and (event_row.starts_at at time zone event_row.timezone)::date between plan.season_starts_on and plan.season_ends_on
  ) played
$$;

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

-- A key figure with its source (null: values by hand); at most 12.
create or replace function internal.save_team_development_kpi_for_actor(
  target_plan_id uuid, expected_revision bigint, target_kpi_id uuid, kpi_title text, kpi_unit text,
  kpi_target numeric, higher_better boolean, kpi_source text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans; saved jsonb;
begin
  saved := internal.save_team_development_kpi_for_actor(target_plan_id, expected_revision, target_kpi_id, kpi_title,
    kpi_unit, kpi_target, higher_better);
  select * into plan from core.development_plans where id = target_plan_id;
  update core.team_development_kpis set source = nullif(btrim(coalesce(kpi_source, '')), '')
  where plan_id = plan.id
    and id = coalesce(target_kpi_id, (select kpi.id from core.team_development_kpis kpi where kpi.plan_id = plan.id
      order by kpi.position desc limit 1));
  return internal.tdp_plan_json(plan);
end;
$$;

-- A key figure's value for one of the season's matches, set by hand: it
-- replaces the counted value (or an earlier one set for the match). No
-- value removes it, and the counted value shows again.
create or replace function internal.set_team_development_kpi_match_value_for_actor(
  target_plan_id uuid, target_kpi_id uuid, target_event_id uuid, kpi_value numeric, value_note text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans; played date;
begin
  plan := internal.tdp_checkin_plan(target_plan_id);
  if target_kpi_id is null or target_event_id is null or length(coalesce(value_note, '')) > 2000
    or (kpi_value is not null and kpi_value not between -1000000 and 1000000) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if not exists (select 1 from core.team_development_kpis where id = target_kpi_id and plan_id = plan.id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select (match.value->>'played_on')::date into played
  from jsonb_array_elements(internal.tdp_matches(plan)) match where match.value->>'event_id' = target_event_id::text;
  if played is null then raise invalid_parameter_value using message = 'not_a_match'; end if;
  delete from core.team_development_checkins where kpi_id = target_kpi_id and event_id = target_event_id;
  if kpi_value is not null then
    if (select count(*) from core.team_development_checkins where plan_id = plan.id) >= 2000 then
      raise invalid_parameter_value using message = 'too_many';
    end if;
    insert into core.team_development_checkins (club_id, plan_id, kpi_id, event_id, checked_on, value, note, created_by)
    values (plan.club_id, plan.id, target_kpi_id, target_event_id, played, kpi_value, btrim(coalesce(value_note, '')), auth.uid());
  end if;
  return internal.tdp_plan_json(plan);
end;
$$;

create or replace function api.save_team_development_kpi(target_plan_id uuid, expected_revision bigint, target_kpi_id uuid,
  kpi_title text, kpi_unit text, kpi_target numeric, higher_better boolean, kpi_source text) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.save_team_development_kpi_for_actor(target_plan_id, expected_revision, target_kpi_id, kpi_title,
    kpi_unit, kpi_target, higher_better, kpi_source) $$;
create or replace function api.set_team_development_kpi_match_value(target_plan_id uuid, target_kpi_id uuid,
  target_event_id uuid, kpi_value numeric, value_note text) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.set_team_development_kpi_match_value_for_actor(target_plan_id, target_kpi_id, target_event_id,
    kpi_value, value_note) $$;

revoke all on function internal.tdp_matches(core.development_plans),
  internal.save_team_development_kpi_for_actor(uuid, bigint, uuid, text, text, numeric, boolean, text),
  internal.set_team_development_kpi_match_value_for_actor(uuid, uuid, uuid, numeric, text),
  api.save_team_development_kpi(uuid, bigint, uuid, text, text, numeric, boolean, text),
  api.set_team_development_kpi_match_value(uuid, uuid, uuid, numeric, text) from public, anon;
revoke all on function internal.tdp_matches(core.development_plans) from authenticated;
grant execute on function
  internal.save_team_development_kpi_for_actor(uuid, bigint, uuid, text, text, numeric, boolean, text),
  internal.set_team_development_kpi_match_value_for_actor(uuid, uuid, uuid, numeric, text),
  api.save_team_development_kpi(uuid, bigint, uuid, text, text, numeric, boolean, text),
  api.set_team_development_kpi_match_value(uuid, uuid, uuid, numeric, text) to authenticated;

notify pgrst, 'reload schema';
