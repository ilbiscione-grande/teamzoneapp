-- Training module, step 1 (decision package 11, MFD-08): the training
-- session, one per training event, versioned. Blocks in order, each in a
-- part of the session (warm-up, main part, finish, as in the old app):
-- the exercise's name, minutes, organisation, coaching points, and
-- optionally the phase of the game it trains (the Swedish FA's phases, as
-- the Team Development Plan's principles). A block can later come from
-- the exercise library (step 2); its origin is kept. The session is saved
-- whole on the revision read, as the match plan, and is the leaders' until
-- published; then the players see it. Written by those who prepare the
-- training (training.plan) where the club has the Training module.

create table core.training_sessions (
  event_id uuid primary key references core.events(id) on delete cascade,
  club_id uuid not null references core.clubs(id),
  team_id uuid not null,
  theme text not null default '' check (length(theme) <= 200),
  goal text not null default '' check (length(goal) <= 2000),
  published boolean not null default false,
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references core.profiles(id) on delete set null
);
create index training_sessions_team on core.training_sessions (team_id);
create index training_sessions_updated_by on core.training_sessions (updated_by);

create table core.training_blocks (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references core.training_sessions(event_id) on delete cascade,
  position integer not null,
  part text not null check (part in ('warmup', 'main', 'finish')),
  title text not null check (length(btrim(title)) between 1 and 120),
  minutes integer not null default 0 check (minutes between 0 and 240),
  organisation text not null default '' check (length(organisation) <= 2000),
  coaching_points text not null default '' check (length(coaching_points) <= 2000),
  phase text check (phase in ('scoring', 'preventing_scoring', 'build_up', 'preventing_build_up',
    'counter', 'regaining', 'attacking_play', 'defending')),
  -- Where the block came from: written here, or copied from the library.
  source_kind text not null default 'own' check (source_kind in ('own', 'library')),
  source_id uuid,
  unique (event_id, position)
);

alter table core.training_sessions enable row level security;
alter table core.training_blocks enable row level security;
revoke all on core.training_sessions, core.training_blocks from public, anon, authenticated;
create policy training_sessions_no_direct_access on core.training_sessions
  for all to authenticated using (false) with check (false);
create policy training_blocks_no_direct_access on core.training_blocks
  for all to authenticated using (false) with check (false);

-- The training event the session is for, when the one asking may read it
-- and the club has the module.
create or replace function internal.training_session_event(target_event_id uuid)
returns core.events language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events;
begin
  select * into event_row from core.events where id = target_event_id;
  if event_row.id is null or event_row.event_type <> 'training' or event_row.owning_team_id is null
    or auth.uid() is null or not internal.actor_can_read_event(target_event_id)
    or not internal.module_allows_read(event_row.club_id, 'module.training') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return event_row;
end;
$$;

create or replace function internal.training_session_can_edit(event_row core.events)
returns boolean language sql stable security definer set search_path = '' as $$
  select internal.module_allows_write(event_row.club_id, 'module.training')
    and internal.actor_has_event_capability(event_row.id, 'training.plan')
    and event_row.archived_at is null
$$;

-- The session as its reader may see it: everything for those who prepare
-- it, a published one for the players, else nothing. A new session starts
-- from the event's own theme, focus and plan in the built-in app.
create or replace function internal.training_session_json(event_row core.events, can_edit boolean)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare session core.training_sessions;
begin
  select * into session from core.training_sessions where event_id = event_row.id;
  if not can_edit and (session.event_id is null or not session.published) then return null; end if;
  return jsonb_build_object(
    'event_id', event_row.id, 'can_edit', can_edit,
    'title', event_row.title, 'starts_at', event_row.starts_at, 'ends_at', event_row.ends_at,
    'revision', coalesce(session.revision, 0), 'published', coalesce(session.published, false),
    'theme', coalesce(session.theme, coalesce(event_row.training_theme, '')),
    'goal', coalesce(session.goal, coalesce(event_row.training_focus, '')),
    'event_plan', case when session.event_id is null then nullif(btrim(coalesce(event_row.training_plan, '')), '') end,
    'updated_at', session.updated_at,
    'updated_by', (select nullif(btrim(profile.display_name), '') from core.profiles profile where profile.id = session.updated_by),
    'blocks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', block.id, 'part', block.part, 'title', block.title, 'minutes', block.minutes,
        'organisation', block.organisation, 'coaching_points', block.coaching_points, 'phase', block.phase,
        'source_kind', block.source_kind, 'source_id', block.source_id
      ) order by block.position)
      from core.training_blocks block where block.event_id = event_row.id), '[]'::jsonb)
  );
end;
$$;

create or replace function internal.get_training_session_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events;
begin
  event_row := internal.training_session_event(target_event_id);
  return internal.training_session_json(event_row, internal.training_session_can_edit(event_row));
end;
$$;

-- Saves the whole session on the revision read (0 for a new one): its
-- theme, goal, whether the players see it, and its blocks in order (at most
-- 30). The session as it is after the save comes back.
create or replace function internal.save_training_session_for_actor(
  target_event_id uuid, expected_revision bigint, session_theme text, session_goal text, is_published boolean,
  session_blocks jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  event_row core.events;
  current_revision bigint;
  block jsonb;
  block_position integer := 0;
begin
  event_row := internal.training_session_event(target_event_id);
  if not internal.training_session_can_edit(event_row) then raise insufficient_privilege using message = 'not_allowed'; end if;
  if length(coalesce(session_theme, '')) > 200 or length(coalesce(session_goal, '')) > 2000 or is_published is null
    or jsonb_typeof(coalesce(session_blocks, 'null'::jsonb)) <> 'array' or jsonb_array_length(session_blocks) > 30 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  for block in select value from jsonb_array_elements(session_blocks) loop
    if jsonb_typeof(block) <> 'object'
      or coalesce(block->>'part', '') not in ('warmup', 'main', 'finish')
      or length(btrim(coalesce(block->>'title', ''))) not between 1 and 120
      or jsonb_typeof(block->'minutes') is distinct from 'number'
      or (block->>'minutes')::numeric not between 0 and 240 or (block->>'minutes')::numeric <> round((block->>'minutes')::numeric)
      or length(coalesce(block->>'organisation', '')) > 2000 or length(coalesce(block->>'coaching_points', '')) > 2000
      or (block->>'phase' is not null and block->>'phase' not in ('scoring', 'preventing_scoring', 'build_up',
        'preventing_build_up', 'counter', 'regaining', 'attacking_play', 'defending'))
      or coalesce(block->>'source_kind', 'own') not in ('own', 'library') then
      raise invalid_parameter_value using message = 'invalid_input';
    end if;
  end loop;
  perform pg_advisory_xact_lock(hashtextextended(event_row.id::text, 2));
  select revision into current_revision from core.training_sessions where event_id = event_row.id for update;
  if coalesce(current_revision, 0) <> coalesce(expected_revision, -1) then
    raise serialization_failure using message = 'stale_revision';
  end if;
  insert into core.training_sessions (event_id, club_id, team_id, theme, goal, published, revision, updated_by)
  values (event_row.id, event_row.club_id, event_row.owning_team_id, btrim(coalesce(session_theme, '')),
    btrim(coalesce(session_goal, '')), is_published, 1, auth.uid())
  on conflict (event_id) do update set theme = excluded.theme, goal = excluded.goal, published = excluded.published,
    revision = core.training_sessions.revision + 1, updated_at = now(), updated_by = excluded.updated_by;
  delete from core.training_blocks where event_id = event_row.id;
  for block in select value from jsonb_array_elements(session_blocks) loop
    insert into core.training_blocks (event_id, position, part, title, minutes, organisation, coaching_points, phase,
      source_kind, source_id)
    values (event_row.id, block_position, block->>'part', btrim(block->>'title'), (block->>'minutes')::integer,
      coalesce(block->>'organisation', ''), coalesce(block->>'coaching_points', ''), block->>'phase',
      coalesce(block->>'source_kind', 'own'),
      case when block->>'source_kind' = 'library' then nullif(block->>'source_id', '')::uuid end);
    block_position := block_position + 1;
  end loop;
  return internal.training_session_json(event_row, true);
end;
$$;

-- The Training module's list: a team's trainings in a period with how far
-- each session is planned and how many minutes it holds.
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
      'blocks', (select count(*) from core.training_blocks block where block.event_id = event_row.id)
    ) order by event_row.starts_at)
    from core.events event_row
    left join core.training_sessions session on session.event_id = event_row.id
    where event_row.owning_team_id = target_team_id and event_row.event_type = 'training' and event_row.archived_at is null
      and event_row.starts_at >= from_time and event_row.starts_at < to_time
  ), '[]'::jsonb);
end;
$$;

create or replace function api.get_training_session(target_event_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_training_session_for_actor(target_event_id) $$;
create or replace function api.save_training_session(target_event_id uuid, expected_revision bigint, session_theme text,
  session_goal text, is_published boolean, session_blocks jsonb) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.save_training_session_for_actor(target_event_id, expected_revision, session_theme, session_goal,
    is_published, session_blocks) $$;
create or replace function api.list_module_trainings(target_team_id uuid, from_time timestamptz, to_time timestamptz) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.list_module_trainings_for_actor(target_team_id, from_time, to_time) $$;

revoke all on function
  internal.training_session_event(uuid), internal.training_session_can_edit(core.events),
  internal.training_session_json(core.events, boolean), internal.get_training_session_for_actor(uuid),
  internal.save_training_session_for_actor(uuid, bigint, text, text, boolean, jsonb),
  internal.list_module_trainings_for_actor(uuid, timestamptz, timestamptz),
  api.get_training_session(uuid), api.save_training_session(uuid, bigint, text, text, boolean, jsonb),
  api.list_module_trainings(uuid, timestamptz, timestamptz)
from public, anon, authenticated;
grant execute on function
  internal.get_training_session_for_actor(uuid),
  internal.save_training_session_for_actor(uuid, bigint, text, text, boolean, jsonb),
  internal.list_module_trainings_for_actor(uuid, timestamptz, timestamptz),
  api.get_training_session(uuid), api.save_training_session(uuid, bigint, text, text, boolean, jsonb),
  api.list_module_trainings(uuid, timestamptz, timestamptz)
to authenticated;
notify pgrst, 'reload schema';
