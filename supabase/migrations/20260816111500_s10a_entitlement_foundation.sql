-- S10A fail-closed billing and club entitlement foundation.
-- Checkout, provider ingress and commercial activation are intentionally absent.

create table core.billing_accounts (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  environment text not null check (environment in ('test', 'production')),
  state text not null default 'unconfigured'
    check (state in ('unconfigured', 'active', 'grace', 'read_only', 'ended', 'unknown')),
  grace_ends_at timestamptz,
  provider text,
  provider_customer_ref_hash bytea,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id),
  unique (club_id, environment),
  check (provider_customer_ref_hash is null or octet_length(provider_customer_ref_hash) = 32),
  check ((provider is null) = (provider_customer_ref_hash is null)),
  check (state <> 'grace' or grace_ends_at is not null)
);

create table core.billing_subscriptions (
  id uuid primary key default gen_random_uuid(),
  billing_account_id uuid not null references core.billing_accounts(id),
  provider_subscription_ref_hash bytea,
  provider_revision bigint,
  pricebook_version text not null check (pricebook_version ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  base_plan_key text not null check (base_plan_key ~ '^plan\.[a-z0-9_]+$'),
  state text not null check (state in ('trialing', 'active', 'grace', 'read_only', 'ended', 'unknown')),
  current_period_starts_at timestamptz,
  current_period_ends_at timestamptz,
  grace_ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  unique (billing_account_id),
  check (provider_subscription_ref_hash is null or octet_length(provider_subscription_ref_hash) = 32),
  check (current_period_ends_at is null or current_period_starts_at is null
    or current_period_ends_at > current_period_starts_at),
  check (state <> 'grace' or grace_ends_at is not null)
);

create table core.billing_subscription_items (
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references core.billing_subscriptions(id) on delete cascade,
  entitlement_key text not null
    check (entitlement_key ~ '^(module|webtool|quota)\.[a-z0-9_]+$'),
  quantity integer not null default 1 check (quantity > 0),
  state text not null default 'active' check (state in ('active', 'ended', 'unknown')),
  starts_at timestamptz not null,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  unique (subscription_id, entitlement_key),
  check (ends_at is null or ends_at > starts_at)
);

create table internal.billing_provider_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  environment text not null check (environment in ('test', 'production')),
  provider_event_id_hash bytea not null check (octet_length(provider_event_id_hash) = 32),
  provider_revision bigint,
  event_type text not null check (length(event_type) between 1 and 120),
  payload_sha256 bytea not null check (octet_length(payload_sha256) = 32),
  signature_verified_at timestamptz not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_state text not null default 'pending'
    check (processing_state in ('pending', 'processed', 'ignored_stale', 'retryable_failure', 'rejected')),
  failure_code text,
  unique (provider, environment, provider_event_id_hash)
);

create table core.club_entitlements (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  billing_account_id uuid not null references core.billing_accounts(id),
  entitlement_key text not null
    check (entitlement_key ~ '^(base|module|webtool|quota)\.[a-z0-9_]+$'),
  access_mode text not null check (access_mode in ('write', 'read_only', 'denied')),
  quantity integer check (quantity is null or quantity >= 0),
  source_subscription_revision bigint not null check (source_subscription_revision > 0),
  effective_at timestamptz not null,
  expires_at timestamptz,
  computed_at timestamptz not null default now(),
  unique (club_id, entitlement_key),
  foreign key (billing_account_id, club_id)
    references core.billing_accounts(id, club_id),
  check (expires_at is null or expires_at > effective_at)
);

create index billing_items_subscription_state_idx
  on core.billing_subscription_items (subscription_id, state, starts_at, ends_at);
create unique index billing_accounts_provider_ref_idx
  on core.billing_accounts (provider, provider_customer_ref_hash)
  where provider_customer_ref_hash is not null;
create unique index billing_subscriptions_provider_ref_idx
  on core.billing_subscriptions (provider_subscription_ref_hash)
  where provider_subscription_ref_hash is not null;
create index club_entitlements_account_idx
  on core.club_entitlements (billing_account_id, access_mode);
create index provider_events_pending_idx
  on internal.billing_provider_events (received_at)
  where processing_state in ('pending', 'retryable_failure');

alter table core.billing_accounts enable row level security;
alter table core.billing_subscriptions enable row level security;
alter table core.billing_subscription_items enable row level security;
alter table core.club_entitlements enable row level security;

create function internal.recompute_club_entitlements(target_billing_account_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  account core.billing_accounts%rowtype;
  subscription core.billing_subscriptions%rowtype;
  mode text := 'denied';
  effective_time timestamptz := now();
begin
  select * into account from core.billing_accounts
   where id = target_billing_account_id for update;
  if account.id is null then raise no_data_found using message = 'billing_account_not_found'; end if;

  select * into subscription from core.billing_subscriptions
   where billing_account_id = account.id;

  delete from core.club_entitlements where billing_account_id = account.id;
  if subscription.id is null or subscription.state = 'unknown' then return; end if;

  mode := case
    when subscription.state in ('active', 'trialing') then 'write'
    when subscription.state = 'grace' and subscription.grace_ends_at > effective_time then 'write'
    when subscription.state in ('grace', 'read_only', 'ended') then 'read_only'
    else 'denied'
  end;

  insert into core.club_entitlements(
    club_id,billing_account_id,entitlement_key,access_mode,quantity,
    source_subscription_revision,effective_at,expires_at
  ) values (
    account.club_id,account.id,replace(subscription.base_plan_key,'plan.','base.'),mode,null,
    subscription.revision,effective_time,
    case when subscription.state = 'grace' then subscription.grace_ends_at else null end
  );

  insert into core.club_entitlements(
    club_id,billing_account_id,entitlement_key,access_mode,quantity,
    source_subscription_revision,effective_at,expires_at
  )
  select account.club_id,account.id,item.entitlement_key,mode,item.quantity,
    subscription.revision,effective_time,item.ends_at
  from core.billing_subscription_items item
  where item.subscription_id = subscription.id and item.state = 'active'
    and item.starts_at <= effective_time
    and (item.ends_at is null or item.ends_at > effective_time);
end;
$$;

create function internal.entitlement_allows_write(target_club_id uuid, target_entitlement_key text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from core.club_entitlements entitlement
    where entitlement.club_id = target_club_id
      and entitlement.entitlement_key = target_entitlement_key
      and entitlement.access_mode = 'write'
      and (entitlement.expires_at is null or entitlement.expires_at > now())
  );
$$;

create function internal.get_club_entitlements_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if not internal.actor_has_club_access(target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select jsonb_build_object(
    'club_id', target_club_id,
    'billing_state', coalesce((select subscription.state
      from core.billing_accounts account
      join core.billing_subscriptions subscription on subscription.billing_account_id = account.id
      where account.club_id = target_club_id and account.environment = 'production'), 'unconfigured'),
    'entitlements', coalesce(jsonb_agg(jsonb_build_object(
      'key', entitlement.entitlement_key,
      'access_mode', entitlement.access_mode,
      'quantity', entitlement.quantity,
      'expires_at', entitlement.expires_at
    ) order by entitlement.entitlement_key) filter (where entitlement.id is not null), '[]'::jsonb)
  ) into result
  from core.club_entitlements entitlement
  where entitlement.club_id = target_club_id;
  return result;
end;
$$;

revoke all on function internal.recompute_club_entitlements(uuid),
  internal.entitlement_allows_write(uuid,text),
  internal.get_club_entitlements_for_actor(uuid)
  from public, anon, authenticated;
grant execute on function internal.get_club_entitlements_for_actor(uuid) to authenticated;

create function api.get_club_entitlements(target_club_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as
$$select internal.get_club_entitlements_for_actor(target_club_id)$$;
revoke all on function api.get_club_entitlements(uuid) from public, anon;
grant execute on function api.get_club_entitlements(uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind)
values('20260816111500_s10a_entitlement_foundation','greenfield');
