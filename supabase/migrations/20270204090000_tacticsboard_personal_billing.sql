-- Tacticsboard sold per person (2026-11-03): a billing account per profile,
-- the 7-day trial without a card, and the entitlement webtool.tacticsboard.
-- Kept apart from the clubs' billing (S10A) so that flow is untouched.
-- Checkout, the Customer Portal and the webhook come next (plan item 7);
-- until then no subscription row is written, and access is the trial only.

-- One row per person, made when the trial starts. The trial is started once
-- and never again, even after a subscription ends.
create table core.personal_billing_accounts (
  profile_id uuid primary key references core.profiles(id) on delete cascade,
  trial_started_at timestamptz not null default now(),
  trial_ends_at timestamptz not null default now() + interval '7 days',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  check (trial_ends_at > trial_started_at)
);

-- The person's subscription, written by the Stripe webhook only. Provider
-- references are kept as hashes, as in S10A.
create table core.personal_billing_subscriptions (
  profile_id uuid primary key references core.personal_billing_accounts(profile_id) on delete cascade,
  entitlement_key text not null default 'webtool.tacticsboard'
    check (entitlement_key ~ '^webtool\.[a-z0-9_]+$'),
  provider text not null check (provider = 'stripe'),
  provider_subscription_ref_hash bytea not null check (octet_length(provider_subscription_ref_hash) = 32),
  provider_revision bigint,
  billing_interval text check (billing_interval in ('month', 'year')),
  state text not null check (state in ('active', 'grace', 'ended', 'unknown')),
  current_period_ends_at timestamptz,
  cancel_at_period_end boolean not null default false,
  grace_ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  unique (provider_subscription_ref_hash),
  check (state <> 'grace' or grace_ends_at is not null)
);

alter table core.personal_billing_accounts enable row level security;
alter table core.personal_billing_subscriptions enable row level security;
revoke all on core.personal_billing_accounts, core.personal_billing_subscriptions
  from public, anon, authenticated;

-- What a person may do in a webtool: write, or nothing. Without a trial or
-- a paid subscription the account is fully locked (decision 2026-11-02);
-- nothing is deleted, and links already shared keep working for others.
create function internal.personal_entitlement_status(target_profile_id uuid, target_entitlement_key text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  account core.personal_billing_accounts;
  subscription core.personal_billing_subscriptions;
  source text := 'none';
begin
  select * into account from core.personal_billing_accounts where profile_id = target_profile_id;
  select * into subscription from core.personal_billing_subscriptions
   where profile_id = target_profile_id and entitlement_key = target_entitlement_key;
  if subscription.state = 'active'
     and (subscription.current_period_ends_at is null or subscription.current_period_ends_at > now()) then
    source := 'subscription';
  elsif subscription.state = 'grace' and subscription.grace_ends_at > now() then
    source := 'grace';
  elsif account.trial_ends_at > now() then
    source := 'trial';
  end if;
  return jsonb_build_object(
    'entitlement', target_entitlement_key,
    'access_mode', case when source = 'none' then 'denied' else 'write' end,
    'source', source,
    'trial_available', account.profile_id is null,
    'trial_ends_at', account.trial_ends_at,
    'subscription_state', subscription.state,
    'billing_interval', subscription.billing_interval,
    'current_period_ends_at', subscription.current_period_ends_at,
    'cancel_at_period_end', coalesce(subscription.cancel_at_period_end, false),
    'grace_ends_at', subscription.grace_ends_at
  );
end;
$$;

-- For the write gate in the Tacticsboard RPCs (plan item 8).
create function internal.actor_has_tacticsboard()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null
    and internal.personal_entitlement_status(auth.uid(), 'webtool.tacticsboard') ->> 'access_mode' = 'write'
$$;

-- A guest (an anonymous sign-in, used for live lessons) has no account to bill.
create function internal.billing_actor_is_person()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and not coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
$$;

create function internal.get_my_tacticsboard_access_for_actor()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.billing_actor_is_person() then raise insufficient_privilege using message = 'not_signed_in'; end if;
  return internal.personal_entitlement_status(auth.uid(), 'webtool.tacticsboard');
end;
$$;

-- Starts the trial the first time; afterwards it only returns the status.
create function internal.start_tacticsboard_trial_for_actor()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare started uuid;
begin
  if not internal.billing_actor_is_person() then raise insufficient_privilege using message = 'not_signed_in'; end if;
  insert into core.personal_billing_accounts (profile_id) values (auth.uid())
  on conflict (profile_id) do nothing returning profile_id into started;
  if started is not null then
    insert into audit.command_events (actor_profile_id, command_type, aggregate_type, aggregate_id, metadata)
    values (auth.uid(), 'billing.personal_trial.started.v1', 'personal_billing_account', auth.uid(),
      jsonb_build_object('entitlement', 'webtool.tacticsboard', 'days', 7));
  end if;
  return internal.personal_entitlement_status(auth.uid(), 'webtool.tacticsboard');
end;
$$;

create function api.get_my_tacticsboard_access() returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.get_my_tacticsboard_access_for_actor() $$;
create function api.start_tacticsboard_trial() returns jsonb
language sql security invoker set search_path = '' as
$$ select internal.start_tacticsboard_trial_for_actor() $$;

revoke all on function
  internal.personal_entitlement_status(uuid, text),
  internal.actor_has_tacticsboard(),
  internal.billing_actor_is_person(),
  internal.get_my_tacticsboard_access_for_actor(),
  internal.start_tacticsboard_trial_for_actor(),
  api.get_my_tacticsboard_access(),
  api.start_tacticsboard_trial()
from public, anon, authenticated;
grant execute on function
  internal.actor_has_tacticsboard(),
  internal.get_my_tacticsboard_access_for_actor(),
  internal.start_tacticsboard_trial_for_actor(),
  api.get_my_tacticsboard_access(),
  api.start_tacticsboard_trial()
to authenticated;
notify pgrst, 'reload schema';
