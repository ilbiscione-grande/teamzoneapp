-- Tacticsboard's library, step 2 (decision package 13, TBL-03–07/13/15/16):
-- TeamZone's library, shared by everyone with Tacticsboard. Anyone shares
-- an item of their own library; what is shared is a locked copy (the
-- version as shared), and sharing it again after a change shares a new
-- version. The writer's name shows (no alias). Whoever uses an item takes
-- a copy, so a later version or removal never changes their projects. The
-- writer may remove what they shared. Items can be reported; three reports
-- hide one until TeamZone's support decides, as the match pool's listings.
-- TeamZone's own starters (the old app's fifteen exercises) are shared by
-- TeamZone, without boards drawn yet.

create table core.tactics_shared_items (
  id uuid primary key default gen_random_uuid(),
  -- Null for TeamZone's starters.
  owner_id uuid references core.profiles(id) on delete cascade,
  library_item_id uuid unique references core.tactics_library_items(id) on delete set null,
  kind text not null check (kind in ('exercise', 'plan', 'lesson')),
  title text not null check (length(btrim(title)) between 1 and 120),
  details jsonb not null default '{}'::jsonb,
  document jsonb not null,
  version integer not null default 1 check (version > 0),
  hidden boolean not null default false,
  hidden_by_support boolean not null default false,
  shared_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(details) = 'object'),
  check (jsonb_typeof(document) = 'object' and jsonb_typeof(document->'boards') = 'array'),
  check (pg_column_size(document) <= 4000000)
);
create index tactics_shared_items_owner on core.tactics_shared_items (owner_id);
create index tactics_shared_items_kind on core.tactics_shared_items (kind, updated_at desc) where not hidden;

create table core.tactics_shared_reports (
  shared_item_id uuid not null references core.tactics_shared_items(id) on delete cascade,
  reporter_id uuid not null references core.profiles(id) on delete cascade,
  reason text not null check (length(btrim(reason)) between 1 and 500),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references core.profiles(id) on delete set null,
  resolution text check (resolution in ('hidden', 'dismissed')),
  primary key (shared_item_id, reporter_id)
);
create index tactics_shared_reports_reporter on core.tactics_shared_reports (reporter_id);
create index tactics_shared_reports_resolved_by on core.tactics_shared_reports (resolved_by);

alter table core.tactics_shared_items enable row level security;
alter table core.tactics_shared_reports enable row level security;
revoke all on core.tactics_shared_items, core.tactics_shared_reports from public, anon, authenticated;
create policy tactics_shared_items_no_direct_access on core.tactics_shared_items
  for all to authenticated using (false) with check (false);
create policy tactics_shared_reports_no_direct_access on core.tactics_shared_reports
  for all to authenticated using (false) with check (false);

insert into core.tactics_shared_items (kind, title, details, document)
select 'exercise', starter.title,
  jsonb_build_object('part', starter.part, 'minutes', starter.minutes, 'organisation', starter.organisation,
    'phase', starter.phase, 'age_classes', '[]'::jsonb, 'game_forms', '[]'::jsonb),
  jsonb_build_object('schemaVersion', 1, 'boards', jsonb_build_array(jsonb_build_object(
    'id', gen_random_uuid()::text, 'name', starter.title, 'view', 'empty', 'overlay', 'none', 'showNames', false,
    'frames', jsonb_build_array(jsonb_build_object('id', gen_random_uuid()::text, 'objects', '[]'::jsonb,
      'durationMs', 1000, 'note', '')))))
from (values
  ('Aktiveringsrondo 6 mot 2', 'warmup', 10,
    'Boll i rörelse med hög passningshastighet i en liten yta. Väcker fötter och huvud inför passet.', null),
  ('Löpskola med boll', 'warmup', 8,
    'Korta stafetter med teknikinslag (insida, utsida, finter) som höjer pulsen och skärper tekniken.', null),
  ('Snabbhet och riktningsförändring', 'warmup', 10,
    'Korta sprintar med snabba vändningar. Förbereder kroppen för explosiva moment i huvuddelen.', null),
  ('Press i par 2 mot 1', 'main', 15,
    'Två spelare pressar en bollhållare i en begränsad yta och tränar vinklar och samarbete i pressen.', 'regaining'),
  ('Utlösare och signaler 4 mot 4 + 2', 'main', 20,
    'Spel i en liten yta där laget tränar att läsa tydliga signaler för press och reagera samtidigt.', 'regaining'),
  ('Press till avslut 6 mot 6', 'finish', 15,
    'Matchspel där varje bollvinst högt upp ska leda till ett snabbt avslut inom tre passningar.', 'regaining'),
  ('Uppspel från målvakt 4 mot 2', 'main', 15,
    'Backlinje och målvakt tränar att skapa spelbara vinklar mot en pressande motståndare.', 'build_up'),
  ('Genom tredjedelarna 8 mot 8', 'main', 20,
    'Positionsspel som belönar laget för att spela sig igenom planens alla tredjedelar med kontroll.', 'build_up'),
  ('Uppbyggnad till mål 7 mot 7', 'finish', 15,
    'Helplansspel där laget måste slå minst fyra passningar i uppbyggnaden innan avslut är tillåtet.', 'build_up'),
  ('Zonförsvar och förflyttning 5 mot 5', 'main', 15,
    'Laget tränar att flytta som en enhet och täcka zoner när bollen byter sida.', 'defending'),
  ('Kompakthet 8 mot 4', 'main', 20,
    'Överläge för det anfallande laget tvingar försvararna att hålla avstånden och täcka de centrala ytorna.', 'defending'),
  ('Försvarsblock i matchspel 7 mot 7', 'finish', 15,
    'Matchspel med fokus på blockets höjd och att täcka bakom spelaren som kliver fram.', 'defending'),
  ('Omställning 4 mot 4 med målvakt', 'main', 15,
    'Direkt efter bollvinst ska laget snabbt hitta den första aktionen framåt.', 'counter'),
  ('Kontring från press 6 mot 6', 'main', 20,
    'Bollvinst på egen planhalva ska leda till en snabb kontring med stöd i bredd och djup.', 'counter'),
  ('Snabba avslut efter omställning 5 mot 5', 'finish', 15,
    'Matchspel där mål bara räknas om de görs inom tio sekunder efter bollvinst.', 'scoring')
) as starter (title, part, minutes, organisation, phase);

-- A shared item for the lists: its writer by name, whether it is yours,
-- without its boards.
create or replace function internal.tactics_shared_summary(item core.tactics_shared_items)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', item.id, 'kind', item.kind, 'title', item.title, 'details', item.details, 'version', item.version,
    'author', case when item.owner_id is null then 'TeamZone'
      else coalesce((select nullif(btrim(profile.display_name), '') from core.profiles profile where profile.id = item.owner_id),
        'En tränare') end,
    'starter', item.owner_id is null,
    'mine', item.owner_id is not distinct from auth.uid() and item.owner_id is not null,
    'hidden', item.hidden,
    'board_count', jsonb_array_length(item.document->'boards'),
    'boards', (select coalesce(jsonb_agg(jsonb_build_object('id', board->>'id', 'name', board->>'name')), '[]'::jsonb)
               from jsonb_array_elements(item.document->'boards') board),
    'updated_at', item.updated_at
  )
$$;

-- As in step 1, with whether the item is shared in TeamZone's library and
-- which version.
create or replace function internal.tactics_library_summary(item core.tactics_library_items)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', item.id, 'kind', item.kind, 'title', item.title, 'details', item.details, 'version', item.version,
    'source_project_id', item.source_project_id, 'source_board_id', item.source_board_id,
    'board_count', jsonb_array_length(item.document->'boards'),
    'boards', (select coalesce(jsonb_agg(jsonb_build_object('id', board->>'id', 'name', board->>'name')), '[]'::jsonb)
               from jsonb_array_elements(item.document->'boards') board),
    'shared', (select jsonb_build_object('id', shared.id, 'version', shared.version, 'hidden', shared.hidden,
        'current', shared.updated_at >= item.updated_at)
      from core.tactics_shared_items shared where shared.library_item_id = item.id),
    'updated_at', item.updated_at
  )
$$;

-- Shares an item of your library in TeamZone's library, or shares its
-- latest version again. Returns the shared item.
create or replace function internal.share_tactics_library_item_for_actor(target_item_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare item core.tactics_library_items; shared core.tactics_shared_items;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  select * into item from core.tactics_library_items where id = target_item_id and owner_id = auth.uid();
  if item.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  update core.tactics_shared_items set title = item.title, details = item.details, document = item.document,
    kind = item.kind, version = version + 1, updated_at = now()
  where library_item_id = item.id and owner_id = auth.uid() and not hidden_by_support
  returning * into shared;
  if shared.id is null then
    if exists (select 1 from core.tactics_shared_items where library_item_id = item.id) then
      raise insufficient_privilege using message = 'hidden_by_support';
    end if;
    if (select count(*) from core.tactics_shared_items where owner_id = auth.uid()) >= 200 then
      raise check_violation using message = 'too_many_shared';
    end if;
    insert into core.tactics_shared_items (owner_id, library_item_id, kind, title, details, document)
    values (auth.uid(), item.id, item.kind, item.title, item.details, item.document)
    returning * into shared;
  end if;
  return internal.tactics_shared_summary(shared);
end;
$$;

-- Removes what you shared from TeamZone's library; those who used it keep
-- their copies.
create or replace function internal.unshare_tactics_item_for_actor(target_shared_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from core.tactics_shared_items where id = target_shared_id and owner_id = auth.uid();
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
end;
$$;

-- Searches TeamZone's library: words in the title, organisation or
-- coaching points, and filters on kind, part, phase, age class and game
-- form. Hidden items show only to their writer. Newest first, 30 at a time.
create or replace function internal.search_tactics_shared_items_for_actor(
  search_text text, item_kind text, exercise_part text, game_phase text, age_class text, game_form text, page integer
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare words text[];
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if length(coalesce(search_text, '')) > 100 or coalesce(page, 0) not between 0 and 100 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  words := array_remove(regexp_split_to_array(lower(btrim(coalesce(search_text, ''))), '\s+'), '');
  return coalesce((
    select jsonb_agg(internal.tactics_shared_summary(hit) order by hit.owner_id is null, hit.updated_at desc)
    from (
      select item.* from core.tactics_shared_items item
      where (not item.hidden or item.owner_id = auth.uid())
        and (item_kind is null or item.kind = item_kind)
        and (exercise_part is null or item.details->>'part' = exercise_part
          or exists (select 1 from jsonb_array_elements(coalesce(item.details->'exercises', '[]'::jsonb)) exercise
            where exercise->>'part' = exercise_part))
        and (game_phase is null or item.details->>'phase' = game_phase
          or exists (select 1 from jsonb_array_elements(coalesce(item.details->'exercises', '[]'::jsonb)) exercise
            where exercise->>'phase' = game_phase))
        and (age_class is null or coalesce(item.details->'age_classes', '[]'::jsonb) ? age_class
          or exists (select 1 from jsonb_array_elements(coalesce(item.details->'exercises', '[]'::jsonb)) exercise
            where coalesce(exercise->'age_classes', '[]'::jsonb) ? age_class))
        and (game_form is null or coalesce(item.details->'game_forms', '[]'::jsonb) ? game_form
          or exists (select 1 from jsonb_array_elements(coalesce(item.details->'exercises', '[]'::jsonb)) exercise
            where coalesce(exercise->'game_forms', '[]'::jsonb) ? game_form))
        and not exists (select 1 from unnest(words) word
          where position(word in lower(item.title || ' ' || coalesce(item.details->>'organisation', '') || ' '
            || coalesce(item.details->>'coaching_points', '') || ' ' || coalesce(item.details->>'theme', ''))) = 0)
      order by item.owner_id is null, item.updated_at desc
      limit 30 offset coalesce(page, 0) * 30
    ) hit
  ), '[]'::jsonb);
end;
$$;

-- One shared item with its boards, to use.
create or replace function internal.get_tactics_shared_item_for_actor(target_shared_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare item core.tactics_shared_items;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  select * into item from core.tactics_shared_items where id = target_shared_id;
  if item.id is null or (item.hidden and item.owner_id is distinct from auth.uid()) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return internal.tactics_shared_summary(item) || jsonb_build_object('document', item.document);
end;
$$;

-- A report; three open reports hide the item until support decides.
create or replace function internal.report_tactics_shared_item_for_actor(target_shared_id uuid, report_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare item core.tactics_shared_items;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  select * into item from core.tactics_shared_items where id = target_shared_id;
  if item.id is null or item.hidden or item.owner_id is not distinct from auth.uid() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if length(btrim(coalesce(report_reason, ''))) not between 1 and 500 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  insert into core.tactics_shared_reports (shared_item_id, reporter_id, reason)
  values (item.id, auth.uid(), btrim(report_reason))
  on conflict (shared_item_id, reporter_id) do nothing;
  if (select count(*) from core.tactics_shared_reports report
      where report.shared_item_id = item.id and report.resolved_at is null) >= 3 then
    update core.tactics_shared_items set hidden = true where id = item.id;
  end if;
end;
$$;

-- For TeamZone's support: reported items with their reports.
create or replace function internal.list_tactics_shared_reports_for_admin(only_open boolean)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_is_support_admin() then raise insufficient_privilege using message = 'not_found'; end if;
  return coalesce((select jsonb_agg(row_value order by latest desc) from (
    select internal.tactics_shared_summary(item) || jsonb_build_object(
        'hidden_by_support', item.hidden_by_support,
        'reports', (select jsonb_agg(jsonb_build_object('reason', report.reason, 'created_at', report.created_at,
            'resolution', report.resolution, 'resolved_at', report.resolved_at) order by report.created_at)
          from core.tactics_shared_reports report where report.shared_item_id = item.id)) as row_value,
      (select max(report.created_at) from core.tactics_shared_reports report where report.shared_item_id = item.id) as latest
    from core.tactics_shared_items item
    where exists (select 1 from core.tactics_shared_reports report where report.shared_item_id = item.id
      and (not coalesce(only_open, true) or report.resolved_at is null))
    order by latest desc limit 200) rows), '[]'::jsonb);
end;
$$;

-- Support hides an item, or shows it again; the open reports are resolved.
create or replace function internal.decide_tactics_shared_reports_for_admin(target_shared_id uuid, hide boolean, note text)
returns void language plpgsql security definer set search_path = '' as $$
declare item core.tactics_shared_items;
begin
  if not internal.actor_is_support_admin() then raise insufficient_privilege using message = 'not_found'; end if;
  if length(btrim(coalesce(note, ''))) not between 5 and 1000 or hide is null then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select * into item from core.tactics_shared_items where id = target_shared_id for update;
  if item.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  update core.tactics_shared_items set hidden = hide, hidden_by_support = hide where id = item.id;
  update core.tactics_shared_reports set resolved_at = now(), resolved_by = auth.uid(),
    resolution = case when hide then 'hidden' else 'dismissed' end
  where shared_item_id = item.id and resolved_at is null;
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id,
    aggregate_revision, reason, metadata)
  values (null, auth.uid(), 'support.tactics_shared_reports.decide.v1', 'tactics_shared_item', item.id, item.version,
    btrim(note), jsonb_build_object('hide', hide));
end;
$$;

create or replace function api.share_tactics_library_item(target_item_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.share_tactics_library_item_for_actor(target_item_id) $$;
create or replace function api.unshare_tactics_item(target_shared_id uuid) returns void
language sql security invoker set search_path = '' as $$ select internal.unshare_tactics_item_for_actor(target_shared_id) $$;
create or replace function api.search_tactics_shared_items(search_text text, item_kind text, exercise_part text,
  game_phase text, age_class text, game_form text, page integer) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select internal.search_tactics_shared_items_for_actor(search_text, item_kind, exercise_part, game_phase, age_class, game_form, page) $$;
create or replace function api.get_tactics_shared_item(target_shared_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_tactics_shared_item_for_actor(target_shared_id) $$;
create or replace function api.report_tactics_shared_item(target_shared_id uuid, report_reason text) returns void
language sql security invoker set search_path = '' as $$ select internal.report_tactics_shared_item_for_actor(target_shared_id, report_reason) $$;
create or replace function api.list_tactics_shared_reports(only_open boolean default true) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.list_tactics_shared_reports_for_admin(only_open) $$;
create or replace function api.decide_tactics_shared_reports(target_shared_id uuid, hide boolean, note text) returns void
language sql security invoker set search_path = '' as $$ select internal.decide_tactics_shared_reports_for_admin(target_shared_id, hide, note) $$;

revoke all on function
  internal.tactics_shared_summary(core.tactics_shared_items),
  internal.share_tactics_library_item_for_actor(uuid), internal.unshare_tactics_item_for_actor(uuid),
  internal.search_tactics_shared_items_for_actor(text, text, text, text, text, text, integer),
  internal.get_tactics_shared_item_for_actor(uuid), internal.report_tactics_shared_item_for_actor(uuid, text),
  internal.list_tactics_shared_reports_for_admin(boolean), internal.decide_tactics_shared_reports_for_admin(uuid, boolean, text),
  api.share_tactics_library_item(uuid), api.unshare_tactics_item(uuid),
  api.search_tactics_shared_items(text, text, text, text, text, text, integer), api.get_tactics_shared_item(uuid),
  api.report_tactics_shared_item(uuid, text), api.list_tactics_shared_reports(boolean),
  api.decide_tactics_shared_reports(uuid, boolean, text)
from public, anon, authenticated;
grant execute on function
  internal.share_tactics_library_item_for_actor(uuid), internal.unshare_tactics_item_for_actor(uuid),
  internal.search_tactics_shared_items_for_actor(text, text, text, text, text, text, integer),
  internal.get_tactics_shared_item_for_actor(uuid), internal.report_tactics_shared_item_for_actor(uuid, text),
  internal.list_tactics_shared_reports_for_admin(boolean), internal.decide_tactics_shared_reports_for_admin(uuid, boolean, text),
  api.share_tactics_library_item(uuid), api.unshare_tactics_item(uuid),
  api.search_tactics_shared_items(text, text, text, text, text, text, integer), api.get_tactics_shared_item(uuid),
  api.report_tactics_shared_item(uuid, text), api.list_tactics_shared_reports(boolean),
  api.decide_tactics_shared_reports(uuid, boolean, text)
to authenticated;
notify pgrst, 'reload schema';
