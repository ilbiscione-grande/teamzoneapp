-- S10A checkout request and Stripe webhook command boundary.
-- Runtime remains disabled and the only pricebook is still draft.

create table internal.billing_provider_prices (
  id uuid primary key default gen_random_uuid(),
  pricebook_version text not null,
  plan_key text not null,
  billing_interval text not null check (billing_interval in ('month','year')),
  provider text not null check (provider = 'stripe'),
  provider_price_ref text not null check (provider_price_ref ~ '^price_[A-Za-z0-9]+$'),
  provider_price_ref_hash bytea generated always as
    (extensions.digest(provider_price_ref,'sha256')) stored,
  active boolean not null default false,
  created_at timestamptz not null default now(),
  unique (pricebook_version,plan_key,billing_interval,provider),
  unique (provider,provider_price_ref_hash),
  foreign key (pricebook_version,plan_key)
    references core.billing_pricebook_plans(pricebook_version,plan_key)
);

create table internal.billing_checkout_requests (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  actor_profile_id uuid not null references core.profiles(id),
  idempotency_key uuid not null,
  pricebook_version text not null,
  plan_key text not null,
  billing_interval text not null check (billing_interval in ('month','year')),
  provider text not null check (provider = 'stripe'),
  state text not null default 'prepared'
    check (state in ('prepared','claimed','session_created','completed','expired','failed')),
  provider_session_ref_hash bytea,
  prepared_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '15 minutes',
  updated_at timestamptz not null default now(),
  unique (actor_profile_id,idempotency_key),
  foreign key (pricebook_version,plan_key)
    references core.billing_pricebook_plans(pricebook_version,plan_key),
  check (expires_at > prepared_at),
  check (provider_session_ref_hash is null or octet_length(provider_session_ref_hash)=32)
);

create index billing_checkout_requests_state_expiry_idx
  on internal.billing_checkout_requests(state,expires_at);

create function internal.prepare_billing_checkout_for_actor(
  target_club_id uuid,target_plan_key text,target_interval text,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); existing internal.billing_checkout_requests%rowtype;
  pricebook core.billing_pricebooks%rowtype; request_id uuid;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,null,'club.billing.manage') then
  raise insufficient_privilege using message='not_found';
 end if;
 if target_interval not in ('month','year') then raise check_violation using message='invalid_checkout'; end if;
 select * into existing from internal.billing_checkout_requests
  where actor_profile_id=actor_id and idempotency_key=p_idempotency_key;
 if existing.id is not null then
  if existing.club_id<>target_club_id or existing.plan_key<>target_plan_key
    or existing.billing_interval<>target_interval then
   raise unique_violation using message='idempotency_conflict';
  end if;
  return jsonb_build_object('checkout_request_id',existing.id);
 end if;
 select * into pricebook from core.billing_pricebooks
  where market='se' and state='published';
 if pricebook.version is null or not exists(
  select 1 from internal.billing_provider_prices price
  join core.billing_pricebook_plans plan on plan.pricebook_version=price.pricebook_version
   and plan.plan_key=price.plan_key
  where price.pricebook_version=pricebook.version and price.plan_key=target_plan_key
   and price.billing_interval=target_interval and price.provider='stripe' and price.active
   and not plan.quote_required
 ) then raise check_violation using message='billing_unavailable'; end if;
 insert into internal.billing_checkout_requests(
  club_id,actor_profile_id,idempotency_key,pricebook_version,plan_key,billing_interval,provider
 ) values(target_club_id,actor_id,p_idempotency_key,pricebook.version,target_plan_key,target_interval,'stripe')
 returning id into request_id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,metadata)
 values(target_club_id,actor_id,'billing.checkout.prepared.v1','billing_checkout',request_id,
  jsonb_build_object('pricebook_version',pricebook.version,'plan_key',target_plan_key,'interval',target_interval));
 return jsonb_build_object('checkout_request_id',request_id);
end; $$;

create function internal.claim_billing_checkout_for_server(target_checkout_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare request internal.billing_checkout_requests%rowtype; price_ref text;
begin
 select * into request from internal.billing_checkout_requests
  where id=target_checkout_request_id for update;
 if request.id is null or request.expires_at<=now() or request.state not in ('prepared','claimed') then
  raise check_violation using message='checkout_unavailable';
 end if;
 select provider_price_ref into price_ref from internal.billing_provider_prices
  where pricebook_version=request.pricebook_version and plan_key=request.plan_key
   and billing_interval=request.billing_interval and provider=request.provider and active;
 if price_ref is null then raise check_violation using message='checkout_unavailable'; end if;
 update internal.billing_checkout_requests set state='claimed',updated_at=now() where id=request.id;
 return jsonb_build_object('checkout_request_id',request.id,'provider_price_ref',price_ref);
end; $$;

create function internal.ingest_stripe_event_for_server(
 provider_event_id text,provider_created_at bigint,event_type text,livemode boolean,payload jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare event_hash bytea; event_environment text:=case when livemode then 'production' else 'test' end;
  inserted_id uuid; object jsonb:=payload->'data'->'object'; customer_ref text;
  subscription_ref text; checkout_id uuid; account core.billing_accounts%rowtype;
  subscription core.billing_subscriptions%rowtype; mapped_state text; price_ref text;
  mapping internal.billing_provider_prices%rowtype;
begin
 if provider_event_id!~'^evt_[A-Za-z0-9]+$' or provider_created_at<=0
   or jsonb_typeof(object) is distinct from 'object' then raise check_violation using message='invalid_provider_event'; end if;
 event_hash:=extensions.digest(provider_event_id,'sha256');
 insert into internal.billing_provider_events(provider,environment,provider_event_id_hash,
  provider_revision,event_type,payload_sha256,signature_verified_at)
 values('stripe',event_environment,event_hash,provider_created_at,event_type,
  extensions.digest(payload::text,'sha256'),now())
 on conflict(provider,environment,provider_event_id_hash) do nothing returning id into inserted_id;
 if inserted_id is null then return jsonb_build_object('duplicate',true); end if;

 if event_type='checkout.session.completed' then
  begin checkout_id:=(object->>'client_reference_id')::uuid; exception when others then checkout_id:=null; end;
  customer_ref:=object->>'customer'; subscription_ref:=object->>'subscription';
  if checkout_id is null or coalesce(customer_ref!~'^cus_[A-Za-z0-9]+$',true)
    or coalesce(subscription_ref!~'^sub_[A-Za-z0-9]+$',true) then
   update internal.billing_provider_events set processing_state='rejected',processed_at=now(),failure_code='invalid_checkout_event' where id=inserted_id;
   return jsonb_build_object('accepted',false);
  end if;
  select * into account from core.billing_accounts account_row
   where account_row.club_id=(select club_id from internal.billing_checkout_requests where id=checkout_id)
   and account_row.environment=event_environment;
  if account.id is null then
   insert into core.billing_accounts(club_id,environment,state,provider,provider_customer_ref_hash)
   select club_id,event_environment,'unknown','stripe',extensions.digest(customer_ref,'sha256')
   from internal.billing_checkout_requests where id=checkout_id returning * into account;
  end if;
  insert into core.billing_subscriptions(billing_account_id,provider_subscription_ref_hash,
   provider_revision,pricebook_version,base_plan_key,state)
  select account.id,extensions.digest(subscription_ref,'sha256'),provider_created_at,
   pricebook_version,plan_key,'unknown' from internal.billing_checkout_requests where id=checkout_id
  on conflict(billing_account_id) do update set
   provider_subscription_ref_hash=excluded.provider_subscription_ref_hash,
   provider_revision=greatest(core.billing_subscriptions.provider_revision,excluded.provider_revision),
   updated_at=now(),revision=core.billing_subscriptions.revision+1;
  update internal.billing_checkout_requests set state='completed',updated_at=now() where id=checkout_id;
  update internal.billing_provider_events set processing_state='processed',processed_at=now() where id=inserted_id;
  return jsonb_build_object('accepted',true);
 end if;

 if event_type in ('customer.subscription.created','customer.subscription.updated','customer.subscription.deleted') then
  customer_ref:=object->>'customer'; subscription_ref:=object->>'id';
  price_ref:=object#>>'{items,data,0,price,id}';
  select * into account from core.billing_accounts account_row where account_row.provider='stripe'
   and account_row.provider_customer_ref_hash=extensions.digest(customer_ref,'sha256')
   and account_row.environment=event_environment;
  select * into subscription from core.billing_subscriptions where billing_account_id=account.id for update;
  select * into mapping from internal.billing_provider_prices where provider='stripe'
   and provider_price_ref_hash=extensions.digest(price_ref,'sha256') and active;
  if account.id is null or subscription.id is null or mapping.id is null
   or subscription.provider_subscription_ref_hash<>extensions.digest(subscription_ref,'sha256') then
   update internal.billing_provider_events set processing_state='retryable_failure',failure_code='subscription_not_bound' where id=inserted_id;
   raise serialization_failure using message='subscription_not_bound';
  end if;
  if subscription.provider_revision is not null and provider_created_at<subscription.provider_revision then
   update internal.billing_provider_events set processing_state='ignored_stale',processed_at=now() where id=inserted_id;
   return jsonb_build_object('ignored_stale',true);
  end if;
  mapped_state:=case
   when event_type='customer.subscription.deleted' then 'grace'
   when object->>'status'='active' then 'active'
   when object->>'status'='trialing' then 'trialing'
   when object->>'status' in ('past_due','unpaid','paused','canceled') then 'grace'
   else 'unknown' end;
  update core.billing_subscriptions set provider_revision=provider_created_at,
   pricebook_version=mapping.pricebook_version,base_plan_key=mapping.plan_key,state=mapped_state,
   current_period_starts_at=to_timestamp(nullif(object->>'current_period_start','')::double precision),
   current_period_ends_at=to_timestamp(nullif(object->>'current_period_end','')::double precision),
   grace_ends_at=case when mapped_state='grace' then now()+interval '14 days' else null end,
   updated_at=now(),revision=revision+1 where id=subscription.id;
  perform internal.recompute_club_entitlements(account.id);
  update internal.billing_provider_events set processing_state='processed',processed_at=now() where id=inserted_id;
  insert into audit.command_events(club_id,command_type,aggregate_type,aggregate_id,metadata)
   values(account.club_id,'billing.entitlement.changed.v1','billing_account',account.id,
    jsonb_build_object('state',mapped_state,'provider_revision',provider_created_at));
  return jsonb_build_object('accepted',true);
 end if;

 update internal.billing_provider_events set processing_state='rejected',processed_at=now(),failure_code='event_type_not_allowed' where id=inserted_id;
 return jsonb_build_object('accepted',false);
end; $$;

create function api.prepare_billing_checkout(target_club_id uuid,target_plan_key text,
 target_interval text,idempotency_key uuid) returns jsonb language sql security invoker set search_path='' as
$$select internal.prepare_billing_checkout_for_actor(target_club_id,target_plan_key,target_interval,idempotency_key)$$;
create function api.claim_billing_checkout(target_checkout_request_id uuid) returns jsonb
 language sql security invoker set search_path='' as
$$select internal.claim_billing_checkout_for_server(target_checkout_request_id)$$;
create function api.ingest_stripe_event(provider_event_id text,provider_created_at bigint,
 event_type text,livemode boolean,payload jsonb) returns jsonb language sql security invoker set search_path='' as
$$select internal.ingest_stripe_event_for_server(provider_event_id,provider_created_at,event_type,livemode,payload)$$;

revoke all on function internal.prepare_billing_checkout_for_actor(uuid,text,text,uuid),
 internal.claim_billing_checkout_for_server(uuid),
 internal.ingest_stripe_event_for_server(text,bigint,text,boolean,jsonb),
 api.prepare_billing_checkout(uuid,text,text,uuid),api.claim_billing_checkout(uuid),
 api.ingest_stripe_event(text,bigint,text,boolean,jsonb) from public,anon,authenticated;
grant execute on function internal.prepare_billing_checkout_for_actor(uuid,text,text,uuid),
 api.prepare_billing_checkout(uuid,text,text,uuid) to authenticated;
grant execute on function internal.claim_billing_checkout_for_server(uuid),
 internal.ingest_stripe_event_for_server(text,bigint,text,boolean,jsonb),
 api.claim_billing_checkout(uuid),api.ingest_stripe_event(text,bigint,text,boolean,jsonb) to service_role;

insert into internal.migration_provenance(migration_name,source_kind)
values('20260816111800_s10a_checkout_webhook_commands','greenfield');
