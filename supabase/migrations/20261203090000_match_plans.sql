-- Match module, step 1 (decision package 11, MFD-04/05): the match plan, one
-- per match event, and the modules' attachments. The plan is Match Space
-- v2's own core.match_plans (S07): its tactics, set-piece and key-opponent
-- notes and its revision, shared with the v2 save_plan command. Each part
-- can now be shown to the players, who see the shown parts once the plan is
-- published; the opponent is hidden by default. The module saves the plan
-- with the event's match.plan capability (preparing), not match.live
-- (running the match), so its save is its own, on the same revision.
-- Attachments are a model shared by the modules' core objects: links now,
-- Tacticsboard boards later; the event's own files stay under Förberedelser
-- and are not copied here.

alter table core.match_plans
  add column tactics_visible boolean not null default true,
  add column set_pieces_visible boolean not null default true,
  add column opponent_visible boolean not null default false,
  add column published boolean not null default false;

create table core.module_attachments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  owner_kind text not null check (owner_kind in ('match_plan')),
  owner_id uuid not null,
  kind text not null check (kind in ('link')),
  title text not null check (length(btrim(title)) between 1 and 120),
  url text check (url ~ '^https://[^[:space:]]{3,}$' and length(url) <= 2000),
  visible_to_players boolean not null default false,
  position integer not null default 0,
  created_by uuid references core.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  check (kind <> 'link' or url is not null)
);
create index module_attachments_owner on core.module_attachments (owner_kind, owner_id, position);

alter table core.module_attachments enable row level security;
revoke all on core.module_attachments from public, anon, authenticated;

-- The match's v2 workspace, which the plan belongs to: made as
-- internal.ensure_match_workspace makes it, but for those who prepare the
-- match as well as those who run it.
create or replace function internal.match_plan_workspace(event_row core.events)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into core.match_workspaces (event_id, club_id, team_id, updated_by, period_minutes)
  values (event_row.id, event_row.club_id, event_row.owning_team_id, auth.uid(),
    coalesce((select settings.period_minutes from core.event_match_settings settings where settings.event_id = event_row.id),
      internal.match_format_period_minutes((select team.match_format from core.teams team where team.id = event_row.owning_team_id))))
  on conflict (event_id) do nothing;
  insert into core.match_projections (event_id) values (event_row.id) on conflict (event_id) do nothing;
end;
$$;

-- The match event the plan is for, and whether the one asking may edit its plan.
create or replace function internal.match_plan_event(target_event_id uuid)
returns core.events language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events;
begin
  select * into event_row from core.events where id = target_event_id;
  if event_row.id is null or event_row.event_type <> 'match' or auth.uid() is null
    or not internal.actor_can_read_event(target_event_id)
    or not internal.module_allows_read(event_row.club_id, 'module.match_workspace') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return event_row;
end;
$$;

create or replace function internal.match_plan_can_edit(event_row core.events)
returns boolean language sql stable security definer set search_path = '' as $$
  select internal.module_allows_write(event_row.club_id, 'module.match_workspace')
    and internal.actor_has_event_capability(event_row.id, 'match.plan')
    and event_row.archived_at is null
$$;

-- The plan as its reader may see it: everything for those who edit it; for
-- the players the shown parts and links of a published plan, else nothing.
create or replace function internal.match_plan_json(event_row core.events, can_edit boolean)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare plan core.match_plans;
begin
  select * into plan from core.match_plans where event_id = event_row.id;
  if not can_edit and (plan.event_id is null or not plan.published) then return null; end if;
  return jsonb_build_object(
    'event_id', event_row.id, 'can_edit', can_edit,
    'opponent_name', event_row.opponent_name, 'home_away', event_row.home_away, 'starts_at', event_row.starts_at,
    'published', coalesce(plan.published, false), 'revision', coalesce(plan.revision, 0), 'updated_at', plan.updated_at,
    'sections', jsonb_build_object(
      'tactics', case when can_edit or plan.tactics_visible
        then jsonb_build_object('text', coalesce(plan.tactics_notes, ''), 'visible', coalesce(plan.tactics_visible, true)) end,
      'set_pieces', case when can_edit or plan.set_pieces_visible
        then jsonb_build_object('text', coalesce(plan.set_pieces_notes, ''), 'visible', coalesce(plan.set_pieces_visible, true)) end,
      'opponent', case when can_edit or plan.opponent_visible
        then jsonb_build_object('text', coalesce(plan.key_opponents_notes, ''), 'visible', coalesce(plan.opponent_visible, false)) end
    ),
    'links', coalesce((
      select jsonb_agg(jsonb_build_object('id', link.id, 'title', link.title, 'url', link.url, 'visible', link.visible_to_players)
        order by link.position, link.created_at)
      from core.module_attachments link
      where link.owner_kind = 'match_plan' and link.owner_id = event_row.id and (can_edit or link.visible_to_players)
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function internal.get_match_plan_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events;
begin
  event_row := internal.match_plan_event(target_event_id);
  return internal.match_plan_json(event_row, internal.match_plan_can_edit(event_row));
end;
$$;

-- Saves the plan when the revision is the one read (0 for a new plan); the new revision back.
create or replace function internal.save_match_plan_for_actor(
  target_event_id uuid, expected_revision bigint, tactics_text text, set_pieces_text text, opponent_text text,
  show_tactics boolean, show_set_pieces boolean, show_opponent boolean, is_published boolean
) returns bigint language plpgsql security definer set search_path = '' as $$
declare
  event_row core.events;
  current_revision bigint;
  saved bigint;
begin
  event_row := internal.match_plan_event(target_event_id);
  if not internal.match_plan_can_edit(event_row) then raise insufficient_privilege using message = 'not_allowed'; end if;
  if length(coalesce(tactics_text, '')) > 8000 or length(coalesce(set_pieces_text, '')) > 8000 or length(coalesce(opponent_text, '')) > 8000
    or show_tactics is null or show_set_pieces is null or show_opponent is null or is_published is null then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(event_row.id::text, 0));
  select revision into current_revision from core.match_plans where event_id = event_row.id for update;
  if coalesce(current_revision, 0) <> coalesce(expected_revision, 0) then raise serialization_failure using message = 'stale_revision'; end if;
  perform internal.match_plan_workspace(event_row);
  insert into core.match_plans (event_id, revision, tactics_notes, set_pieces_notes, key_opponents_notes,
    tactics_visible, set_pieces_visible, opponent_visible, published, updated_by)
  values (event_row.id, 1, coalesce(tactics_text, ''), coalesce(set_pieces_text, ''), coalesce(opponent_text, ''),
    show_tactics, show_set_pieces, show_opponent, is_published, auth.uid())
  on conflict (event_id) do update set tactics_notes = excluded.tactics_notes, set_pieces_notes = excluded.set_pieces_notes,
    key_opponents_notes = excluded.key_opponents_notes, tactics_visible = excluded.tactics_visible,
    set_pieces_visible = excluded.set_pieces_visible, opponent_visible = excluded.opponent_visible,
    published = excluded.published, revision = core.match_plans.revision + 1, updated_by = excluded.updated_by, updated_at = now()
  returning revision into saved;
  return saved;
end;
$$;

-- A link on the plan (a video, a scouting page, a document); at most 30.
create or replace function internal.add_match_plan_link_for_actor(target_event_id uuid, link_title text, link_url text, show_players boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  event_row core.events;
  added core.module_attachments;
begin
  event_row := internal.match_plan_event(target_event_id);
  if not internal.match_plan_can_edit(event_row) then raise insufficient_privilege using message = 'not_allowed'; end if;
  if length(btrim(coalesce(link_title, ''))) not between 1 and 120 or coalesce(btrim(link_url), '') !~ '^https://[^[:space:]]{3,}$'
    or length(btrim(link_url)) > 2000 then
    raise invalid_parameter_value using message = 'invalid_link';
  end if;
  if (select count(*) from core.module_attachments where owner_kind = 'match_plan' and owner_id = event_row.id) >= 30 then
    raise check_violation using message = 'too_many_links';
  end if;
  insert into core.module_attachments (club_id, owner_kind, owner_id, kind, title, url, visible_to_players, position, created_by)
  values (event_row.club_id, 'match_plan', event_row.id, 'link', btrim(link_title), btrim(link_url), coalesce(show_players, false),
    coalesce((select max(position) + 1 from core.module_attachments where owner_kind = 'match_plan' and owner_id = event_row.id), 0), auth.uid())
  returning * into added;
  return jsonb_build_object('id', added.id, 'title', added.title, 'url', added.url, 'visible', added.visible_to_players);
end;
$$;

-- A link shown to the players or not, or removed (show_players null).
create or replace function internal.change_match_plan_link_for_actor(target_link_id uuid, show_players boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  link core.module_attachments;
  event_row core.events;
begin
  select * into link from core.module_attachments where id = target_link_id and owner_kind = 'match_plan';
  if link.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  event_row := internal.match_plan_event(link.owner_id);
  if not internal.match_plan_can_edit(event_row) then raise insufficient_privilege using message = 'not_allowed'; end if;
  if show_players is null then delete from core.module_attachments where id = link.id;
  else update core.module_attachments set visible_to_players = show_players where id = link.id; end if;
end;
$$;

-- The Match module's list: a team's matches in a period with how far each is prepared.
create or replace function internal.list_module_matches_for_actor(target_team_id uuid, from_time timestamptz, to_time timestamptz)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare club uuid;
begin
  select team.club_id into club from core.teams team where team.id = target_team_id;
  if club is null or auth.uid() is null or not internal.actor_has_capability(club, target_team_id, 'match.plan')
    or not internal.module_allows_read(club, 'module.match_workspace') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if from_time is null or to_time is null or to_time <= from_time or to_time - from_time > interval '400 days' then
    raise invalid_parameter_value using message = 'invalid_period';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'event_id', event_row.id, 'title', event_row.title, 'starts_at', event_row.starts_at, 'state', event_row.state,
      'opponent_name', event_row.opponent_name, 'home_away', event_row.home_away,
      'plan', case when plan.event_id is null then 'none' when plan.published then 'published' else 'draft' end,
      'lineup', (select case when lineup.event_id is null then 'none' when lineup.published then 'published' else 'draft' end
                 from (select 1) one left join core.event_lineups lineup on lineup.event_id = event_row.id)
    ) order by event_row.starts_at)
    from core.events event_row
    left join core.match_plans plan on plan.event_id = event_row.id
    where event_row.owning_team_id = target_team_id and event_row.event_type = 'match' and event_row.archived_at is null
      and event_row.starts_at >= from_time and event_row.starts_at < to_time
  ), '[]'::jsonb);
end;
$$;

create or replace function api.get_match_plan(target_event_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_match_plan_for_actor(target_event_id) $$;
create or replace function api.save_match_plan(
  target_event_id uuid, expected_revision bigint, tactics_text text, set_pieces_text text, opponent_text text,
  show_tactics boolean, show_set_pieces boolean, show_opponent boolean, is_published boolean
) returns bigint language sql security invoker set search_path = '' as $$
  select internal.save_match_plan_for_actor(target_event_id, expected_revision, tactics_text, set_pieces_text, opponent_text,
    show_tactics, show_set_pieces, show_opponent, is_published) $$;
create or replace function api.add_match_plan_link(target_event_id uuid, link_title text, link_url text, show_players boolean) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.add_match_plan_link_for_actor(target_event_id, link_title, link_url, show_players) $$;
create or replace function api.change_match_plan_link(target_link_id uuid, show_players boolean) returns void
language sql security invoker set search_path = '' as $$ select internal.change_match_plan_link_for_actor(target_link_id, show_players) $$;
create or replace function api.list_module_matches(target_team_id uuid, from_time timestamptz, to_time timestamptz) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.list_module_matches_for_actor(target_team_id, from_time, to_time) $$;

revoke all on function
  internal.match_plan_workspace(core.events), internal.match_plan_event(uuid), internal.match_plan_can_edit(core.events), internal.match_plan_json(core.events, boolean),
  internal.get_match_plan_for_actor(uuid), internal.save_match_plan_for_actor(uuid, bigint, text, text, text, boolean, boolean, boolean, boolean),
  internal.add_match_plan_link_for_actor(uuid, text, text, boolean), internal.change_match_plan_link_for_actor(uuid, boolean),
  internal.list_module_matches_for_actor(uuid, timestamptz, timestamptz),
  api.get_match_plan(uuid), api.save_match_plan(uuid, bigint, text, text, text, boolean, boolean, boolean, boolean),
  api.add_match_plan_link(uuid, text, text, boolean), api.change_match_plan_link(uuid, boolean),
  api.list_module_matches(uuid, timestamptz, timestamptz)
from public, anon, authenticated;
grant execute on function
  internal.match_plan_event(uuid), internal.match_plan_can_edit(core.events), internal.match_plan_json(core.events, boolean),
  internal.get_match_plan_for_actor(uuid), internal.save_match_plan_for_actor(uuid, bigint, text, text, text, boolean, boolean, boolean, boolean),
  internal.add_match_plan_link_for_actor(uuid, text, text, boolean), internal.change_match_plan_link_for_actor(uuid, boolean),
  internal.list_module_matches_for_actor(uuid, timestamptz, timestamptz),
  api.get_match_plan(uuid), api.save_match_plan(uuid, bigint, text, text, text, boolean, boolean, boolean, boolean),
  api.add_match_plan_link(uuid, text, text, boolean), api.change_match_plan_link(uuid, boolean),
  api.list_module_matches(uuid, timestamptz, timestamptz)
to authenticated;
