-- Supportens statistik för Tacticsboard (2026-11-14).
--
-- Tacticsboard is sold from webtools.teamzoneapp.se, whose database is the
-- production project, not the app's. Support reads its numbers through the
-- app project's edge function support-tacticsboard-usage, which checks that
-- the caller is a support administrator and then calls
-- api.get_tacticsboard_usage_for_server here with the production project's
-- secret key. Only the server role may call it.
--
-- Counts only: no names, no e-mail addresses, no ids. Days are Swedish dates.
-- It uses only tables that exist in both projects, so it can be applied to
-- either of them.

create or replace function internal.get_tacticsboard_usage_for_server(period_days integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  today date := (now() at time zone 'Europe/Stockholm')::date;
  days integer := greatest(7, least(coalesce(period_days, 30), 365));
  first_day date;
  since timestamptz;
  withdrawals bigint;
begin
  first_day := today - (days - 1);
  since := first_day::timestamp at time zone 'Europe/Stockholm';
  -- Withdrawals (20270209090000) exist only where Tacticsboard is sold.
  if to_regclass('internal.personal_billing_withdrawals') is not null then
    execute 'select count(*) from internal.personal_billing_withdrawals
      where livemode and received_at >= $1' into withdrawals using since;
  end if;

  return jsonb_build_object(
    'period_days', days,
    'first_day', first_day,
    'today', today,
    'accounts', (
      select jsonb_build_object(
        'total', count(*),
        'new_in_period', count(*) filter (where account.created_at >= since),
        'signed_in_7_days', count(*) filter (where account.last_sign_in_at >= now() - interval '7 days'),
        'signed_in_30_days', count(*) filter (where account.last_sign_in_at >= now() - interval '30 days'),
        'signed_in_in_period', count(*) filter (where account.last_sign_in_at >= since))
      from auth.users account
      where not coalesce(account.is_anonymous, false) and account.deleted_at is null),
    'billing', (
      select jsonb_build_object(
        'trials_started', count(*),
        'trials_started_in_period', count(*) filter (where billing.trial_started_at >= since),
        'trials_active', count(*) filter (where billing.trial_ends_at > now()
          and not exists (select 1 from core.personal_billing_subscriptions paid
            where paid.profile_id = billing.profile_id and paid.state in ('active', 'grace'))),
        'trials_ended_unpaid', count(*) filter (where billing.trial_ends_at <= now()
          and not exists (select 1 from core.personal_billing_subscriptions paid
            where paid.profile_id = billing.profile_id)))
      from core.personal_billing_accounts billing),
    'subscriptions', (
      select jsonb_build_object(
        'paying_month', count(*) filter (where paid.state = 'active' and paid.billing_interval = 'month'),
        'paying_year', count(*) filter (where paid.state = 'active' and paid.billing_interval = 'year'),
        'ending', count(*) filter (where paid.state = 'active' and paid.cancel_at_period_end),
        'grace', count(*) filter (where paid.state = 'grace'),
        'ended', count(*) filter (where paid.state = 'ended'),
        'new_in_period', count(*) filter (where paid.created_at >= since),
        'withdrawals_in_period', withdrawals)
      from core.personal_billing_subscriptions paid
      where paid.entitlement_key = 'webtool.tacticsboard'),
    'projects', (
      select jsonb_build_object(
        'total', count(*),
        'new_in_period', count(*) filter (where project.created_at >= since),
        'changed_in_period', count(*) filter (where project.updated_at >= since),
        'owners', count(distinct project.owner_id),
        'match', count(*) filter (where project.kind = 'match'),
        'training', count(*) filter (where project.kind = 'training'),
        'education', count(*) filter (where project.kind = 'education'))
      from core.tactics_projects project),
    'live', jsonb_build_object(
      'live_now', (select count(*) from core.tactics_live_sessions session where session.status = 'live'),
      'sessions_in_period', (select count(*) from core.tactics_live_sessions session
        where session.created_at >= since),
      'participants_in_period', (select count(*) from core.tactics_live_participants participant
        where participant.joined_at >= since),
      'guests_in_period', (select count(*) from core.tactics_live_participants participant
        where participant.joined_at >= since and participant.is_guest)),
    'sharing', jsonb_build_object(
      'share_links', (select count(*) from core.tactics_share_links link where link.revoked_at is null),
      'library_items', (select count(*) from core.tactics_library_items item),
      'shared_items', (select count(*) from core.tactics_shared_items shared
        where shared.owner_id is not null and not shared.hidden),
      'open_reports', (select count(*) from core.tactics_shared_reports report
        where report.resolved_at is null)),
    'daily', (
      select coalesce(jsonb_agg(jsonb_build_object(
          'day', calendar.day,
          'new_accounts', (select count(*) from auth.users account
            where not coalesce(account.is_anonymous, false) and account.deleted_at is null
              and (account.created_at at time zone 'Europe/Stockholm')::date = calendar.day),
          'trials_started', (select count(*) from core.personal_billing_accounts billing
            where (billing.trial_started_at at time zone 'Europe/Stockholm')::date = calendar.day),
          'new_subscriptions', (select count(*) from core.personal_billing_subscriptions paid
            where paid.entitlement_key = 'webtool.tacticsboard'
              and (paid.created_at at time zone 'Europe/Stockholm')::date = calendar.day),
          'new_projects', (select count(*) from core.tactics_projects project
            where (project.created_at at time zone 'Europe/Stockholm')::date = calendar.day),
          'live_sessions', (select count(*) from core.tactics_live_sessions session
            where (session.created_at at time zone 'Europe/Stockholm')::date = calendar.day))
        order by calendar.day), '[]'::jsonb)
      from (select generate_series(first_day, today, interval '1 day')::date as day) calendar)
  );
end
$$;

create or replace function api.get_tacticsboard_usage_for_server(period_days integer default 30)
returns jsonb language sql stable security invoker set search_path = ''
as $$select internal.get_tacticsboard_usage_for_server(period_days)$$;

revoke all on function
  internal.get_tacticsboard_usage_for_server(integer),
  api.get_tacticsboard_usage_for_server(integer)
from public, anon, authenticated;

grant execute on function
  internal.get_tacticsboard_usage_for_server(integer),
  api.get_tacticsboard_usage_for_server(integer)
to service_role;

notify pgrst, 'reload schema';
