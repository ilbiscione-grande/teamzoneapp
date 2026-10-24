-- Decision package 12, step 1: the match live on the team's public page.
-- A team chooses whether its published matches are reported live (PLM-03,
-- off by default); a match can follow that or be switched on or off. The
-- public projection holds the score, the clock and the match's events
-- (PLM-04: goals, shots, saves, penalties, cards, substitutions, injuries;
-- never notes, counters, plans or the line-up) and is written again after
-- every change to the match (PLM-06). A player is named only with an
-- active name consent (PLM-01); otherwise the name never leaves the
-- database. Without live reporting, or once the event or the team is no
-- longer published, the projection is removed (PLM-09). After full time it
-- stays as the match's course (PLM-05).

alter table core.team_publication_settings add column live_reporting boolean not null default false;
-- Null follows the team.
alter table core.event_publication_settings add column live_reporting boolean;

create table public_api.match_live_projections (
  event_public_id uuid primary key references public_api.event_projections(public_id) on delete cascade,
  state text not null check (state in ('live', 'completed')),
  score_us integer not null check (score_us >= 0),
  score_opponent integer not null check (score_opponent >= 0),
  clock jsonb not null,
  feed jsonb not null default '[]'::jsonb check (jsonb_typeof(feed) = 'array'),
  updated_at timestamptz not null default now()
);
alter table public_api.match_live_projections enable row level security;
create policy match_live_no_client_access on public_api.match_live_projections for all to authenticated using (false) with check (false);
revoke all on public_api.match_live_projections from public, anon, authenticated;

-- A person's name for the public page: only with an active name consent.
create or replace function internal.public_person_name(target_person_id uuid, target_club_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select person.display_name from core.club_people person
  where person.id = target_person_id and person.club_id = target_club_id
    and exists (select 1 from core.publication_consents consent
      where consent.club_id = target_club_id and consent.subject_club_person_id = target_person_id
        and consent.field_class = 'name' and consent.purpose_code = 'public_team_profile_v1'
        and consent.state = 'active' and consent.withdrawn_at is null and consent.expires_at > now())
$$;

-- Whether a match is reported live now: the match under way or played, the
-- event and the team published, and live reporting chosen.
create or replace function internal.match_live_enabled(target_event_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select workspace.state in ('live', 'completed')
      and setting.state = 'published'
      and team_setting.mode = 'published'
      and exists (select 1 from public_api.event_projections projection where projection.public_id = event_row.id)
      and coalesce(setting.live_reporting, team_setting.live_reporting)
    from core.events event_row
    join core.match_workspaces workspace on workspace.event_id = event_row.id
    join core.event_publication_settings setting on setting.event_id = event_row.id
    join core.team_publication_settings team_setting on team_setting.team_id = event_row.owning_team_id
    where event_row.id = target_event_id and event_row.event_type = 'match'), false)
$$;

-- Writes (or removes) the match's public projection.
create or replace function internal.project_live_match(target_event_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare workspace core.match_workspaces%rowtype; club uuid; feed_value jsonb; clock_value jsonb;
begin
  if not internal.match_live_enabled(target_event_id) then
    delete from public_api.match_live_projections where event_public_id = target_event_id;
    return;
  end if;
  select * into workspace from core.match_workspaces where event_id = target_event_id;
  select event_row.club_id into club from core.events event_row where event_row.id = target_event_id;
  select coalesce(jsonb_agg(jsonb_build_object(
      'n', ordered.n, 'minute', ordered.minute, 'type', ordered.fact_type, 'side', coalesce(ordered.side, 'us'),
      'result', case when ordered.fact_type = 'card' then ordered.detail->>'color' else ordered.detail->>'result' end,
      'player', case when coalesce(ordered.side, 'us') = 'us' then internal.public_person_name(ordered.club_person_id, club) end,
      'second', case when coalesce(ordered.side, 'us') = 'us' then internal.public_person_name(ordered.secondary_club_person_id, club) end)
      order by ordered.n), '[]'::jsonb)
    into feed_value
    from (select fact.*, row_number() over (order by fact.minute, fact.created_at, fact.id) n
      from core.match_facts fact
      where fact.event_id = target_event_id and fact.state = 'active'
        and fact.fact_type in ('goal', 'shot', 'save', 'penalty', 'card', 'substitution', 'injury')) ordered;
  clock_value := jsonb_build_object(
    'started_at', workspace.match_started_at, 'paused_at', workspace.match_paused_at,
    'paused_seconds', workspace.paused_seconds, 'completed_at', workspace.completed_at,
    'period_minutes', to_jsonb(workspace.period_minutes), 'current_period', workspace.current_period,
    -- The latest period end: its anchor keeps the clock on the scheduled minute.
    'period_end', (select fact.detail from core.match_facts fact
      where fact.event_id = target_event_id and fact.state = 'active' and fact.fact_type = 'period_end'
      order by fact.created_at desc, fact.id desc limit 1),
    'period_ended', workspace.match_paused_at is not null and exists (select 1 from core.match_facts fact
      where fact.event_id = target_event_id and fact.state = 'active' and fact.fact_type = 'period_end'
        and (fact.detail->>'period')::integer = workspace.current_period));
  insert into public_api.match_live_projections (event_public_id, state, score_us, score_opponent, clock, feed, updated_at)
  select target_event_id, workspace.state, coalesce(projection.score_us, 0), coalesce(projection.score_opponent, 0),
    clock_value, feed_value, now()
  from (select 1) one left join core.match_projections projection on projection.event_id = target_event_id
  on conflict (event_public_id) do update set state = excluded.state, score_us = excluded.score_us,
    score_opponent = excluded.score_opponent, clock = excluded.clock, feed = excluded.feed, updated_at = now();
end;
$$;

-- After every change to the match, its publication or a name consent.
create or replace function internal.project_live_match_trigger() returns trigger
language plpgsql security definer set search_path = '' as $$
declare target uuid;
begin
  if tg_table_name = 'team_publication_settings' then
    for target in select workspace.event_id from core.match_workspaces workspace
        join core.events event_row on event_row.id = workspace.event_id
        where event_row.owning_team_id = new.team_id loop
      perform internal.project_live_match(target);
    end loop;
  elsif tg_table_name = 'publication_consents' then
    for target in select distinct projection.event_public_id from public_api.match_live_projections projection
        join core.match_facts fact on fact.event_id = projection.event_public_id
        where fact.club_person_id = new.subject_club_person_id or fact.secondary_club_person_id = new.subject_club_person_id loop
      perform internal.project_live_match(target);
    end loop;
  else
    perform internal.project_live_match(new.event_id);
  end if;
  return null;
end;
$$;

create trigger project_live_on_fact after insert or update on core.match_facts
  for each row execute function internal.project_live_match_trigger();
create trigger project_live_on_workspace after update on core.match_workspaces
  for each row execute function internal.project_live_match_trigger();
create trigger project_live_on_score after insert or update on core.match_projections
  for each row execute function internal.project_live_match_trigger();
create trigger project_live_on_event_publication after insert or update on core.event_publication_settings
  for each row execute function internal.project_live_match_trigger();
create trigger project_live_on_team_publication after update of mode, live_reporting on core.team_publication_settings
  for each row execute function internal.project_live_match_trigger();
create trigger project_live_on_consent after insert or update on core.publication_consents
  for each row when (new.field_class = 'name') execute function internal.project_live_match_trigger();

-- The team's choice, for those who manage its publication.
create or replace function internal.get_team_live_reporting_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare club uuid; setting core.team_publication_settings%rowtype;
begin
  select team.club_id into club from core.teams team where team.id = target_team_id;
  if club is null or auth.uid() is null or not internal.actor_has_capability(club, target_team_id, 'publication.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select * into setting from core.team_publication_settings where team_id = target_team_id;
  return jsonb_build_object('enabled', coalesce(setting.live_reporting, false),
    'published', coalesce(setting.mode = 'published', false));
end;
$$;

create or replace function internal.set_team_live_reporting_for_actor(target_team_id uuid, enabled boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare club uuid; setting core.team_publication_settings%rowtype;
begin
  select team.club_id into club from core.teams team where team.id = target_team_id;
  if club is null or auth.uid() is null or not internal.actor_has_capability(club, target_team_id, 'publication.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if enabled is null then raise invalid_parameter_value using message = 'invalid_setting'; end if;
  update core.team_publication_settings set live_reporting = enabled
  where team_id = target_team_id returning * into setting;
  if setting.team_id is null then raise check_violation using message = 'team_not_publishable'; end if;
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision, metadata)
  values (club, auth.uid(), 'publication.team.live_reporting.v1', 'team', target_team_id, setting.revision,
    jsonb_build_object('live_reporting', enabled));
  return internal.get_team_live_reporting_for_actor(target_team_id);
end;
$$;

-- A match's choice: the team's default, the match's own (null follows the
-- team), and whether it is reported live now.
create or replace function internal.get_match_live_reporting_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events%rowtype; setting core.event_publication_settings%rowtype;
  team_setting core.team_publication_settings%rowtype;
begin
  select * into event_row from core.events where id = target_event_id;
  if event_row.id is null or auth.uid() is null or not internal.actor_can_read_event(target_event_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select * into setting from core.event_publication_settings where event_id = target_event_id;
  select * into team_setting from core.team_publication_settings where team_id = event_row.owning_team_id;
  return jsonb_build_object(
    'team_default', coalesce(team_setting.live_reporting, false),
    'match_choice', setting.live_reporting,
    'published', coalesce(setting.state = 'published', false) and coalesce(team_setting.mode = 'published', false),
    'live', exists (select 1 from public_api.match_live_projections projection where projection.event_public_id = target_event_id));
end;
$$;

create or replace function internal.set_match_live_reporting_for_actor(target_event_id uuid, choice boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare event_row core.events; setting core.event_publication_settings%rowtype;
begin
  event_row := internal.assert_match_manager(target_event_id);
  update core.event_publication_settings set live_reporting = choice
  where event_id = target_event_id and state = 'published' returning * into setting;
  if setting.event_id is null then raise check_violation using message = 'event_not_published'; end if;
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision, metadata)
  values (event_row.club_id, auth.uid(), 'publication.event.live_reporting.v1', 'event', target_event_id, setting.revision,
    jsonb_build_object('live_reporting', choice));
  return internal.get_match_live_reporting_for_actor(target_event_id);
end;
$$;

-- The public page's read: the team's reported matches, latest first, the
-- one under way among them, with the server's time for the clock.
create or replace function internal.public_team_live_matches(target_team_id uuid, ip_sha256_hex text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare rate jsonb; items jsonb;
begin
  if not internal.public_runtime_enabled() then
    return jsonb_build_object('available', false, 'items', '[]'::jsonb);
  end if;
  rate := internal.consume_public_rate_limit(ip_sha256_hex, 'read', null);
  if not (rate->>'allowed')::boolean then raise program_limit_exceeded using message = 'rate_limited'; end if;
  select coalesce(jsonb_agg(to_jsonb(page) order by page.starts_at desc, page.id desc), '[]'::jsonb) into items from (
    select e.public_id id, e.title, e.starts_at, l.state, l.score_us, l.score_opponent, l.clock, l.feed, l.updated_at
    from public_api.match_live_projections l join public_api.event_projections e on e.public_id = l.event_public_id
    join public_api.team_projections t on t.public_id = e.team_public_id join public_api.club_projections c on c.public_id = t.club_public_id
    where t.public_id = target_team_id and t.visibility = 'published' and c.visibility = 'published'
    order by e.starts_at desc, e.public_id desc limit 10
  ) page;
  return jsonb_build_object('available', true, 'server_now', now(), 'items', items);
end;
$$;

-- Existing matches: their projections as they stand.
do $$ declare target uuid;
begin
  for target in select event_id from core.match_workspaces loop
    perform internal.project_live_match(target);
  end loop;
end $$;

create or replace function api.get_team_live_reporting(target_team_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_team_live_reporting_for_actor(target_team_id) $$;
create or replace function api.set_team_live_reporting(target_team_id uuid, enabled boolean) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.set_team_live_reporting_for_actor(target_team_id, enabled) $$;
create or replace function api.get_match_live_reporting(target_event_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_match_live_reporting_for_actor(target_event_id) $$;
create or replace function api.set_match_live_reporting(target_event_id uuid, choice boolean) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.set_match_live_reporting_for_actor(target_event_id, choice) $$;
create or replace function api.public_team_live_matches(team_id uuid, ip_hash text) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.public_team_live_matches(team_id, ip_hash) $$;

revoke all on function
  internal.public_person_name(uuid, uuid), internal.match_live_enabled(uuid), internal.project_live_match(uuid),
  internal.project_live_match_trigger(),
  internal.get_team_live_reporting_for_actor(uuid), internal.set_team_live_reporting_for_actor(uuid, boolean),
  internal.get_match_live_reporting_for_actor(uuid), internal.set_match_live_reporting_for_actor(uuid, boolean),
  internal.public_team_live_matches(uuid, text),
  api.get_team_live_reporting(uuid), api.set_team_live_reporting(uuid, boolean),
  api.get_match_live_reporting(uuid), api.set_match_live_reporting(uuid, boolean),
  api.public_team_live_matches(uuid, text)
from public, anon, authenticated;
grant execute on function
  internal.get_team_live_reporting_for_actor(uuid), internal.set_team_live_reporting_for_actor(uuid, boolean),
  internal.get_match_live_reporting_for_actor(uuid), internal.set_match_live_reporting_for_actor(uuid, boolean),
  api.get_team_live_reporting(uuid), api.set_team_live_reporting(uuid, boolean),
  api.get_match_live_reporting(uuid), api.set_match_live_reporting(uuid, boolean)
to authenticated;
grant execute on function internal.public_team_live_matches(uuid, text), api.public_team_live_matches(uuid, text) to service_role;
notify pgrst, 'reload schema';
