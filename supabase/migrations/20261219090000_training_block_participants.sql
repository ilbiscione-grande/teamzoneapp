-- Per-block player assignments. CLI-created migration renumbered after the
-- existing December prerequisites so a fresh replay applies in dependency order.
create function internal.valid_training_block_players(players jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare player jsonb;
begin
  if jsonb_typeof(players) is distinct from 'array' then return false; end if;
  if jsonb_array_length(players) > 80 then return false; end if;
  for player in select value from jsonb_array_elements(players) loop
    if jsonb_typeof(player) is distinct from 'object'
      or jsonb_typeof(player->'name') is distinct from 'string'
      or length(player->>'name') > 120
      or coalesce(player->>'team', '') not in ('blue','red','green','yellow','neutral')
      or (player - array['person_id','name','team']) <> '{}'::jsonb then return false; end if;
    if player->>'person_id' is not null and (
      jsonb_typeof(player->'person_id') is distinct from 'string'
      or player->>'person_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ) then return false; end if;
  end loop;
  return not exists (select 1 from jsonb_array_elements(players) p
    where p->>'person_id' is not null group by lower(p->>'person_id') having count(*) > 1);
end;
$$;
revoke all on function internal.valid_training_block_players(jsonb) from public, anon, authenticated;
alter table core.training_blocks add column players jsonb not null default '[]'::jsonb
  check (internal.valid_training_block_players(players));

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
    'goal', coalesce(session.goal, ''),
    'event_plan', case when session.event_id is null then nullif(btrim(coalesce(event_row.training_plan, '')), '') end,
    'updated_at', session.updated_at,
    'updated_by', (select nullif(btrim(profile.display_name), '') from core.profiles profile where profile.id = session.updated_by),
    'blocks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', block.id, 'part', block.part, 'title', block.title, 'minutes', block.minutes,
        'organisation', block.organisation, 'coaching_points', block.coaching_points, 'phase', block.phase,
        'source_kind', block.source_kind, 'source_id', block.source_id, 'players', coalesce((select jsonb_agg(jsonb_build_object(
          'person_id', entry.value->>'person_id', 'team', entry.value->>'team',
          'name', case when entry.value->>'person_id' is null then '' else coalesce(
            (select left(person.display_name,120) from core.club_people person
              where person.id = (entry.value->>'person_id')::uuid and person.club_id = event_row.club_id
                and person.status = 'active'), '—') end
        ) order by entry.position) from jsonb_array_elements(block.players) with ordinality entry(value,position)), '[]'::jsonb)
      ) order by block.position)
      from core.training_blocks block where block.event_id = event_row.id), '[]'::jsonb)
  );
end;
$$;

create or replace function internal.save_training_session_for_actor(
  target_event_id uuid, expected_revision bigint, session_theme text, session_goal text, is_published boolean,
  session_blocks jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  event_row core.events;
  current_revision bigint;
  block jsonb;
  player jsonb;
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
    if not internal.valid_training_block_players(coalesce(block->'players', '[]'::jsonb)) then
      raise invalid_parameter_value using message = 'invalid_players';
    end if;
    for player in select value from jsonb_array_elements(coalesce(block->'players','[]'::jsonb)) loop
      if player->>'person_id' is not null and not exists (
        select 1 from core.assignments assignment
        join core.club_people person on person.id = assignment.club_person_id and person.club_id = assignment.club_id
        join core.event_teams relation on relation.event_id = event_row.id and relation.club_id = assignment.club_id
          and relation.team_id = assignment.team_id
        where assignment.club_id = event_row.club_id and assignment.club_person_id = (player->>'person_id')::uuid
          and assignment.state = 'active' and assignment.role_package = 'player' and person.status = 'active'
          and assignment.starts_at <= event_row.starts_at and (assignment.ends_at is null or assignment.ends_at > event_row.starts_at)
      ) then raise invalid_parameter_value using message = 'invalid_player_reference'; end if;
    end loop;
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
      source_kind, source_id, players)
    values (event_row.id, block_position, block->>'part', btrim(block->>'title'), (block->>'minutes')::integer,
      coalesce(block->>'organisation', ''), coalesce(block->>'coaching_points', ''), block->>'phase',
      coalesce(block->>'source_kind', 'own'),
      case when block->>'source_kind' = 'library' then nullif(block->>'source_id', '')::uuid end,
      coalesce((select jsonb_agg(jsonb_build_object(
        'person_id', entry.value->>'person_id', 'team', entry.value->>'team',
        'name', ''
      ) order by entry.position) from jsonb_array_elements(coalesce(block->'players','[]'::jsonb)) with ordinality entry(value,position)), '[]'::jsonb));
    block_position := block_position + 1;
  end loop;
  return internal.training_session_json(event_row, true);
end;
$$;

