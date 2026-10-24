-- Tacticsboard's library, step 1 (decision package 13, TBL-01/02/12/16):
-- "Mitt bibliotek", what you save from your boards. An exercise is one
-- board with its details (the part of the session, minutes, players, area,
-- organisation, coaching points, the phase of the game, age classes and game
-- forms); a pass is a training project's boards in order, each with its
-- details, with a theme and a goal; a session is an education project's
-- boards in order. Saving the same board or project again updates its
-- entry (a new version). The boards are saved as in a template: without the
-- squad or ties to TeamZone players. Sharing with the club and with
-- TeamZone's library comes in the next steps.

create table core.tactics_library_items (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references core.profiles(id),
  kind text not null check (kind in ('exercise', 'plan', 'lesson')),
  title text not null check (length(btrim(title)) between 1 and 120),
  details jsonb not null default '{}'::jsonb,
  document jsonb not null,
  -- The project, and for an exercise the board, it was saved from.
  source_project_id uuid references core.tactics_projects(id) on delete set null,
  source_board_id text,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(details) = 'object'),
  check (jsonb_typeof(document) = 'object' and jsonb_typeof(document->'boards') = 'array'),
  check (pg_column_size(document) <= 4000000)
);
create index tactics_library_items_owner on core.tactics_library_items (owner_id, updated_at desc);
create index tactics_library_items_source_project on core.tactics_library_items (source_project_id);
create unique index tactics_library_items_source on core.tactics_library_items
  (owner_id, kind, source_project_id, coalesce(source_board_id, '')) where source_project_id is not null;

alter table core.tactics_library_items enable row level security;
revoke all on core.tactics_library_items from public, anon, authenticated;
create policy tactics_library_items_no_direct_access on core.tactics_library_items
  for all to authenticated using (false) with check (false);

-- An exercise's details, checked: the part, minutes, players, area,
-- organisation, coaching points, phase, age classes and game forms.
create or replace function internal.tactics_exercise_details_valid(details jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select jsonb_typeof(details) = 'object'
    and coalesce(details->>'part', 'main') in ('warmup', 'main', 'finish')
    and (details->'minutes' is null or (jsonb_typeof(details->'minutes') = 'number'
      and (details->>'minutes')::numeric between 0 and 240 and (details->>'minutes')::numeric = round((details->>'minutes')::numeric)))
    and (details->'players' is null or jsonb_typeof(details->'players') = 'null' or (jsonb_typeof(details->'players') = 'number'
      and (details->>'players')::numeric between 1 and 60 and (details->>'players')::numeric = round((details->>'players')::numeric)))
    and length(coalesce(details->>'area', '')) <= 40
    and length(coalesce(details->>'organisation', '')) <= 2000
    and length(coalesce(details->>'coaching_points', '')) <= 2000
    and (details->>'phase' is null or details->>'phase' in ('scoring', 'preventing_scoring', 'build_up',
      'preventing_build_up', 'counter', 'regaining', 'attacking_play', 'defending'))
    and (details->'age_classes' is null or (jsonb_typeof(details->'age_classes') = 'array'
      and not exists (select 1 from jsonb_array_elements_text(details->'age_classes') age
        where age not in ('7-9', '10-12', '13-15', '16+'))))
    and (details->'game_forms' is null or (jsonb_typeof(details->'game_forms') = 'array'
      and not exists (select 1 from jsonb_array_elements_text(details->'game_forms') form
        where form not in ('3v3', '5v5', '7v7', '9v9', '11v11'))))
$$;

-- The item without its boards, for the lists.
create or replace function internal.tactics_library_summary(item core.tactics_library_items)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', item.id, 'kind', item.kind, 'title', item.title, 'details', item.details, 'version', item.version,
    'source_project_id', item.source_project_id, 'source_board_id', item.source_board_id,
    'board_count', jsonb_array_length(item.document->'boards'),
    'boards', (select coalesce(jsonb_agg(jsonb_build_object('id', board->>'id', 'name', board->>'name')), '[]'::jsonb)
               from jsonb_array_elements(item.document->'boards') board),
    'updated_at', item.updated_at
  )
$$;

create or replace function internal.list_my_tactics_library_for_actor()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  return coalesce((
    select jsonb_agg(internal.tactics_library_summary(item) order by item.updated_at desc)
    from core.tactics_library_items item where item.owner_id = auth.uid()
  ), '[]'::jsonb);
end;
$$;

create or replace function internal.get_tactics_library_item_for_actor(target_item_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare item core.tactics_library_items;
begin
  select * into item from core.tactics_library_items where id = target_item_id;
  if item.id is null or item.owner_id is distinct from auth.uid() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return internal.tactics_library_summary(item) || jsonb_build_object('document', item.document);
end;
$$;

-- Saves an exercise, a pass or a session in your library. Saved again from
-- the same project (and board), it updates that entry with a new version.
-- A pass's details hold its theme and goal and, per board, the exercise's
-- details; a session needs none. At most 500 items.
create or replace function internal.save_tactics_library_item_for_actor(
  item_kind text, item_title text, item_details jsonb, item_document jsonb,
  from_project_id uuid, from_board_id text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare saved core.tactics_library_items; board_count integer;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if item_kind is null or item_kind not in ('exercise', 'plan', 'lesson')
    or length(btrim(coalesce(item_title, ''))) not between 1 and 120
    or jsonb_typeof(coalesce(item_details, 'null'::jsonb)) <> 'object'
    or jsonb_typeof(coalesce(item_document, 'null'::jsonb)) <> 'object'
    or jsonb_typeof(item_document->'boards') is distinct from 'array' then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  board_count := jsonb_array_length(item_document->'boards');
  if board_count = 0 or board_count > 40 or (item_kind = 'exercise' and board_count <> 1)
    or (item_kind = 'exercise' and not internal.tactics_exercise_details_valid(item_details))
    or (item_kind = 'plan' and (length(coalesce(item_details->>'theme', '')) > 200
      or length(coalesce(item_details->>'goal', '')) > 2000
      or jsonb_typeof(coalesce(item_details->'exercises', '[]'::jsonb)) <> 'array'
      or exists (select 1 from jsonb_array_elements(coalesce(item_details->'exercises', '[]'::jsonb)) exercise
        where not internal.tactics_exercise_details_valid(exercise)))) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if from_project_id is not null and not exists (
      select 1 from core.tactics_projects project where project.id = from_project_id and project.owner_id = auth.uid()) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if from_project_id is not null then
    update core.tactics_library_items item set title = btrim(item_title), details = item_details, document = item_document,
      version = item.version + 1, updated_at = now()
    where item.owner_id = auth.uid() and item.kind = item_kind and item.source_project_id = from_project_id
      and coalesce(item.source_board_id, '') = coalesce(case when item_kind = 'exercise' then from_board_id end, '')
    returning * into saved;
    if saved.id is not null then
      return internal.tactics_library_summary(saved) || jsonb_build_object('created', false);
    end if;
  end if;
  if (select count(*) from core.tactics_library_items where owner_id = auth.uid()) >= 500 then
    raise check_violation using message = 'too_many_items';
  end if;
  insert into core.tactics_library_items (owner_id, kind, title, details, document, source_project_id, source_board_id)
  values (auth.uid(), item_kind, btrim(item_title), item_details, item_document, from_project_id,
    case when item_kind = 'exercise' then from_board_id end)
  returning * into saved;
  return internal.tactics_library_summary(saved) || jsonb_build_object('created', true);
end;
$$;

create or replace function internal.delete_tactics_library_item_for_actor(target_item_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from core.tactics_library_items where id = target_item_id and owner_id = auth.uid();
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
end;
$$;

create or replace function api.list_my_tactics_library() returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.list_my_tactics_library_for_actor() $$;
create or replace function api.get_tactics_library_item(target_item_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_tactics_library_item_for_actor(target_item_id) $$;
create or replace function api.save_tactics_library_item(item_kind text, item_title text, item_details jsonb,
  item_document jsonb, from_project_id uuid, from_board_id text) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.save_tactics_library_item_for_actor(item_kind, item_title, item_details, item_document,
    from_project_id, from_board_id) $$;
create or replace function api.delete_tactics_library_item(target_item_id uuid) returns void
language sql security invoker set search_path = '' as $$ select internal.delete_tactics_library_item_for_actor(target_item_id) $$;

revoke all on function
  internal.tactics_exercise_details_valid(jsonb), internal.tactics_library_summary(core.tactics_library_items),
  internal.list_my_tactics_library_for_actor(), internal.get_tactics_library_item_for_actor(uuid),
  internal.save_tactics_library_item_for_actor(text, text, jsonb, jsonb, uuid, text),
  internal.delete_tactics_library_item_for_actor(uuid),
  api.list_my_tactics_library(), api.get_tactics_library_item(uuid),
  api.save_tactics_library_item(text, text, jsonb, jsonb, uuid, text), api.delete_tactics_library_item(uuid)
from public, anon, authenticated;
grant execute on function
  internal.list_my_tactics_library_for_actor(), internal.get_tactics_library_item_for_actor(uuid),
  internal.save_tactics_library_item_for_actor(text, text, jsonb, jsonb, uuid, text),
  internal.delete_tactics_library_item_for_actor(uuid),
  api.list_my_tactics_library(), api.get_tactics_library_item(uuid),
  api.save_tactics_library_item(text, text, jsonb, jsonb, uuid, text), api.delete_tactics_library_item(uuid)
to authenticated;
notify pgrst, 'reload schema';
