-- Training module, step 3 (decision package 11, MFD-08): the leaders'
-- evaluation after the session. How the session went (1–5), whether its
-- goal was reached, each exercise as it went (good, fair, poor), what worked,
-- what to do differently and what to take to the next session; beside it the
-- attendance against the callups. One per training, on the revision read,
-- after the training has started, and only the leaders' (training.plan).
-- The players' self-assessment (ACD-07) stays off until PAR-PRIV-04 decides
-- its age, visibility, guardians' insight, opt-out and retention.

create table core.training_evaluations (
  event_id uuid primary key references core.events(id) on delete cascade,
  club_id uuid not null references core.clubs(id),
  team_id uuid not null,
  rating smallint check (rating between 1 and 5),
  goal_reached text check (goal_reached in ('yes', 'partly', 'no')),
  went_well text not null default '' check (length(went_well) <= 2000),
  do_differently text not null default '' check (length(do_differently) <= 2000),
  next_time text not null default '' check (length(next_time) <= 2000),
  -- Each exercise as it went: the session's blocks as they were, by title.
  blocks jsonb not null default '[]'::jsonb check (jsonb_typeof(blocks) = 'array'),
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references core.profiles(id) on delete set null
);
create index training_evaluations_team on core.training_evaluations (team_id);
create index training_evaluations_updated_by on core.training_evaluations (updated_by);

alter table core.training_evaluations enable row level security;
revoke all on core.training_evaluations from public, anon, authenticated;
create policy training_evaluations_no_direct_access on core.training_evaluations
  for all to authenticated using (false) with check (false);

-- The evaluation with the attendance: called (callups not cancelled),
-- accepted, attended (present, late or partly) and recorded.
create or replace function internal.training_evaluation_json(event_row core.events, can_edit boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'event_id', event_row.id, 'can_edit', can_edit,
    'started', event_row.starts_at <= now(),
    'revision', coalesce(evaluation.revision, 0),
    'rating', evaluation.rating, 'goal_reached', evaluation.goal_reached,
    'went_well', coalesce(evaluation.went_well, ''), 'do_differently', coalesce(evaluation.do_differently, ''),
    'next_time', coalesce(evaluation.next_time, ''), 'blocks', coalesce(evaluation.blocks, '[]'::jsonb),
    'updated_at', evaluation.updated_at,
    'updated_by', (select nullif(btrim(profile.display_name), '') from core.profiles profile where profile.id = evaluation.updated_by),
    'attendance', jsonb_build_object(
      'called', (select count(*) from core.callups callup where callup.event_id = event_row.id and callup.state <> 'cancelled'),
      'accepted', (select count(*) from core.callups callup where callup.event_id = event_row.id and callup.state = 'accepted'),
      'attended', (select count(*) from core.attendance_facts fact where fact.event_id = event_row.id
        and fact.status in ('present', 'late', 'partial')),
      'recorded', (select count(*) from core.attendance_facts fact where fact.event_id = event_row.id))
  )
  from (select 1) one left join core.training_evaluations evaluation on evaluation.event_id = event_row.id
$$;

-- The evaluation, for those who prepare the training.
create or replace function internal.get_training_evaluation_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events;
begin
  event_row := internal.training_session_event(target_event_id);
  if not internal.actor_has_event_capability(event_row.id, 'training.plan') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return internal.training_evaluation_json(event_row, internal.training_session_can_edit(event_row));
end;
$$;

-- Saves the evaluation on the revision read (0 for a new one), once the
-- training has started.
create or replace function internal.save_training_evaluation_for_actor(
  target_event_id uuid, expected_revision bigint, session_rating integer, reached text, well text, differently text,
  next_session text, block_ratings jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare event_row core.events; current_revision bigint; block jsonb;
begin
  event_row := internal.training_session_event(target_event_id);
  if not internal.training_session_can_edit(event_row) then raise insufficient_privilege using message = 'not_allowed'; end if;
  if event_row.starts_at > now() then raise invalid_parameter_value using message = 'not_started'; end if;
  if (session_rating is not null and session_rating not between 1 and 5)
    or (reached is not null and reached not in ('yes', 'partly', 'no'))
    or length(coalesce(well, '')) > 2000 or length(coalesce(differently, '')) > 2000 or length(coalesce(next_session, '')) > 2000
    or jsonb_typeof(coalesce(block_ratings, 'null'::jsonb)) <> 'array' or jsonb_array_length(block_ratings) > 30 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  for block in select value from jsonb_array_elements(block_ratings) loop
    if jsonb_typeof(block) <> 'object' or length(btrim(coalesce(block->>'title', ''))) not between 1 and 120
      or (block->>'rating' is not null and block->>'rating' not in ('good', 'fair', 'poor'))
      or length(coalesce(block->>'note', '')) > 500 then
      raise invalid_parameter_value using message = 'invalid_input';
    end if;
  end loop;
  perform pg_advisory_xact_lock(hashtextextended(event_row.id::text, 3));
  select revision into current_revision from core.training_evaluations where event_id = event_row.id for update;
  if coalesce(current_revision, 0) <> coalesce(expected_revision, -1) then
    raise serialization_failure using message = 'stale_revision';
  end if;
  insert into core.training_evaluations (event_id, club_id, team_id, rating, goal_reached, went_well, do_differently,
    next_time, blocks, updated_by)
  values (event_row.id, event_row.club_id, event_row.owning_team_id, session_rating, reached, btrim(coalesce(well, '')),
    btrim(coalesce(differently, '')), btrim(coalesce(next_session, '')), block_ratings, auth.uid())
  on conflict (event_id) do update set rating = excluded.rating, goal_reached = excluded.goal_reached,
    went_well = excluded.went_well, do_differently = excluded.do_differently, next_time = excluded.next_time,
    blocks = excluded.blocks, revision = core.training_evaluations.revision + 1, updated_at = now(),
    updated_by = excluded.updated_by;
  return internal.training_evaluation_json(event_row, true);
end;
$$;

-- As in step 1, with whether each training is evaluated.
create or replace function internal.list_module_trainings_for_actor(target_team_id uuid, from_time timestamptz, to_time timestamptz)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare club uuid;
begin
  select team.club_id into club from core.teams team where team.id = target_team_id;
  if club is null or auth.uid() is null or not internal.actor_has_capability(club, target_team_id, 'training.plan')
    or not internal.module_allows_read(club, 'module.training') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if from_time is null or to_time is null or to_time <= from_time or to_time - from_time > interval '400 days' then
    raise invalid_parameter_value using message = 'invalid_period';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'event_id', event_row.id, 'title', event_row.title, 'starts_at', event_row.starts_at, 'ends_at', event_row.ends_at,
      'state', event_row.state,
      'theme', coalesce(nullif(session.theme, ''), event_row.training_theme),
      'session', case when session.event_id is null then 'none' when session.published then 'published' else 'draft' end,
      'minutes', (select coalesce(sum(block.minutes), 0) from core.training_blocks block where block.event_id = event_row.id),
      'blocks', (select count(*) from core.training_blocks block where block.event_id = event_row.id),
      'evaluated', exists (select 1 from core.training_evaluations evaluation where evaluation.event_id = event_row.id),
      'rating', (select evaluation.rating from core.training_evaluations evaluation where evaluation.event_id = event_row.id)
    ) order by event_row.starts_at)
    from core.events event_row
    left join core.training_sessions session on session.event_id = event_row.id
    where event_row.owning_team_id = target_team_id and event_row.event_type = 'training' and event_row.archived_at is null
      and event_row.starts_at >= from_time and event_row.starts_at < to_time
  ), '[]'::jsonb);
end;
$$;

create or replace function api.get_training_evaluation(target_event_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_training_evaluation_for_actor(target_event_id) $$;
create or replace function api.save_training_evaluation(target_event_id uuid, expected_revision bigint, session_rating integer,
  reached text, well text, differently text, next_session text, block_ratings jsonb) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.save_training_evaluation_for_actor(target_event_id, expected_revision, session_rating, reached, well,
    differently, next_session, block_ratings) $$;

revoke all on function
  internal.training_evaluation_json(core.events, boolean), internal.get_training_evaluation_for_actor(uuid),
  internal.save_training_evaluation_for_actor(uuid, bigint, integer, text, text, text, text, jsonb),
  api.get_training_evaluation(uuid), api.save_training_evaluation(uuid, bigint, integer, text, text, text, text, jsonb)
from public, anon, authenticated;
grant execute on function
  internal.get_training_evaluation_for_actor(uuid),
  internal.save_training_evaluation_for_actor(uuid, bigint, integer, text, text, text, text, jsonb),
  api.get_training_evaluation(uuid), api.save_training_evaluation(uuid, bigint, integer, text, text, text, text, jsonb)
to authenticated;
notify pgrst, 'reload schema';
