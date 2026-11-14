-- Supportens statistik (adminsidan för TeamZones support, del 2).
--
-- Support wants to see how the apps are used: how many accounts there are,
-- how many are active, which apps they use and how much each area is used.
--
-- * Active days were recorded per account (core.profile_activity_days,
--   PROF-05) but not from which app. core.profile_activity_apps adds that,
--   recorded by api.record_app_activity(app) once per day and app. It also
--   records the active day, so a client calling it no longer needs
--   api.record_activity (kept for older app versions).
-- * api.get_platform_usage_for_support(period_days): counts only, never
--   names or ids, for support administrators only. Days are Swedish dates.

create table if not exists core.profile_activity_apps (
  profile_id uuid not null references core.profiles(id) on delete cascade,
  day date not null,
  app text not null check (app in ('web', 'android', 'ios', 'tacticsboard', 'webtools')),
  primary key (profile_id, day, app)
);
create index if not exists profile_activity_apps_day_idx
  on core.profile_activity_apps(day, app);
alter table core.profile_activity_apps enable row level security;
revoke all on table core.profile_activity_apps from public, anon, authenticated;

create or replace function internal.record_app_activity_for_actor(app text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  today date := (now() at time zone 'Europe/Stockholm')::date;
begin
  if auth.uid() is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  if app is null or app not in ('web', 'android', 'ios', 'tacticsboard', 'webtools') then
    raise invalid_parameter_value using message = 'invalid_app';
  end if;
  insert into core.profile_activity_days(profile_id, day)
  values (auth.uid(), today) on conflict do nothing;
  insert into core.profile_activity_apps(profile_id, day, app)
  values (auth.uid(), today, app) on conflict do nothing;
end
$$;

create or replace function internal.get_platform_usage_for_support_for_actor(period_days integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  today date := (now() at time zone 'Europe/Stockholm')::date;
  days integer := greatest(7, least(coalesce(period_days, 30), 365));
  first_day date;
  since timestamptz;
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  first_day := today - (days - 1);
  since := first_day::timestamp at time zone 'Europe/Stockholm';

  return jsonb_build_object(
    'period_days', days,
    'first_day', first_day,
    'today', today,
    'activity_recorded_since', (select min(day) from core.profile_activity_days),
    'apps_recorded_since', (select min(day) from core.profile_activity_apps),
    'accounts', jsonb_build_object(
      'total', (select count(*) from core.profiles),
      'by_type', coalesce((select jsonb_object_agg(kind, n) from (
          select coalesce(profile.account_type, 'unknown') kind, count(*) n
          from core.profiles profile group by 1) types), '{}'::jsonb),
      'new_in_period', (select count(*) from core.profiles profile where profile.created_at >= since),
      'linked_to_club', (select count(distinct link.profile_id) from core.person_account_links link
        where link.state = 'active')),
    'active', jsonb_build_object(
      'today', (select count(*) from core.profile_activity_days activity where activity.day = today),
      'last_7_days', (select count(distinct activity.profile_id) from core.profile_activity_days activity
        where activity.day > today - 7),
      'last_30_days', (select count(distinct activity.profile_id) from core.profile_activity_days activity
        where activity.day > today - 30),
      'in_period', (select count(distinct activity.profile_id) from core.profile_activity_days activity
        where activity.day >= first_day)),
    'apps', coalesce((select jsonb_object_agg(app_row.app, app_row.n) from (
        select activity.app, count(distinct activity.profile_id) n from core.profile_activity_apps activity
        where activity.day >= first_day group by activity.app) app_row), '{}'::jsonb),
    'daily', (select jsonb_agg(jsonb_build_object(
        'day', series.day,
        'active', (select count(*) from core.profile_activity_days activity where activity.day = series.day),
        'new_accounts', (select count(*) from core.profiles profile
          where (profile.created_at at time zone 'Europe/Stockholm')::date = series.day))
        order by series.day)
      from (select generate_series(first_day, today, interval '1 day')::date as day) series),
    'clubs', jsonb_build_object(
      'active', (select count(*) from core.clubs club where club.status = 'active'),
      'official', (select count(*) from core.clubs club
        where club.status = 'active' and club.verification_status = 'official'),
      'new_in_period', (select count(*) from core.clubs club where club.created_at >= since),
      'teams', (select count(*) from core.teams team where team.status = 'active'),
      'people', (select count(*) from core.club_people person where person.status = 'active')),
    'areas', jsonb_build_object(
      'events_created', (select count(*) from core.events event_row where event_row.created_at >= since),
      'callup_answers', (select count(*) from core.callup_responses response where response.created_at >= since),
      'attendance_recorded', (select count(*) from core.attendance_facts fact where fact.recorded_at >= since),
      'messages_sent', (select count(*) from core.messages message where message.created_at >= since),
      'tactics_projects_created', (select count(*) from core.tactics_projects project
        where project.created_at >= since),
      'tactics_live_sessions', (select count(*) from core.tactics_live_sessions live
        where live.created_at >= since),
      'bookings_created', (select count(*) from core.booking_bookings booking
        where booking.created_at >= since)),
    'subscriptions', coalesce((select jsonb_object_agg(sub.entitlement_key, sub.n) from (
        select subscription.entitlement_key, count(*) n from core.personal_billing_subscriptions subscription
        where subscription.state = 'active' group by 1) sub), '{}'::jsonb),
    'push_devices', coalesce((select jsonb_object_agg(device.platform, device.n) from (
        select token.platform, count(*) n from internal.push_endpoint_tokens token
        join core.notification_endpoints endpoint on endpoint.id = token.endpoint_id
        where endpoint.state = 'active' group by 1) device), '{}'::jsonb)
  );
end
$$;

create or replace function api.record_app_activity(app text)
returns void language sql security invoker set search_path = ''
as $$select internal.record_app_activity_for_actor(app)$$;

create or replace function api.get_platform_usage_for_support(period_days integer default 30)
returns jsonb language sql stable security invoker set search_path = ''
as $$select internal.get_platform_usage_for_support_for_actor(period_days)$$;

revoke all on function
  internal.record_app_activity_for_actor(text),
  internal.get_platform_usage_for_support_for_actor(integer),
  api.record_app_activity(text),
  api.get_platform_usage_for_support(integer)
from public, anon, authenticated;

grant execute on function
  internal.record_app_activity_for_actor(text),
  internal.get_platform_usage_for_support_for_actor(integer),
  api.record_app_activity(text),
  api.get_platform_usage_for_support(integer)
to authenticated;

notify pgrst, 'reload schema';
