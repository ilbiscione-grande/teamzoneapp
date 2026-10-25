-- The training session's goals are a list: the event's "Mål för träningen"
-- (core.event_kpi_targets), own goals or counted KPIs, followed up after the
-- training. A session's old free-text goal becomes own yes/no goals, one per
-- line (at most 80 characters each), and is cleared. A new session no longer
-- starts its goal from the event's free-text focus.

with lines as (
  select session.event_id, event_row.club_id, session.updated_by,
    left(btrim(regexp_replace(line.text, '^\s*[•\-\*]\s*', '')), 80) as label, line.n
  from core.training_sessions session
  join core.events event_row on event_row.id = session.event_id
  cross join lateral regexp_split_to_table(session.goal, '\n') with ordinality as line(text, n)
  where btrim(session.goal) <> '' and session.updated_by is not null
)
insert into core.event_kpi_targets (club_id, event_id, kpi_key, label, value_type, direction, source, comparator,
  target, position, created_by)
select lines.club_id, lines.event_id, 'custom', lines.label, 'boolean', 'higher', 'manual', 'eq', 1,
  coalesce((select max(target.position) from core.event_kpi_targets target where target.event_id = lines.event_id), -1)
    + row_number() over (partition by lines.event_id order by lines.n),
  lines.updated_by
from lines
where lines.label <> '';

update core.training_sessions set goal = '' where btrim(goal) <> '' and updated_by is not null;

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
        'source_kind', block.source_kind, 'source_id', block.source_id
      ) order by block.position)
      from core.training_blocks block where block.event_id = event_row.id), '[]'::jsonb)
  );
end;
$$;
