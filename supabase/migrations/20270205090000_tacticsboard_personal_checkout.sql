-- Tacticsboard sold per person, plan item 7 (2026-11-03): Stripe Checkout,
-- the Customer Portal and the webhook for webtool.tacticsboard. Builds on
-- 20270204090000; the clubs' S10A commands are untouched, and both flows
-- share internal.billing_provider_events for duplicate protection.

-- A subscription no longer needs a trial first: someone may buy at once.
alter table core.personal_billing_subscriptions
  drop constraint personal_billing_subscriptions_profile_id_fkey,
  add foreign key (profile_id) references core.profiles(id) on delete cascade;

-- The Stripe prices that give webtool.tacticsboard, one per interval and
-- mode. Rows are added by hand once the prices exist in Stripe. A coupon
-- (the launch offer on the yearly price) is applied until coupon_ends_at.
create table internal.personal_billing_prices (
  id uuid primary key default gen_random_uuid(),
  entitlement_key text not null default 'webtool.tacticsboard'
    check (entitlement_key ~ '^webtool\.[a-z0-9_]+$'),
  billing_interval text not null check (billing_interval in ('month', 'year')),
  livemode boolean not null,
  provider_price_ref text not null check (provider_price_ref ~ '^price_[A-Za-z0-9]+$'),
  provider_coupon_ref text check (provider_coupon_ref ~ '^[A-Za-z0-9_-]{1,64}$'),
  coupon_ends_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (provider_price_ref),
  check ((provider_coupon_ref is null) = (coupon_ends_at is null))
);
create unique index personal_billing_prices_active_idx
  on internal.personal_billing_prices (entitlement_key, billing_interval, livemode) where active;

-- The person's Stripe customer, kept in plain text for the Customer Portal
-- and the next checkout. Never readable by clients.
create table internal.personal_billing_customers (
  profile_id uuid not null references core.profiles(id) on delete cascade,
  livemode boolean not null,
  provider_customer_ref text not null check (provider_customer_ref ~ '^cus_[A-Za-z0-9]+$'),
  updated_at timestamptz not null default now(),
  primary key (profile_id, livemode),
  unique (provider_customer_ref)
);

create table internal.personal_billing_checkout_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references core.profiles(id) on delete cascade,
  idempotency_key uuid not null,
  entitlement_key text not null default 'webtool.tacticsboard',
  billing_interval text not null check (billing_interval in ('month', 'year')),
  state text not null default 'prepared' check (state in ('prepared', 'claimed', 'completed')),
  prepared_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '15 minutes',
  updated_at timestamptz not null default now(),
  unique (profile_id, idempotency_key)
);

revoke all on internal.personal_billing_prices, internal.personal_billing_customers,
  internal.personal_billing_checkout_requests from public, anon, authenticated;

-- A trial is offered only to someone who has neither had one nor paid.
create or replace function internal.personal_entitlement_status(target_profile_id uuid, target_entitlement_key text)
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
    'trial_available', account.profile_id is null and subscription.profile_id is null,
    'trial_ends_at', account.trial_ends_at,
    'subscription_state', subscription.state,
    'billing_interval', subscription.billing_interval,
    'current_period_ends_at', subscription.current_period_ends_at,
    'cancel_at_period_end', coalesce(subscription.cancel_at_period_end, false),
    'grace_ends_at', subscription.grace_ends_at
  );
end;
$$;

create or replace function internal.start_tacticsboard_trial_for_actor()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare started uuid;
begin
  if not internal.billing_actor_is_person() then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if not exists (select 1 from core.personal_billing_subscriptions where profile_id = auth.uid()) then
    insert into core.personal_billing_accounts (profile_id) values (auth.uid())
    on conflict (profile_id) do nothing returning profile_id into started;
  end if;
  if started is not null then
    insert into audit.command_events (actor_profile_id, command_type, aggregate_type, aggregate_id, metadata)
    values (auth.uid(), 'billing.personal_trial.started.v1', 'personal_billing_account', auth.uid(),
      jsonb_build_object('entitlement', 'webtool.tacticsboard', 'days', 7));
  end if;
  return internal.personal_entitlement_status(auth.uid(), 'webtool.tacticsboard');
end;
$$;

-- Step 1 of a checkout, as the signed-in person.
create function internal.prepare_tacticsboard_checkout_for_actor(target_interval text, p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare existing internal.personal_billing_checkout_requests; request_id uuid;
begin
  if not internal.billing_actor_is_person() then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if target_interval is null or target_interval not in ('month', 'year') then
    raise invalid_parameter_value using message = 'invalid_checkout';
  end if;
  select * into existing from internal.personal_billing_checkout_requests
   where profile_id = auth.uid() and idempotency_key = p_idempotency_key;
  if existing.id is not null then
    if existing.billing_interval <> target_interval then raise unique_violation using message = 'idempotency_conflict'; end if;
    return jsonb_build_object('checkout_request_id', existing.id);
  end if;
  if internal.personal_entitlement_status(auth.uid(), 'webtool.tacticsboard') ->> 'source' in ('subscription', 'grace') then
    raise check_violation using message = 'already_subscribed';
  end if;
  insert into internal.personal_billing_checkout_requests (profile_id, idempotency_key, billing_interval)
  values (auth.uid(), p_idempotency_key, target_interval) returning id into request_id;
  insert into audit.command_events (actor_profile_id, command_type, aggregate_type, aggregate_id, metadata)
  values (auth.uid(), 'billing.personal_checkout.prepared.v1', 'personal_checkout', request_id,
    jsonb_build_object('entitlement', 'webtool.tacticsboard', 'interval', target_interval));
  return jsonb_build_object('checkout_request_id', request_id);
end;
$$;

-- Step 2, by the Edge function: what Stripe needs for the session. The
-- trial's remaining days carry over, so buying early costs nothing extra.
create function internal.claim_tacticsboard_checkout_for_server(target_checkout_request_id uuid, target_livemode boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare request internal.personal_billing_checkout_requests; price internal.personal_billing_prices;
begin
  select * into request from internal.personal_billing_checkout_requests
   where id = target_checkout_request_id for update;
  if request.id is null or request.expires_at <= now() or request.state not in ('prepared', 'claimed') then
    raise check_violation using message = 'checkout_unavailable';
  end if;
  select * into price from internal.personal_billing_prices
   where entitlement_key = request.entitlement_key and billing_interval = request.billing_interval
     and livemode = target_livemode and active;
  if price.id is null then raise check_violation using message = 'billing_unavailable'; end if;
  update internal.personal_billing_checkout_requests set state = 'claimed', updated_at = now() where id = request.id;
  return jsonb_build_object(
    'checkout_request_id', request.id,
    'profile_id', request.profile_id,
    'provider_price_ref', price.provider_price_ref,
    'provider_coupon_ref', case when price.coupon_ends_at > now() then price.provider_coupon_ref end,
    'provider_customer_ref', (select provider_customer_ref from internal.personal_billing_customers
      where profile_id = request.profile_id and livemode = target_livemode),
    'trial_ends_at', (select trial_ends_at from core.personal_billing_accounts
      where profile_id = request.profile_id and trial_ends_at > now())
  );
end;
$$;

-- For the Customer Portal: the person's own Stripe customer, if any.
create function internal.tacticsboard_billing_customer_for_server(target_profile_id uuid, target_livemode boolean)
returns text language sql stable security definer set search_path = '' as $$
  select provider_customer_ref from internal.personal_billing_customers
   where profile_id = target_profile_id and livemode = target_livemode
$$;

-- Stripe's subscription status as ours. A failed renewal keeps access for
-- 14 days (PAR-BILL-02) while Stripe retries; then the account is locked.
create function internal.personal_subscription_state(stripe_status text)
returns text language sql immutable set search_path = '' as $$
  select case
    when stripe_status in ('active', 'trialing') then 'active'
    when stripe_status in ('past_due', 'unpaid') then 'grace'
    when stripe_status in ('canceled', 'incomplete_expired', 'paused') then 'ended'
    else 'unknown' end
$$;

create function internal.ingest_tacticsboard_stripe_event_for_server(
  provider_event_id text, provider_created_at bigint, event_type text, livemode boolean, payload jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  event_id uuid;
  object jsonb := payload -> 'data' -> 'object';
  customer_ref text := object ->> 'customer';
  subscription_ref text;
  request internal.personal_billing_checkout_requests;
  existing core.personal_billing_subscriptions;
  price internal.personal_billing_prices;
  target_profile uuid;
  new_state text;
  period_end text;
  finish text := 'processed';
  is_live boolean := $4;
begin
  if provider_event_id !~ '^evt_[A-Za-z0-9]+$' or provider_created_at <= 0
     or jsonb_typeof(object) is distinct from 'object' then
    raise check_violation using message = 'invalid_provider_event';
  end if;
  insert into internal.billing_provider_events (provider, environment, provider_event_id_hash,
    provider_revision, event_type, payload_sha256, signature_verified_at)
  values ('stripe', case when is_live then 'production' else 'test' end, extensions.digest(provider_event_id, 'sha256'),
    provider_created_at, event_type, extensions.digest(payload::text, 'sha256'), now())
  on conflict (provider, environment, provider_event_id_hash) do nothing returning id into event_id;
  if event_id is null then return jsonb_build_object('duplicate', true); end if;

  if customer_ref is null or customer_ref !~ '^cus_[A-Za-z0-9]+$' then
    finish := 'rejected';
  elsif event_type = 'checkout.session.completed' then
    begin request := (select r from internal.personal_billing_checkout_requests r
      where r.id = (object ->> 'client_reference_id')::uuid);
    exception when others then request := null; end;
    if request.id is null then
      finish := 'rejected';
    else
      target_profile := request.profile_id;
      update internal.personal_billing_checkout_requests set state = 'completed', updated_at = now() where id = request.id;
    end if;
  elsif event_type in ('customer.subscription.created', 'customer.subscription.updated', 'customer.subscription.deleted') then
    subscription_ref := object ->> 'id';
    select * into existing from core.personal_billing_subscriptions
     where provider_subscription_ref_hash = extensions.digest(coalesce(subscription_ref, ''), 'sha256');
    target_profile := existing.profile_id;
    if target_profile is null then
      begin select profile_id into target_profile from internal.personal_billing_checkout_requests
        where id = (object -> 'metadata' ->> 'checkout_request_id')::uuid;
      exception when others then target_profile := null; end;
      select * into existing from core.personal_billing_subscriptions where profile_id = target_profile;
    end if;
    select * into price from internal.personal_billing_prices
     where provider_price_ref = object #>> '{items,data,0,price,id}' and personal_billing_prices.livemode = is_live;
    new_state := case when event_type = 'customer.subscription.deleted' then 'ended'
      else internal.personal_subscription_state(object ->> 'status') end;
    if subscription_ref is null or subscription_ref !~ '^sub_[A-Za-z0-9]+$' or target_profile is null or price.id is null then
      finish := 'rejected';
    elsif existing.profile_id is not null and (
      (existing.provider_subscription_ref_hash = extensions.digest(subscription_ref, 'sha256')
        and existing.provider_revision > provider_created_at)
      -- An older subscription never replaces a newer one that still gives access.
      or (existing.provider_subscription_ref_hash <> extensions.digest(subscription_ref, 'sha256')
        and existing.state in ('active', 'grace') and new_state not in ('active', 'grace'))) then
      finish := 'ignored_stale';
    else
      period_end := coalesce(object ->> 'current_period_end', object #>> '{items,data,0,current_period_end}');
      insert into core.personal_billing_subscriptions as s (profile_id, entitlement_key, provider,
        provider_subscription_ref_hash, provider_revision, billing_interval, state, current_period_ends_at,
        cancel_at_period_end, grace_ends_at)
      values (target_profile, price.entitlement_key, 'stripe', extensions.digest(subscription_ref, 'sha256'),
        provider_created_at, price.billing_interval, new_state,
        to_timestamp(nullif(period_end, '')::double precision),
        coalesce((object ->> 'cancel_at_period_end')::boolean, false) or nullif(object ->> 'cancel_at', '') is not null,
        case when new_state = 'grace' then now() + interval '14 days' end)
      on conflict (profile_id) do update set
        entitlement_key = excluded.entitlement_key,
        provider_subscription_ref_hash = excluded.provider_subscription_ref_hash,
        provider_revision = excluded.provider_revision,
        billing_interval = excluded.billing_interval,
        state = excluded.state,
        current_period_ends_at = excluded.current_period_ends_at,
        cancel_at_period_end = excluded.cancel_at_period_end,
        -- The 14 days count from the first failed renewal, not the latest retry.
        grace_ends_at = case when excluded.state <> 'grace' then null
          when s.state = 'grace' and s.provider_subscription_ref_hash = excluded.provider_subscription_ref_hash
          then s.grace_ends_at else excluded.grace_ends_at end,
        updated_at = now(), revision = s.revision + 1;
      insert into audit.command_events (actor_profile_id, command_type, aggregate_type, aggregate_id, metadata)
      values (target_profile, 'billing.personal_entitlement.changed.v1', 'personal_billing_subscription', target_profile,
        jsonb_build_object('entitlement', price.entitlement_key, 'state', new_state, 'provider_revision', provider_created_at));
    end if;
  else
    finish := 'rejected';
  end if;

  if finish = 'processed' then
    insert into internal.personal_billing_customers (profile_id, livemode, provider_customer_ref)
    values (target_profile, is_live, customer_ref)
    on conflict on constraint personal_billing_customers_pkey do update set provider_customer_ref = excluded.provider_customer_ref, updated_at = now();
  end if;
  update internal.billing_provider_events set processing_state = finish, processed_at = now(),
    failure_code = case when finish = 'rejected' then 'not_bound' end
   where id = event_id;
  return jsonb_build_object('accepted', finish = 'processed', 'state', finish);
end;
$$;

create function api.prepare_tacticsboard_checkout(target_interval text, idempotency_key uuid) returns jsonb
language sql security invoker set search_path = '' as
$$ select internal.prepare_tacticsboard_checkout_for_actor(target_interval, idempotency_key) $$;
create function api.claim_tacticsboard_checkout(target_checkout_request_id uuid, target_livemode boolean) returns jsonb
language sql security invoker set search_path = '' as
$$ select internal.claim_tacticsboard_checkout_for_server(target_checkout_request_id, target_livemode) $$;
create function api.tacticsboard_billing_customer(target_profile_id uuid, target_livemode boolean) returns text
language sql stable security invoker set search_path = '' as
$$ select internal.tacticsboard_billing_customer_for_server(target_profile_id, target_livemode) $$;
create function api.ingest_tacticsboard_stripe_event(provider_event_id text, provider_created_at bigint,
  event_type text, livemode boolean, payload jsonb) returns jsonb
language sql security invoker set search_path = '' as
$$ select internal.ingest_tacticsboard_stripe_event_for_server(provider_event_id, provider_created_at, event_type, livemode, payload) $$;

revoke all on function
  internal.prepare_tacticsboard_checkout_for_actor(text, uuid),
  internal.claim_tacticsboard_checkout_for_server(uuid, boolean),
  internal.tacticsboard_billing_customer_for_server(uuid, boolean),
  internal.personal_subscription_state(text),
  internal.ingest_tacticsboard_stripe_event_for_server(text, bigint, text, boolean, jsonb),
  api.prepare_tacticsboard_checkout(text, uuid),
  api.claim_tacticsboard_checkout(uuid, boolean),
  api.tacticsboard_billing_customer(uuid, boolean),
  api.ingest_tacticsboard_stripe_event(text, bigint, text, boolean, jsonb)
from public, anon, authenticated;
grant execute on function
  internal.prepare_tacticsboard_checkout_for_actor(text, uuid),
  api.prepare_tacticsboard_checkout(text, uuid)
to authenticated;
grant execute on function
  internal.claim_tacticsboard_checkout_for_server(uuid, boolean),
  internal.tacticsboard_billing_customer_for_server(uuid, boolean),
  internal.ingest_tacticsboard_stripe_event_for_server(text, bigint, text, boolean, jsonb),
  api.claim_tacticsboard_checkout(uuid, boolean),
  api.tacticsboard_billing_customer(uuid, boolean),
  api.ingest_tacticsboard_stripe_event(text, bigint, text, boolean, jsonb)
to service_role;
notify pgrst, 'reload schema';
