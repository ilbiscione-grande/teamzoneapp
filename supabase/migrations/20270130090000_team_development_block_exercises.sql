-- Team Development Plan, new design step 7 (2026-11-02): exercise
-- suggestions for a block (decision 18).
--
-- A block suggests exercises from the club's and TeamZone's libraries
-- (Tacticsboard's shared exercises) that train its principles: the
-- exercise's phase of the game is the area of one of the block's
-- principles. The leaders can also choose exercises for the block
-- themselves, from the library or written as their own. When a session is
-- prepared, in the Training module or on the event page, the suggestion
-- carries the day's block's exercises in the form the session takes them
-- in (training_pass_json), so one tap puts one in the session.

create table core.team_development_block_exercises (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  block_id uuid not null references core.team_development_blocks(id) on delete cascade,
  shared_item_id uuid references core.tactics_shared_items(id) on delete cascade,
  title text not null default '' check (length(title) <= 120),
  description text not null default '' check (length(description) <= 2000),
  position integer not null default 0,
  created_by uuid references core.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  -- From the library, or written as one's own with a title.
  check ((shared_item_id is not null) or length(btrim(title)) >= 2)
);
create index team_development_block_exercises_block on core.team_development_block_exercises (block_id, position);
create index team_development_block_exercises_item on core.team_development_block_exercises (shared_item_id)
  where shared_item_id is not null;
create index team_development_block_exercises_created_by on core.team_development_block_exercises (created_by);
create unique index team_development_block_exercises_once on core.team_development_block_exercises (block_id, shared_item_id)
  where shared_item_id is not null;
alter table core.team_development_block_exercises enable row level security;
revoke all on core.team_development_block_exercises from public, anon, authenticated;
create policy team_development_block_exercises_no_direct_access on core.team_development_block_exercises
  for all to authenticated using (false) with check (false);

-- A block's exercises, each as the session takes it in: chosen (the
-- library's that the reader sees, and the leaders' own), then up to six of
-- the club's and TeamZone's library that train the block's principles.
create or replace function internal.tdp_block_exercises(target_block_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with block as (
    select block.id, block.club_id from core.team_development_blocks block where block.id = target_block_id
  ), areas as (
    select distinct principle.area from core.team_development_block_principles chosen
    join core.team_development_principles principle on principle.id = chosen.principle_id
    where chosen.block_id = target_block_id
  )
  select jsonb_build_object(
    'chosen', coalesce((
      select jsonb_agg(jsonb_build_object('id', exercise.id,
          'pass', case when item.id is not null
            then internal.training_pass_from_shared(item, case when item.club_id is null then 'teamzone' else 'club' end)
            else internal.training_pass_json('own', exercise.id, 'exercise', exercise.title,
              jsonb_build_object('organisation', exercise.description), '{"boards":[]}'::jsonb, null, exercise.created_at) end)
        order by exercise.position, exercise.created_at)
      from core.team_development_block_exercises exercise
      left join core.tactics_shared_items item on item.id = exercise.shared_item_id
      where exercise.block_id = target_block_id
        and (exercise.shared_item_id is null or (item.id is not null and internal.tactics_shared_visible(item)))), '[]'::jsonb),
    'matched', coalesce((
      select jsonb_agg(internal.training_pass_from_shared(hit, case when hit.club_id is null then 'teamzone' else 'club' end)
        order by hit.club_id is null, hit.updated_at desc)
      from (
        select item.* from core.tactics_shared_items item, block
        where item.kind = 'exercise' and internal.tactics_shared_visible(item)
          and item.details->>'phase' in (select area from areas)
          and (item.club_id is null or item.club_id = block.club_id
            or exists (select 1 from core.tactics_club_picks pick
              where pick.club_id = block.club_id and pick.shared_item_id = item.id))
          and not exists (select 1 from core.team_development_block_exercises chosen
            where chosen.block_id = target_block_id and chosen.shared_item_id = item.id)
        order by item.club_id is null, item.updated_at desc
        limit 6
      ) hit), '[]'::jsonb)
  )
$$;

-- The block of a plan, for the one who reads the plan.
create or replace function internal.tdp_block_of(target_plan_id uuid, target_block_id uuid)
returns core.team_development_blocks language plpgsql stable security definer set search_path = '' as $$
declare plan core.development_plans; block core.team_development_blocks;
begin
  plan := internal.tdp_plan(target_plan_id);
  select * into block from core.team_development_blocks where id = target_block_id and plan_id = plan.id;
  if block.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  return block;
end;
$$;

create or replace function internal.get_team_development_block_exercises_for_actor(target_plan_id uuid, target_block_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare block core.team_development_blocks;
begin
  block := internal.tdp_block_of(target_plan_id, target_block_id);
  return internal.tdp_block_exercises(block.id);
end;
$$;

-- Chooses an exercise for the block: one of the library's the leader sees,
-- or their own; at most twelve per block. No revision: an exercise is added
-- beside the plan, as a check-in.
create or replace function internal.add_team_development_block_exercise_for_actor(
  target_plan_id uuid, target_block_id uuid, target_shared_item_id uuid, own_title text, own_description text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans; block core.team_development_blocks; item core.tactics_shared_items;
begin
  plan := internal.tdp_checkin_plan(target_plan_id);
  block := internal.tdp_block_of(plan.id, target_block_id);
  if target_shared_item_id is null and length(btrim(coalesce(own_title, ''))) not between 2 and 120
    or length(coalesce(own_description, '')) > 2000 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if target_shared_item_id is not null then
    select * into item from core.tactics_shared_items where id = target_shared_item_id;
    if item.id is null or item.kind not in ('exercise', 'plan') or not internal.tactics_shared_visible(item) then
      raise insufficient_privilege using message = 'not_found';
    end if;
  end if;
  if (select count(*) from core.team_development_block_exercises where block_id = block.id) >= 12 then
    raise invalid_parameter_value using message = 'too_many';
  end if;
  insert into core.team_development_block_exercises (club_id, block_id, shared_item_id, title, description, position, created_by)
  values (plan.club_id, block.id, target_shared_item_id,
    case when target_shared_item_id is null then btrim(own_title) else '' end,
    case when target_shared_item_id is null then btrim(coalesce(own_description, '')) else '' end,
    coalesce((select max(position) + 1 from core.team_development_block_exercises where block_id = block.id), 0), auth.uid())
  on conflict (block_id, shared_item_id) where shared_item_id is not null do nothing;
  return internal.tdp_block_exercises(block.id);
end;
$$;

create or replace function internal.delete_team_development_block_exercise_for_actor(
  target_plan_id uuid, target_exercise_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans; removed core.team_development_block_exercises;
begin
  plan := internal.tdp_checkin_plan(target_plan_id);
  delete from core.team_development_block_exercises exercise
  using core.team_development_blocks block
  where exercise.id = target_exercise_id and block.id = exercise.block_id and block.plan_id = plan.id
  returning exercise.* into removed;
  if removed.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.tdp_block_exercises(removed.block_id);
end;
$$;

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
    -- The block's exercises: those the leaders chose, then the library's
    -- that train its principles.
    'exercises', case when block.id is not null then internal.tdp_block_exercises(block.id) end,
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

create or replace function api.get_team_development_block_exercises(target_plan_id uuid, target_block_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select internal.get_team_development_block_exercises_for_actor(target_plan_id, target_block_id) $$;
create or replace function api.add_team_development_block_exercise(target_plan_id uuid, target_block_id uuid,
  target_shared_item_id uuid, own_title text, own_description text) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.add_team_development_block_exercise_for_actor(target_plan_id, target_block_id, target_shared_item_id,
    own_title, own_description) $$;
create or replace function api.delete_team_development_block_exercise(target_plan_id uuid, target_exercise_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.delete_team_development_block_exercise_for_actor(target_plan_id, target_exercise_id) $$;

revoke all on function
  internal.tdp_block_exercises(uuid),
  internal.tdp_block_of(uuid, uuid),
  internal.get_team_development_block_exercises_for_actor(uuid, uuid),
  internal.add_team_development_block_exercise_for_actor(uuid, uuid, uuid, text, text),
  internal.delete_team_development_block_exercise_for_actor(uuid, uuid),
  api.get_team_development_block_exercises(uuid, uuid),
  api.add_team_development_block_exercise(uuid, uuid, uuid, text, text),
  api.delete_team_development_block_exercise(uuid, uuid)
from public, anon, authenticated;
grant execute on function
  internal.get_team_development_block_exercises_for_actor(uuid, uuid),
  internal.add_team_development_block_exercise_for_actor(uuid, uuid, uuid, text, text),
  internal.delete_team_development_block_exercise_for_actor(uuid, uuid),
  api.get_team_development_block_exercises(uuid, uuid),
  api.add_team_development_block_exercise(uuid, uuid, uuid, text, text),
  api.delete_team_development_block_exercise(uuid, uuid)
to authenticated;
notify pgrst, 'reload schema';
