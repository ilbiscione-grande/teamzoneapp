-- Team Development Plan, step 3 (decision package 11, MFD-04/12; the
-- product owner's choices 2026-10-24):
--  * Sharing: the leaders choose per part what the team's players and
--    guardians see of the plan: the vision, the periods with their focus,
--    the principles, and the season's and periods' goals. Check-ins, notes
--    and the key figures stay the leaders'. Shown in Laget for those who see
--    the team's roster (team.roster.view).
--  * Links on goals, in the modules' shared attachments (owner 'team_goal'),
--    each shown to the players or not, as on the match plan.
--  * A suggestion for an event's preparation: the period of the event's day,
--    its focus, the principles and the goals ahead, for those who prepare
--    the training (training.plan) or the match (match.plan). A suggestion
--    only: nothing is written to the event (MFD-12).

alter table core.development_plans
  add column share_vision boolean not null default false,
  add column share_periods boolean not null default false,
  add column share_principles boolean not null default false,
  add column share_goals boolean not null default false;

-- Goals get attachments too.
do $$
declare constraint_name text;
begin
  select con.conname into constraint_name from pg_constraint con
  where con.conrelid = 'core.module_attachments'::regclass and con.contype = 'c'
    and pg_get_constraintdef(con.oid) like '%owner_kind%';
  if constraint_name is not null then
    execute format('alter table core.module_attachments drop constraint %I', constraint_name);
  end if;
end $$;
alter table core.module_attachments
  add constraint module_attachments_owner_kind_check check (owner_kind in ('match_plan', 'team_goal'));

-- A goal's links: all for the leaders, the shown ones for the players.
create or replace function internal.tdp_goal_links(target_goal_id uuid, shown_only boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', link.id, 'title', link.title, 'url', link.url,
      'visible', link.visible_to_players) order by link.position, link.created_at), '[]'::jsonb)
  from core.module_attachments link
  where link.owner_kind = 'team_goal' and link.owner_id = target_goal_id and (not shown_only or link.visible_to_players)
$$;

-- As in step 2, with the sharing and each goal's links.
create or replace function internal.tdp_plan_json(plan core.development_plans)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', plan.id, 'title', plan.title, 'vision', plan.focus,
    'starts_on', plan.season_starts_on, 'ends_on', plan.season_ends_on,
    'checkin_every_days', plan.checkin_every_days,
    'sharing', jsonb_build_object('vision', plan.share_vision, 'periods', plan.share_periods,
      'principles', plan.share_principles, 'goals', plan.share_goals),
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

create or replace function internal.set_team_development_sharing_for_actor(
  target_plan_id uuid, expected_revision bigint, vision boolean, periods boolean, principles boolean, goals boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  if vision is null or periods is null or principles is null or goals is null then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  update core.development_plans set share_vision = vision, share_periods = periods,
    share_principles = principles, share_goals = goals
  where id = plan.id returning * into plan;
  return internal.tdp_plan_json(plan);
end;
$$;

-- A link on a goal (a video, an exercise, a document); at most 10 a goal.
-- Beside the plan, as a check-in: no revision.
create or replace function internal.add_team_development_goal_link_for_actor(
  target_plan_id uuid, target_goal_id uuid, link_title text, link_url text, show_players boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_checkin_plan(target_plan_id);
  if not exists (select 1 from core.team_development_goals where id = target_goal_id and plan_id = plan.id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if length(btrim(coalesce(link_title, ''))) not between 1 and 120 or show_players is null
    or coalesce(link_url, '') !~ '^https://[^[:space:]]{3,}$' or length(link_url) > 2000 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if (select count(*) from core.module_attachments where owner_kind = 'team_goal' and owner_id = target_goal_id) >= 10 then
    raise invalid_parameter_value using message = 'too_many';
  end if;
  insert into core.module_attachments (club_id, owner_kind, owner_id, kind, title, url, visible_to_players, position, created_by)
  values (plan.club_id, 'team_goal', target_goal_id, 'link', btrim(link_title), link_url, show_players,
    coalesce((select max(position) + 1 from core.module_attachments where owner_kind = 'team_goal' and owner_id = target_goal_id), 0),
    auth.uid());
  return internal.tdp_plan_json(plan);
end;
$$;

-- Shown to the players or not; show_players null removes the link.
create or replace function internal.change_team_development_goal_link_for_actor(
  target_plan_id uuid, target_link_id uuid, show_players boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans; link core.module_attachments;
begin
  plan := internal.tdp_checkin_plan(target_plan_id);
  select attachment.* into link from core.module_attachments attachment
  join core.team_development_goals goal on goal.id = attachment.owner_id and goal.plan_id = plan.id
  where attachment.id = target_link_id and attachment.owner_kind = 'team_goal';
  if link.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  if show_players is null then delete from core.module_attachments where id = link.id;
  else update core.module_attachments set visible_to_players = show_players where id = link.id; end if;
  return internal.tdp_plan_json(plan);
end;
$$;

-- What the team's players and guardians see: the shared parts of today's
-- season (else the next); null when nothing is shared or there is none.
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
  if plan.id is null or not (plan.share_vision or plan.share_periods or plan.share_principles or plan.share_goals) then
    return null;
  end if;
  return jsonb_build_object(
    'title', plan.title, 'starts_on', plan.season_starts_on, 'ends_on', plan.season_ends_on,
    'vision', case when plan.share_vision and btrim(plan.focus) <> '' then plan.focus end,
    'periods', case when plan.share_periods then coalesce((
      select jsonb_agg(jsonb_build_object('id', period.id, 'name', period.name, 'phase', period.phase,
        'starts_on', period.starts_on, 'ends_on', period.ends_on, 'focus', period.focus) order by period.starts_on)
      from core.team_development_periods period where period.plan_id = plan.id), '[]'::jsonb) end,
    'principles', case when plan.share_principles then coalesce((
      select jsonb_agg(jsonb_build_object('id', principle.id, 'area', principle.area, 'title', principle.title,
        'description', principle.description) order by principle.position, principle.updated_at)
      from core.team_development_principles principle where principle.plan_id = plan.id), '[]'::jsonb) end,
    -- The season's and periods' goals; short-term ones stay the leaders'.
    'goals', case when plan.share_goals then coalesce((
      select jsonb_agg(jsonb_build_object('id', goal.id, 'horizon', goal.horizon, 'period_id', goal.period_id,
        'title', goal.title, 'description', goal.description, 'state', goal.state,
        'links', internal.tdp_goal_links(goal.id, true)) order by goal.position, goal.updated_at)
      from core.team_development_goals goal
      where goal.plan_id = plan.id and goal.horizon in ('season', 'period') and goal.state <> 'dropped'), '[]'::jsonb) end
  );
end;
$$;

-- For an event's preparation: what the team's plan says for its day, for
-- those who prepare it; null without the module, a plan or the right.
create or replace function internal.get_team_plan_suggestion_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events; plan core.development_plans; period core.team_development_periods; day date;
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
  return jsonb_build_object(
    'plan_title', plan.title,
    'period', case when period.id is not null then
      jsonb_build_object('name', period.name, 'phase', period.phase, 'focus', period.focus) end,
    'principles', coalesce((
      select jsonb_agg(jsonb_build_object('area', principle.area, 'title', principle.title)
        order by principle.position, principle.updated_at)
      from core.team_development_principles principle where principle.plan_id = plan.id), '[]'::jsonb),
    -- The open goals of the day's period, and the short-term ones ahead within three weeks.
    'goals', coalesce((
      select jsonb_agg(jsonb_build_object('horizon', goal.horizon, 'title', goal.title, 'target_on', goal.target_on)
        order by goal.horizon, goal.target_on nulls first, goal.position)
      from core.team_development_goals goal
      where goal.plan_id = plan.id and goal.state = 'open'
        and ((goal.horizon = 'period' and goal.period_id = period.id)
          or (goal.horizon = 'short' and goal.target_on between day and day + 21))), '[]'::jsonb)
  );
end;
$$;

-- The principles' areas follow the Swedish FA's phases of the game, each
-- with the ball and its opposite without (the product owner, 2026-10-24).
-- No principle was written with the earlier areas.
do $$
declare constraint_name text;
begin
  select con.conname into constraint_name from pg_constraint con
  where con.conrelid = 'core.team_development_principles'::regclass and con.contype = 'c'
    and pg_get_constraintdef(con.oid) like '%area%';
  if constraint_name is not null then
    execute format('alter table core.team_development_principles drop constraint %I', constraint_name);
  end if;
end $$;
alter table core.team_development_principles
  add constraint team_development_principles_area_check check (area in (
    'scoring', 'preventing_scoring', 'build_up', 'preventing_build_up',
    'counter', 'regaining', 'attacking_play', 'defending'));

create or replace function internal.save_team_development_principle_for_actor(
  target_plan_id uuid, expected_revision bigint, target_principle_id uuid, principle_area text,
  principle_title text, principle_description text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_change(target_plan_id, expected_revision);
  if principle_area is null
    or principle_area not in ('scoring', 'preventing_scoring', 'build_up', 'preventing_build_up',
      'counter', 'regaining', 'attacking_play', 'defending')
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

create or replace function api.set_team_development_sharing(target_plan_id uuid, expected_revision bigint,
  vision boolean, periods boolean, principles boolean, goals boolean) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.set_team_development_sharing_for_actor(target_plan_id, expected_revision, vision, periods, principles, goals) $$;
create or replace function api.add_team_development_goal_link(target_plan_id uuid, target_goal_id uuid, link_title text,
  link_url text, show_players boolean) returns jsonb language sql security invoker set search_path = '' as $$
  select internal.add_team_development_goal_link_for_actor(target_plan_id, target_goal_id, link_title, link_url, show_players) $$;
create or replace function api.change_team_development_goal_link(target_plan_id uuid, target_link_id uuid,
  show_players boolean) returns jsonb language sql security invoker set search_path = '' as $$
  select internal.change_team_development_goal_link_for_actor(target_plan_id, target_link_id, show_players) $$;
create or replace function api.get_shared_team_development(target_team_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_shared_team_development_for_actor(target_team_id) $$;
create or replace function api.get_team_plan_suggestion(target_event_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_team_plan_suggestion_for_actor(target_event_id) $$;

revoke all on function
  internal.tdp_goal_links(uuid, boolean),
  internal.set_team_development_sharing_for_actor(uuid, bigint, boolean, boolean, boolean, boolean),
  internal.add_team_development_goal_link_for_actor(uuid, uuid, text, text, boolean),
  internal.change_team_development_goal_link_for_actor(uuid, uuid, boolean),
  internal.get_shared_team_development_for_actor(uuid),
  internal.get_team_plan_suggestion_for_actor(uuid),
  api.set_team_development_sharing(uuid, bigint, boolean, boolean, boolean, boolean),
  api.add_team_development_goal_link(uuid, uuid, text, text, boolean),
  api.change_team_development_goal_link(uuid, uuid, boolean),
  api.get_shared_team_development(uuid),
  api.get_team_plan_suggestion(uuid)
from public, anon, authenticated;
grant execute on function
  internal.set_team_development_sharing_for_actor(uuid, bigint, boolean, boolean, boolean, boolean),
  internal.add_team_development_goal_link_for_actor(uuid, uuid, text, text, boolean),
  internal.change_team_development_goal_link_for_actor(uuid, uuid, boolean),
  internal.get_shared_team_development_for_actor(uuid),
  internal.get_team_plan_suggestion_for_actor(uuid),
  api.set_team_development_sharing(uuid, bigint, boolean, boolean, boolean, boolean),
  api.add_team_development_goal_link(uuid, uuid, text, text, boolean),
  api.change_team_development_goal_link(uuid, uuid, boolean),
  api.get_shared_team_development(uuid),
  api.get_team_plan_suggestion(uuid)
to authenticated;
notify pgrst, 'reload schema';
