-- Mer detaljerad statistik för Tacticsboard (2026-11-14).
--
-- Support wants to see who is in Webtools right now, which tools, ready
-- boards, templates and library items are used most, and which pages are
-- visited. Part of it is already in the projects; the rest Webtools now
-- records:
--
-- * core.webtools_presence: one row per account, the last time an open
--   Webtools tab said so (about once a minute while it is visible). Gives
--   "active now" (the last five minutes). Overwritten, never a history.
-- * core.webtools_activity_days: the days an account had Webtools open.
--   Gives active per day, as core.profile_activity_days does for the app.
-- * core.webtools_usage_counts: counts per day of page views (by page
--   pattern, never an address with ids), ready boards, own templates,
--   library items and shared items used. No account is stored with them.
--
-- api.record_webtools_presence() and api.record_webtools_use(kind, key) are
-- for signed-in accounts (not live-lesson guests). The extra numbers are
-- added to api.get_tacticsboard_usage_for_server, which only the server
-- role may call. Counts only; the only names are titles of items shared in
-- the library, which are public there.

create table if not exists core.webtools_presence (
  profile_id uuid primary key references core.profiles(id) on delete cascade,
  seen_at timestamptz not null default now()
);
create index if not exists webtools_presence_seen_idx on core.webtools_presence(seen_at);

create table if not exists core.webtools_activity_days (
  profile_id uuid not null references core.profiles(id) on delete cascade,
  day date not null,
  primary key (profile_id, day)
);
create index if not exists webtools_activity_days_day_idx on core.webtools_activity_days(day);

create table if not exists core.webtools_usage_counts (
  day date not null,
  kind text not null check (kind in ('page', 'starter', 'template', 'library', 'shared')),
  key text not null check (key ~ '^[a-z0-9._/\[\]-]{1,100}$'),
  uses bigint not null default 0 check (uses >= 0),
  primary key (day, kind, key)
);

alter table core.webtools_presence enable row level security;
alter table core.webtools_activity_days enable row level security;
alter table core.webtools_usage_counts enable row level security;
revoke all on table core.webtools_presence, core.webtools_activity_days, core.webtools_usage_counts
  from public, anon, authenticated;

create or replace function internal.webtools_actor_counts()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and not coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
$$;

create or replace function internal.record_webtools_presence_for_actor()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not internal.webtools_actor_counts() then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  insert into core.webtools_presence(profile_id, seen_at) values (auth.uid(), now())
  on conflict (profile_id) do update set seen_at = excluded.seen_at;
  insert into core.webtools_activity_days(profile_id, day)
  values (auth.uid(), (now() at time zone 'Europe/Stockholm')::date) on conflict do nothing;
end
$$;

create or replace function internal.record_webtools_use_for_actor(target_kind text, target_key text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not internal.webtools_actor_counts() then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  if target_kind is null or target_kind not in ('page', 'starter', 'template', 'library', 'shared')
     or target_key is null or target_key !~ '^[a-z0-9._/\[\]-]{1,100}$' then
    raise invalid_parameter_value using message = 'invalid_use';
  end if;
  -- A shared item is counted by its id, and only one that exists.
  if target_kind = 'shared' and (target_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or not exists (select 1 from core.tactics_shared_items item where item.id = target_key::uuid)) then
    raise invalid_parameter_value using message = 'invalid_use';
  end if;
  insert into core.webtools_usage_counts(day, kind, key, uses)
  values ((now() at time zone 'Europe/Stockholm')::date, target_kind, target_key, 1)
  on conflict (day, kind, key) do update set uses = core.webtools_usage_counts.uses + 1;
end
$$;

-- The numbers added to the Tacticsboard tab.
create or replace function internal.get_tacticsboard_usage_more_for_server(period_days integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  today date := (now() at time zone 'Europe/Stockholm')::date;
  days integer := greatest(7, least(coalesce(period_days, 30), 365));
  first_day date;
  since timestamptz;
begin
  first_day := today - (days - 1);
  since := first_day::timestamp at time zone 'Europe/Stockholm';

  return jsonb_build_object(
    'activity_recorded_since', (select min(day) from core.webtools_activity_days),
    'active', jsonb_build_object(
      'now', (select count(*) from core.webtools_presence presence
        where presence.seen_at >= now() - interval '5 minutes'),
      'today', (select count(*) from core.webtools_activity_days active where active.day = today),
      'last_7_days', (select count(distinct active.profile_id) from core.webtools_activity_days active
        where active.day > today - 7),
      'last_30_days', (select count(distinct active.profile_id) from core.webtools_activity_days active
        where active.day > today - 30),
      'in_period', (select count(distinct active.profile_id) from core.webtools_activity_days active
        where active.day >= first_day)),
    'uses', (
      select jsonb_build_object(
        'starter', coalesce(sum(used.uses) filter (where used.kind = 'starter'), 0),
        'template', coalesce(sum(used.uses) filter (where used.kind = 'template'), 0),
        'library', coalesce(sum(used.uses) filter (where used.kind = 'library'), 0),
        'shared', coalesce(sum(used.uses) filter (where used.kind = 'shared'), 0),
        'page', coalesce(sum(used.uses) filter (where used.kind = 'page'), 0))
      from core.webtools_usage_counts used where used.day >= first_day),
    -- What is on the boards of the projects that exist now.
    'tools', coalesce((
      select jsonb_object_agg(kind, n) from (
        select coalesce(object->>'type', 'other') kind, count(*) n
        from core.tactics_projects project,
          jsonb_array_elements(case when jsonb_typeof(project.document->'boards') = 'array'
            then project.document->'boards' else '[]'::jsonb end) board,
          jsonb_array_elements(case when jsonb_typeof(board->'frames') = 'array'
            then board->'frames' else '[]'::jsonb end) frame,
          jsonb_array_elements(case when jsonb_typeof(frame->'objects') = 'array'
            then frame->'objects' else '[]'::jsonb end) object
        where (object->>'type') is null or (object->>'type') ~ '^[a-z_-]{1,30}$'
        group by 1) types), '{}'::jsonb),
    'boards', (
      select jsonb_build_object(
        'total', count(*),
        'animated', count(*) filter (where frames > 1),
        'frames', coalesce(sum(frames), 0),
        'view_full', count(*) filter (where view = 'full'),
        'view_attack', count(*) filter (where view = 'attack'),
        'view_defend', count(*) filter (where view = 'defend'),
        'view_empty', count(*) filter (where view = 'empty'))
      from (
        select board->>'view' as view,
          case when jsonb_typeof(board->'frames') = 'array' then jsonb_array_length(board->'frames') else 0 end frames
        from core.tactics_projects project,
          jsonb_array_elements(case when jsonb_typeof(project.document->'boards') = 'array'
            then project.document->'boards' else '[]'::jsonb end) board) boards),
    'library', jsonb_build_object(
      'starters', (select count(*) from core.tactics_shared_items shared
        where shared.owner_id is null and not shared.hidden),
      'templates', (select count(*) from core.tactics_templates template),
      'favorites', (select count(*) from core.tactics_favorites favorite),
      'folders', (select count(*) from core.tactics_folders folder),
      'pinned', (select count(*) from core.tactics_project_pins pin),
      'versions_in_period', (select count(*) from core.tactics_project_versions version
        where version.created_at >= since)),
    'live_activity', jsonb_build_object(
      'messages_in_period', (select count(*) from core.tactics_live_messages message
        where message.created_at >= since),
      'questions_in_period', (select count(*) from core.tactics_live_questions question
        where question.created_at >= since),
      'answers_in_period', (select count(*) from core.tactics_live_answers answer
        where answer.updated_at >= since),
      'drawings_in_period', (select count(*) from core.tactics_live_strokes stroke
        where stroke.created_at >= since)),
    'rankings', jsonb_build_object(
      'pages', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'value', n) order by n desc, key)
        from (select used.key, sum(used.uses) n from core.webtools_usage_counts used
          where used.kind = 'page' and used.day >= first_day group by 1 order by 2 desc, 1 limit 15) pages), '[]'::jsonb),
      'starters', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'value', n) order by n desc, key)
        from (select used.key, sum(used.uses) n from core.webtools_usage_counts used
          where used.kind = 'starter' and used.day >= first_day group by 1 order by 2 desc, 1 limit 15) starters), '[]'::jsonb),
      'shared', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'label', title, 'value', n) order by n desc, title)
        from (select used.key, shared.title, sum(used.uses) n from core.webtools_usage_counts used
          join core.tactics_shared_items shared on shared.id::text = used.key
          where used.kind = 'shared' and used.day >= first_day and not shared.hidden
          group by 1, 2 order by 3 desc, 2 limit 10) shared), '[]'::jsonb),
      'favorites', coalesce((select jsonb_agg(jsonb_build_object('key', id, 'label', title, 'value', n) order by n desc, title)
        from (select shared.id, shared.title, count(*) n from core.tactics_favorites favorite
          join core.tactics_shared_items shared on shared.id = favorite.shared_item_id
          where not shared.hidden
          group by 1, 2 order by 3 desc, 2 limit 10) favorites), '[]'::jsonb)),
    'daily_more', (
      select coalesce(jsonb_agg(jsonb_build_object(
          'day', calendar.day,
          'active', (select count(*) from core.webtools_activity_days active where active.day = calendar.day),
          'page_views', (select coalesce(sum(used.uses), 0) from core.webtools_usage_counts used
            where used.kind = 'page' and used.day = calendar.day),
          'uses', (select coalesce(sum(used.uses), 0) from core.webtools_usage_counts used
            where used.kind <> 'page' and used.day = calendar.day))
        order by calendar.day), '[]'::jsonb)
      from (select generate_series(first_day, today, interval '1 day')::date as day) calendar)
  );
end
$$;

create or replace function api.get_tacticsboard_usage_for_server(period_days integer default 30)
returns jsonb language sql stable security invoker set search_path = ''
as $$select internal.get_tacticsboard_usage_for_server(period_days)
  || internal.get_tacticsboard_usage_more_for_server(period_days)$$;

create or replace function api.record_webtools_presence()
returns void language sql security invoker set search_path = ''
as $$select internal.record_webtools_presence_for_actor()$$;

create or replace function api.record_webtools_use(kind text, key text)
returns void language sql security invoker set search_path = ''
as $$select internal.record_webtools_use_for_actor(kind, key)$$;

revoke all on function
  internal.webtools_actor_counts(),
  internal.record_webtools_presence_for_actor(),
  internal.record_webtools_use_for_actor(text, text),
  internal.get_tacticsboard_usage_more_for_server(integer),
  api.record_webtools_presence(),
  api.record_webtools_use(text, text)
from public, anon, authenticated;

grant execute on function
  internal.webtools_actor_counts(),
  internal.record_webtools_presence_for_actor(),
  internal.record_webtools_use_for_actor(text, text),
  api.record_webtools_presence(),
  api.record_webtools_use(text, text)
to authenticated;

grant execute on function internal.get_tacticsboard_usage_more_for_server(integer) to service_role;

notify pgrst, 'reload schema';
