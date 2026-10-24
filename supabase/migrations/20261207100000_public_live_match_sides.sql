-- Decision package 12, step 3: the live report names the opponent and says
-- where the match was played ("gästernas målvakt", "på hemmaplan"), so
-- the projection carries the event's opponent and home or away; both are
-- already part of the published match's title. Otherwise as in
-- 20261207090000.

alter table public_api.match_live_projections
  add column opponent_name text check (opponent_name is null or length(opponent_name) <= 160),
  add column home_away text check (home_away is null or home_away in ('home', 'away'));

-- Writes (or removes) the match's public projection.
create or replace function internal.project_live_match(target_event_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare workspace core.match_workspaces%rowtype; club uuid; opponent text; venue text; feed_value jsonb; clock_value jsonb;
begin
  if not internal.match_live_enabled(target_event_id) then
    delete from public_api.match_live_projections where event_public_id = target_event_id;
    return;
  end if;
  select * into workspace from core.match_workspaces where event_id = target_event_id;
  select event_row.club_id, left(nullif(btrim(event_row.opponent_name), ''), 160),
    case when event_row.home_away in ('home', 'away') then event_row.home_away end into club, opponent, venue
    from core.events event_row where event_row.id = target_event_id;
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
  insert into public_api.match_live_projections (event_public_id, state, score_us, score_opponent, clock, feed,
    opponent_name, home_away, updated_at)
  select target_event_id, workspace.state, coalesce(projection.score_us, 0), coalesce(projection.score_opponent, 0),
    clock_value, feed_value, opponent, venue, now()
  from (select 1) one left join core.match_projections projection on projection.event_id = target_event_id
  on conflict (event_public_id) do update set state = excluded.state, score_us = excluded.score_us,
    score_opponent = excluded.score_opponent, clock = excluded.clock, feed = excluded.feed,
    opponent_name = excluded.opponent_name, home_away = excluded.home_away, updated_at = now();
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
    select e.public_id id, e.title, e.starts_at, l.state, l.score_us, l.score_opponent, l.clock, l.feed, l.opponent_name, l.home_away, l.updated_at
    from public_api.match_live_projections l join public_api.event_projections e on e.public_id = l.event_public_id
    join public_api.team_projections t on t.public_id = e.team_public_id join public_api.club_projections c on c.public_id = t.club_public_id
    where t.public_id = target_team_id and t.visibility = 'published' and c.visibility = 'published'
    order by e.starts_at desc, e.public_id desc limit 10
  ) page;
  return jsonb_build_object('available', true, 'server_now', now(), 'items', items);
end;
$$;

do $$ declare target uuid;
begin
  for target in select event_public_id from public_api.match_live_projections loop
    perform internal.project_live_match(target);
  end loop;
end $$;

notify pgrst, 'reload schema';
