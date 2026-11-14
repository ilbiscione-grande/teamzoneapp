-- Supportens statistik: mer om ett kort.
--
-- Each card on Support -> Statistik can be opened (product owner,
-- 2026-11-14). api.get_usage_detail_for_support(metric, item, period_days)
-- returns, for the chosen period, one value per day and a few breakdowns
-- (by type, app, status, or the clubs with the most). Counts only; the
-- only names are club names, which support already sees under Klubbar.
-- Support administrators only, like the statistics themselves.

-- {key: n} -> [{key, value}], largest first.
create or replace function internal.usage_rows(pairs jsonb)
returns jsonb language sql immutable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', pair.key, 'value', pair.value::bigint)
    order by pair.value::bigint desc, pair.key), '[]'::jsonb)
  from jsonb_each_text(coalesce(pairs, '{}'::jsonb)) pair
$$;

-- {club_id: n} -> [{key, label, value}] for the 15 largest, with club names.
create or replace function internal.usage_club_rows(pairs jsonb)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', club.id, 'label', club.name, 'value', top.n)
    order by top.n desc, club.name), '[]'::jsonb)
  from (select pair.key::uuid club_id, pair.value::bigint n
    from jsonb_each_text(coalesce(pairs, '{}'::jsonb)) pair
    order by pair.value::bigint desc limit 15) top
  join core.clubs club on club.id = top.club_id
$$;

create or replace function internal.get_usage_detail_for_support_for_actor(
  metric text, item text, period_days integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  today date := (now() at time zone 'Europe/Stockholm')::date;
  days integer := greatest(7, least(coalesce(period_days, 30), 365));
  first_day date;
  since timestamptz;
  window_start date;
  counts jsonb := '{}'::jsonb;
  groups jsonb := '[]'::jsonb;
  total bigint;
  linked bigint;
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  first_day := today - (days - 1);
  since := first_day::timestamp at time zone 'Europe/Stockholm';

  if metric = 'accounts' and item in ('total', 'new') then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (profile.created_at at time zone 'Europe/Stockholm')::date as day, count(*) n
      from core.profiles profile where profile.created_at >= since group by 1) g;
    select count(*), count(*) filter (where exists (select 1 from core.person_account_links link
        where link.profile_id = profile.id and link.state = 'active'))
      into total, linked
    from core.profiles profile where item = 'total' or profile.created_at >= since;
    groups := jsonb_build_array(
      jsonb_build_object('group', 'by_type', 'rows', internal.usage_rows((
        select jsonb_object_agg(kind, n) from (
          select coalesce(profile.account_type, 'unknown') kind, count(*) n from core.profiles profile
          where item = 'total' or profile.created_at >= since group by 1) g))),
      jsonb_build_object('group', 'linked', 'rows', internal.usage_rows(
        jsonb_build_object('linked', linked, 'not_linked', total - linked))));

  elsif metric = 'accounts' and item = 'linked' then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (link.created_at at time zone 'Europe/Stockholm')::date as day, count(distinct link.profile_id) n
      from core.person_account_links link where link.created_at >= since and link.state = 'active' group by 1) g;
    groups := jsonb_build_array(jsonb_build_object('group', 'clubs', 'rows', internal.usage_club_rows((
      select jsonb_object_agg(club_id, n) from (
        select link.club_id, count(distinct link.profile_id) n from core.person_account_links link
        where link.state = 'active' group by 1) g))));

  elsif metric = 'account_type' then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (profile.created_at at time zone 'Europe/Stockholm')::date as day, count(*) n
      from core.profiles profile
      where profile.created_at >= since and coalesce(profile.account_type, 'unknown') = item group by 1) g;
    select count(*), count(*) filter (where exists (select 1 from core.person_account_links link
        where link.profile_id = profile.id and link.state = 'active'))
      into total, linked
    from core.profiles profile where coalesce(profile.account_type, 'unknown') = item;
    groups := jsonb_build_array(jsonb_build_object('group', 'linked', 'rows', internal.usage_rows(
      jsonb_build_object('linked', linked, 'not_linked', total - linked))));

  elsif metric = 'active' and item in ('today', 'last_7_days', 'last_30_days', 'in_period') then
    window_start := case item when 'today' then today when 'last_7_days' then today - 6
      when 'last_30_days' then today - 29 else first_day end;
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select activity.day as day, count(*) n from core.profile_activity_days activity
      where activity.day >= first_day group by 1) g;
    groups := jsonb_build_array(
      jsonb_build_object('group', 'by_app', 'rows', internal.usage_rows((
        select jsonb_object_agg(app, n) from (
          select activity.app, count(distinct activity.profile_id) n from core.profile_activity_apps activity
          where activity.day >= window_start group by 1) g))),
      jsonb_build_object('group', 'clubs', 'rows', internal.usage_club_rows((
        select jsonb_object_agg(club_id, n) from (
          select link.club_id, count(distinct activity.profile_id) n from core.profile_activity_days activity
          join core.person_account_links link on link.profile_id = activity.profile_id and link.state = 'active'
          where activity.day >= window_start group by 1) g))));

  elsif metric = 'app' then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select activity.day as day, count(*) n from core.profile_activity_apps activity
      where activity.day >= first_day and activity.app = item group by 1) g;
    groups := jsonb_build_array(jsonb_build_object('group', 'clubs', 'rows', internal.usage_club_rows((
      select jsonb_object_agg(club_id, n) from (
        select link.club_id, count(distinct activity.profile_id) n from core.profile_activity_apps activity
        join core.person_account_links link on link.profile_id = activity.profile_id and link.state = 'active'
        where activity.day >= first_day and activity.app = item group by 1) g))));

  elsif metric = 'clubs' and item in ('active', 'official', 'new_in_period') then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (club.created_at at time zone 'Europe/Stockholm')::date as day, count(*) n from core.clubs club
      where club.created_at >= since and (item <> 'official' or club.verification_status = 'official')
      group by 1) g;
    if item = 'active' then
      groups := jsonb_build_array(jsonb_build_object('group', 'by_verification', 'rows', internal.usage_rows((
        select jsonb_object_agg(verification_status, n) from (
          select club.verification_status, count(*) n from core.clubs club where club.status = 'active'
          group by 1) g))));
    end if;
    groups := groups || jsonb_build_array(jsonb_build_object('group', 'clubs_by_people', 'rows',
      internal.usage_club_rows((select jsonb_object_agg(id, n) from (
        select club.id, (select count(*) from core.club_people person
          where person.club_id = club.id and person.status = 'active') n
        from core.clubs club
        where (item = 'new_in_period' and club.created_at >= since)
          or (item = 'active' and club.status = 'active')
          or (item = 'official' and club.status = 'active' and club.verification_status = 'official')) g))));

  elsif metric = 'clubs' and item = 'teams' then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (team.created_at at time zone 'Europe/Stockholm')::date as day, count(*) n from core.teams team
      where team.created_at >= since group by 1) g;
    groups := jsonb_build_array(
      jsonb_build_object('group', 'by_sport', 'rows', internal.usage_rows((
        select jsonb_object_agg(sport, n) from (
          select coalesce(team.sport, 'unknown') sport, count(*) n from core.teams team
          where team.status = 'active' group by 1) g))),
      jsonb_build_object('group', 'clubs', 'rows', internal.usage_club_rows((
        select jsonb_object_agg(club_id, n) from (
          select team.club_id, count(*) n from core.teams team where team.status = 'active' group by 1) g))));

  elsif metric = 'clubs' and item = 'people' then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (person.created_at at time zone 'Europe/Stockholm')::date as day, count(*) n from core.club_people person
      where person.created_at >= since group by 1) g;
    groups := jsonb_build_array(jsonb_build_object('group', 'clubs', 'rows', internal.usage_club_rows((
      select jsonb_object_agg(club_id, n) from (
        select person.club_id, count(*) n from core.club_people person where person.status = 'active'
        group by 1) g))));

  elsif metric = 'area' and item = 'events_created' then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (row_.created_at at time zone 'Europe/Stockholm')::date as day, count(*) n from core.events row_
      where row_.created_at >= since group by 1) g;
    groups := jsonb_build_array(
      jsonb_build_object('group', 'by_event_type', 'rows', internal.usage_rows((
        select jsonb_object_agg(event_type, n) from (select row_.event_type, count(*) n from core.events row_
          where row_.created_at >= since group by 1) g))),
      jsonb_build_object('group', 'clubs', 'rows', internal.usage_club_rows((
        select jsonb_object_agg(club_id, n) from (select row_.club_id, count(*) n from core.events row_
          where row_.created_at >= since group by 1) g))));

  elsif metric = 'area' and item = 'callup_answers' then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (row_.created_at at time zone 'Europe/Stockholm')::date as day, count(*) n from core.callup_responses row_
      where row_.created_at >= since group by 1) g;
    groups := jsonb_build_array(
      jsonb_build_object('group', 'by_response', 'rows', internal.usage_rows((
        select jsonb_object_agg(response, n) from (select row_.response, count(*) n
          from core.callup_responses row_ where row_.created_at >= since group by 1) g))),
      jsonb_build_object('group', 'clubs', 'rows', internal.usage_club_rows((
        select jsonb_object_agg(club_id, n) from (select row_.club_id, count(*) n
          from core.callup_responses row_ where row_.created_at >= since group by 1) g))));

  elsif metric = 'area' and item = 'attendance_recorded' then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (row_.recorded_at at time zone 'Europe/Stockholm')::date as day, count(*) n from core.attendance_facts row_
      where row_.recorded_at >= since group by 1) g;
    groups := jsonb_build_array(
      jsonb_build_object('group', 'by_status', 'rows', internal.usage_rows((
        select jsonb_object_agg(status, n) from (select row_.status, count(*) n
          from core.attendance_facts row_ where row_.recorded_at >= since group by 1) g))),
      jsonb_build_object('group', 'clubs', 'rows', internal.usage_club_rows((
        select jsonb_object_agg(club_id, n) from (select row_.club_id, count(*) n
          from core.attendance_facts row_ where row_.recorded_at >= since group by 1) g))));

  elsif metric = 'area' and item = 'messages_sent' then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (row_.created_at at time zone 'Europe/Stockholm')::date as day, count(*) n from core.messages row_
      where row_.created_at >= since group by 1) g;
    groups := jsonb_build_array(jsonb_build_object('group', 'clubs', 'rows', internal.usage_club_rows((
      select jsonb_object_agg(club_id, n) from (select row_.club_id, count(*) n from core.messages row_
        where row_.created_at >= since and row_.club_id is not null group by 1) g))));

  elsif metric = 'area' and item = 'tactics_projects_created' then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (row_.created_at at time zone 'Europe/Stockholm')::date as day, count(*) n from core.tactics_projects row_
      where row_.created_at >= since group by 1) g;
    groups := jsonb_build_array(
      jsonb_build_object('group', 'by_kind', 'rows', internal.usage_rows((
        select jsonb_object_agg(kind, n) from (select coalesce(row_.kind, 'unknown') kind, count(*) n
          from core.tactics_projects row_ where row_.created_at >= since group by 1) g))),
      jsonb_build_object('group', 'team_link', 'rows', internal.usage_rows((
        select jsonb_object_agg(linked_, n) from (
          select case when row_.teamzone_team_id is null then 'not_linked' else 'linked' end linked_, count(*) n
          from core.tactics_projects row_ where row_.created_at >= since group by 1) g))));

  elsif metric = 'area' and item = 'tactics_live_sessions' then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (row_.created_at at time zone 'Europe/Stockholm')::date as day, count(*) n
      from core.tactics_live_sessions row_ where row_.created_at >= since group by 1) g;
    groups := jsonb_build_array(jsonb_build_object('group', 'by_status', 'rows', internal.usage_rows((
      select jsonb_object_agg(status, n) from (select row_.status, count(*) n
        from core.tactics_live_sessions row_ where row_.created_at >= since group by 1) g))));

  elsif metric = 'area' and item = 'bookings_created' then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (row_.created_at at time zone 'Europe/Stockholm')::date as day, count(*) n
      from core.booking_bookings row_ where row_.created_at >= since group by 1) g;
    groups := jsonb_build_array(jsonb_build_object('group', 'by_status', 'rows', internal.usage_rows((
      select jsonb_object_agg(status, n) from (select row_.status, count(*) n
        from core.booking_bookings row_ where row_.created_at >= since group by 1) g))));

  elsif metric = 'subscription' then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (row_.created_at at time zone 'Europe/Stockholm')::date as day, count(*) n
      from core.personal_billing_subscriptions row_
      where row_.created_at >= since and row_.entitlement_key = item group by 1) g;
    groups := jsonb_build_array(
      jsonb_build_object('group', 'by_interval', 'rows', internal.usage_rows((
        select jsonb_object_agg(billing_interval, n) from (
          select coalesce(row_.billing_interval, 'unknown') billing_interval, count(*) n
          from core.personal_billing_subscriptions row_
          where row_.entitlement_key = item and row_.state = 'active' group by 1) g))),
      jsonb_build_object('group', 'by_state', 'rows', internal.usage_rows((
        select jsonb_object_agg(state_, n) from (
          select case when row_.state = 'active' and row_.cancel_at_period_end then 'ending'
            else row_.state end state_, count(*) n
          from core.personal_billing_subscriptions row_ where row_.entitlement_key = item group by 1) g))));

  elsif metric = 'push' then
    select coalesce(jsonb_object_agg(day, n), '{}') into counts from (
      select (endpoint.created_at at time zone 'Europe/Stockholm')::date as day, count(*) n
      from internal.push_endpoint_tokens token
      join core.notification_endpoints endpoint on endpoint.id = token.endpoint_id
      where endpoint.created_at >= since and token.platform = item group by 1) g;
    groups := jsonb_build_array(jsonb_build_object('group', 'last_seen', 'rows', internal.usage_rows((
      select jsonb_object_agg(seen, n) from (
        select case when token.last_seen_at >= now() - interval '30 days' then 'seen_30_days'
          else 'not_seen_30_days' end seen, count(*) n
        from internal.push_endpoint_tokens token
        join core.notification_endpoints endpoint on endpoint.id = token.endpoint_id
        where endpoint.state = 'active' and token.platform = item group by 1) g))));

  else
    raise invalid_parameter_value using message = 'unknown_metric';
  end if;

  return jsonb_build_object(
    'metric', metric, 'item', item, 'period_days', days, 'first_day', first_day, 'today', today,
    'daily', (select jsonb_agg(jsonb_build_object('day', series.day,
        'value', coalesce((counts ->> series.day::text)::bigint, 0)) order by series.day)
      from (select generate_series(first_day, today, interval '1 day')::date as day) series),
    'groups', groups);
end
$$;

create or replace function api.get_usage_detail_for_support(metric text, item text, period_days integer default 30)
returns jsonb language sql stable security invoker set search_path = ''
as $$select internal.get_usage_detail_for_support_for_actor(metric, item, period_days)$$;

revoke all on function
  internal.usage_rows(jsonb),
  internal.usage_club_rows(jsonb),
  internal.get_usage_detail_for_support_for_actor(text, text, integer),
  api.get_usage_detail_for_support(text, text, integer)
from public, anon, authenticated;

grant execute on function
  internal.get_usage_detail_for_support_for_actor(text, text, integer),
  api.get_usage_detail_for_support(text, text, integer)
to authenticated;

notify pgrst, 'reload schema';
