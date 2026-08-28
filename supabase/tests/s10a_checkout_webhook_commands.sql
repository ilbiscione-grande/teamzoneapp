begin;
set local role postgres;

insert into auth.users(id,raw_user_meta_data) values
 ('b1000000-0000-4000-8000-000000000001','{"display_name":"Billing Admin"}'),
 ('b1000000-0000-4000-8000-000000000002','{"display_name":"Outsider"}');
insert into core.clubs(id,name,slug) values
 ('b1100000-0000-4000-8000-000000000001','Billing Klubb','billing-klubb');
insert into core.club_people(id,club_id,display_name) values
 ('b1200000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000001','Billing Admin');
insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at) values
 ('b1100000-0000-4000-8000-000000000001','b1200000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000001','active',now());
insert into core.assignments(id,club_id,club_person_id,role_package,state,starts_at) values
 ('b1300000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000001',
  'b1200000-0000-4000-8000-000000000001','club_functionary','active',now()-interval '1 day');
insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at) values
 ('b1100000-0000-4000-8000-000000000001','b1300000-0000-4000-8000-000000000001',
  'club.billing.manage','club','b1100000-0000-4000-8000-000000000001',now()-interval '1 day');

set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin
  perform api.prepare_billing_checkout('b1100000-0000-4000-8000-000000000001','plan.small','month',
   'b1400000-0000-4000-8000-000000000001');
  raise exception 'draft pricebook allowed checkout';
 exception when check_violation then null; end;
end $$;

set local role postgres;
update core.billing_pricebooks set state='published',published_at=now() where version='se.v1-draft';
insert into internal.billing_provider_prices(pricebook_version,plan_key,billing_interval,provider,provider_price_ref,active)
values('se.v1-draft','plan.small','month','stripe','price_smallmonthlytest',true);

set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000001',true);
select api.prepare_billing_checkout(
 'b1100000-0000-4000-8000-000000000001','plan.small','month',
 'b1400000-0000-4000-8000-000000000002');
select api.prepare_billing_checkout(
 'b1100000-0000-4000-8000-000000000001','plan.small','month',
 'b1400000-0000-4000-8000-000000000002');

set local role postgres;
select set_config('test.checkout_request_id',(
 select id::text from internal.billing_checkout_requests
 where idempotency_key='b1400000-0000-4000-8000-000000000002'
),true);

set local role service_role;
select api.claim_billing_checkout(current_setting('test.checkout_request_id')::uuid);
select api.ingest_stripe_event('evt_checkout1',1000,'checkout.session.completed',false,
 jsonb_build_object('data',jsonb_build_object('object',jsonb_build_object(
  'client_reference_id',current_setting('test.checkout_request_id'),'customer','cus_test1','subscription','sub_test1'))));
select api.ingest_stripe_event('evt_subscription1',1100,'customer.subscription.updated',false,
 jsonb_build_object('data',jsonb_build_object('object',jsonb_build_object(
  'id','sub_test1','customer','cus_test1','status','active',
  'current_period_start',extract(epoch from now())::bigint,
  'current_period_end',extract(epoch from now()+interval '30 days')::bigint,
  'items',jsonb_build_object('data',jsonb_build_array(jsonb_build_object(
    'price',jsonb_build_object('id','price_smallmonthlytest'))))))));
select api.ingest_stripe_event('evt_subscription1',1100,'customer.subscription.updated',false,
 jsonb_build_object('data',jsonb_build_object('object',jsonb_build_object('id','sub_test1'))));
select api.ingest_stripe_event('evt_subscriptionold',1050,'customer.subscription.updated',false,
 jsonb_build_object('data',jsonb_build_object('object',jsonb_build_object(
  'id','sub_test1','customer','cus_test1','status','past_due',
  'items',jsonb_build_object('data',jsonb_build_array(jsonb_build_object(
    'price',jsonb_build_object('id','price_smallmonthlytest'))))))));

set local role postgres;
do $$ begin
 if (select state from core.billing_subscriptions) <> 'active' then raise exception 'subscription not active'; end if;
 if not internal.entitlement_allows_write('b1100000-0000-4000-8000-000000000001','base.small')
  then raise exception 'active base entitlement missing'; end if;
 if (select count(*) from internal.billing_provider_events) <> 3
  then raise exception 'provider dedupe failed'; end if;
 if (select processing_state from internal.billing_provider_events where provider_revision=1050) <> 'ignored_stale'
  then raise exception 'out-of-order event not ignored'; end if;
 if has_function_privilege('authenticated','api.claim_billing_checkout(uuid)','execute')
   or has_function_privilege('authenticated','api.ingest_stripe_event(text,bigint,text,boolean,jsonb)','execute')
  then raise exception 'server RPC exposed'; end if;
end $$;

rollback;
