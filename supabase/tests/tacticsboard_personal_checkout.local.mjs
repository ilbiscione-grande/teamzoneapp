// Tacticsboard checkout and webhook per person (20270205090000), on top of
// 20270204090000, in PGlite: prepare and claim, Stripe's events in either
// order, duplicates, stale and foreign events, grace and the end.
// node supabase/tests/tacticsboard_personal_checkout.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const buyer = id(1), early = id(2), stranger = id(3);
const key = n => `00000000-0000-4000-9000-${String(n).padStart(12, '0')}`;
const as = (who, role = 'authenticated') => db.query(
  "select set_config('request.jwt.claim.sub',$1,false), set_config('request.jwt.claims',$2,false), set_config('role',$3,false)",
  [who ?? '', JSON.stringify({ sub: who }), role]);
const call = async (who, sql, params = [], role = 'authenticated') => {
  await as(who, role);
  const value = Object.values((await db.query(sql, params)).rows[0] ?? {})[0];
  await db.exec('reset role');
  return value;
};
const fails = async (who, sql, params, pattern, role) => {
  await db.exec('savepoint s');
  await assert.rejects(call(who, sql, params, role), pattern);
  await db.exec('rollback to s');
};
const access = who => call(who, 'select api.get_my_tacticsboard_access()');
let eventNumber = 0;
const ingest = (type, object, created = 1000 + eventNumber) => call(null,
  'select api.ingest_tacticsboard_stripe_event($1,$2,$3,false,$4)',
  [`evt_${++eventNumber}`, created, type, JSON.stringify({ data: { object } })], 'service_role');
const subscription = (fields = {}) => ({
  id: 'sub_1', customer: 'cus_1', status: 'active', cancel_at_period_end: false,
  items: { data: [{ price: { id: 'price_Month' }, current_period_end: Math.floor(Date.now() / 1000) + 30 * 86400 }] },
  metadata: { teamzone_product: 'webtool.tacticsboard', checkout_request_id: fields.request }, ...fields,
});

await db.exec(`create role anon; create role authenticated; create role service_role;
create schema internal; create schema api; create schema core; create schema auth; create schema audit; create schema extensions;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
create function extensions.digest(value text, algorithm text) returns bytea language sql immutable as $$select sha256(convert_to(value,'utf8'))$$;
create table core.profiles(id uuid primary key);
insert into core.profiles values ('${buyer}'),('${early}'),('${stranger}');
create table audit.command_events(id bigserial, club_id uuid, actor_profile_id uuid, command_type text, aggregate_type text,
  aggregate_id uuid, metadata jsonb);
create table internal.billing_provider_events(id uuid primary key default gen_random_uuid(), provider text, environment text,
  provider_event_id_hash bytea, provider_revision bigint, event_type text, payload_sha256 bytea, signature_verified_at timestamptz,
  received_at timestamptz default now(), processed_at timestamptz, processing_state text default 'pending', failure_code text,
  unique (provider, environment, provider_event_id_hash));
grant usage on schema api, internal, core, auth, extensions to authenticated, service_role;`);
for (const name of ['20270204090000_tacticsboard_personal_billing', '20270205090000_tacticsboard_personal_checkout'])
  await db.exec(read(`supabase/migrations/${name}.sql`));
await db.exec(`insert into internal.personal_billing_prices(billing_interval, livemode, provider_price_ref, provider_coupon_ref, coupon_ends_at)
  values ('month', false, 'price_Month', null, null), ('year', false, 'price_Year', 'launch50', now() + interval '50 days'),
         ('month', true, 'price_LiveMonth', null, null)`);
await db.exec('begin');

// Without a price for the mode, a checkout cannot be claimed.
const first = await call(buyer, "select api.prepare_tacticsboard_checkout('year',$1)", [key(1)]);
assert.equal((await call(buyer, "select api.prepare_tacticsboard_checkout('year',$1)", [key(1)])).checkout_request_id, first.checkout_request_id);
await fails(buyer, "select api.prepare_tacticsboard_checkout('month',$1)", [key(1)], /idempotency_conflict/);
await fails(buyer, "select api.prepare_tacticsboard_checkout('week',$1)", [key(2)], /invalid_checkout/);
await fails(buyer, 'select api.claim_tacticsboard_checkout($1,false)', [first.checkout_request_id], /permission denied/);

// The yearly price gets the launch coupon; the trial's rest carries over.
await call(buyer, 'select api.start_tacticsboard_trial()');
let claimed = await call(null, 'select api.claim_tacticsboard_checkout($1,false)', [first.checkout_request_id], 'service_role');
assert.equal(claimed.provider_price_ref, 'price_Year');
assert.equal(claimed.provider_coupon_ref, 'launch50');
assert.equal(claimed.provider_customer_ref, null);
assert.equal(claimed.profile_id, buyer);
assert.ok(claimed.trial_ends_at);
await db.exec("update internal.personal_billing_prices set coupon_ends_at = now() - interval '1 second' where provider_price_ref = 'price_Year'");
claimed = await call(null, 'select api.claim_tacticsboard_checkout($1,false)', [first.checkout_request_id], 'service_role');
assert.equal(claimed.provider_coupon_ref, null);

// A monthly checkout; the subscription event comes before the session's.
const monthly = (await call(buyer, "select api.prepare_tacticsboard_checkout('month',$1)", [key(3)])).checkout_request_id;
await call(null, 'select api.claim_tacticsboard_checkout($1,false)', [monthly], 'service_role');
let result = await ingest('customer.subscription.created', subscription({ request: monthly }));
assert.equal(result.state, 'processed');
let status = await access(buyer);
assert.deepEqual([status.access_mode, status.source, status.billing_interval], ['write', 'subscription', 'month']);
result = await ingest('checkout.session.completed', { id: 'cs_1', customer: 'cus_1', subscription: 'sub_1', client_reference_id: monthly,
  metadata: { teamzone_product: 'webtool.tacticsboard', checkout_request_id: monthly } });
assert.equal(result.state, 'processed');
assert.equal(await call(null, 'select api.tacticsboard_billing_customer($1,false)', [buyer], 'service_role'), 'cus_1');
assert.equal(await call(null, 'select api.tacticsboard_billing_customer($1,true)', [buyer], 'service_role'), null);
await fails(buyer, 'select api.tacticsboard_billing_customer($1,false)', [buyer], /permission denied/);

// The same event twice is a duplicate.
await db.query(`select api.ingest_tacticsboard_stripe_event('evt_dup',5000,'customer.subscription.updated',false,$1)`,
  [JSON.stringify({ data: { object: subscription({ request: monthly }) } })]).catch(() => {});
await as(null, 'service_role');
assert.equal((await db.query(`select api.ingest_tacticsboard_stripe_event('evt_dup',5000,'customer.subscription.updated',false,$1) r`,
  [JSON.stringify({ data: { object: subscription({ request: monthly }) } })])).rows[0].r.duplicate, true);
await db.exec('reset role');

// While subscribed, no new checkout and no trial.
await fails(buyer, "select api.prepare_tacticsboard_checkout('year',$1)", [key(4)], /already_subscribed/);

// An older event is ignored; a later one with the end at the period's close is kept.
assert.equal((await ingest('customer.subscription.updated', subscription({ request: monthly, status: 'canceled' }), 10)).state, 'ignored_stale');
await ingest('customer.subscription.updated', subscription({ request: monthly, cancel_at_period_end: true }), 6000);
assert.equal((await access(buyer)).cancel_at_period_end, true);

// A failed renewal: grace for 14 days from the first failure, then locked.
await ingest('customer.subscription.updated', subscription({ request: monthly, status: 'past_due' }), 7000);
status = await access(buyer);
assert.deepEqual([status.access_mode, status.source], ['write', 'grace']);
const firstGrace = status.grace_ends_at;
await ingest('customer.subscription.updated', subscription({ request: monthly, status: 'unpaid' }), 8000);
assert.equal((await access(buyer)).grace_ends_at, firstGrace);
await db.exec(`update core.personal_billing_subscriptions set grace_ends_at = now() - interval '1 second' where profile_id = '${buyer}'`);
await db.exec(`update core.personal_billing_accounts set trial_ends_at = now() - interval '1 second', trial_started_at = now() - interval '8 days' where profile_id = '${buyer}'`);
assert.equal((await access(buyer)).access_mode, 'denied');
await ingest('customer.subscription.updated', subscription({ request: monthly }), 9000);
assert.equal((await access(buyer)).source, 'subscription');
await ingest('customer.subscription.deleted', subscription({ request: monthly, status: 'canceled' }), 10000);
status = await access(buyer);
assert.deepEqual([status.access_mode, status.subscription_state, status.trial_available], ['denied', 'ended', false]);

// Someone who buys at once never gets a trial afterwards.
const direct = (await call(early, "select api.prepare_tacticsboard_checkout('month',$1)", [key(5)])).checkout_request_id;
await ingest('customer.subscription.created', subscription({ id: 'sub_2', customer: 'cus_2', request: direct }), 11000);
assert.equal((await access(early)).source, 'subscription');
await ingest('customer.subscription.deleted', subscription({ id: 'sub_2', customer: 'cus_2', request: direct, status: 'canceled' }), 12000);
status = await call(early, 'select api.start_tacticsboard_trial()');
assert.deepEqual([status.access_mode, status.trial_available], ['denied', false]);

// Foreign events: no request, an unknown price, a live event for a test price, no customer.
for (const [type, object] of [
  ['customer.subscription.created', subscription({ id: 'sub_3', request: key(99) })],
  ['customer.subscription.created', subscription({ id: 'sub_4', request: direct, items: { data: [{ price: { id: 'price_Other' } }] } })],
  ['checkout.session.completed', { customer: 'cus_9', client_reference_id: 'not-a-uuid' }],
  ['customer.subscription.created', subscription({ id: 'sub_5', customer: null, request: direct })],
  ['invoice.paid', { customer: 'cus_1' }],
]) assert.equal((await ingest(type, object)).state, 'rejected');
const live = await call(null, 'select api.ingest_tacticsboard_stripe_event($1,20000,$2,true,$3)',
  ['evt_live', 'customer.subscription.created', JSON.stringify({ data: { object: subscription({ id: 'sub_6', customer: 'cus_6', request: direct }) } })], 'service_role');
assert.equal(live.state, 'rejected');
await fails(null, "select api.ingest_tacticsboard_stripe_event('bad',1,'x',false,'{}')", [], /invalid_provider_event/, 'service_role');
await fails(stranger, "select api.ingest_tacticsboard_stripe_event('evt_x',1,'x',false,'{}')", [], /permission denied/);
assert.equal((await access(stranger)).trial_available, true);
await db.exec('rollback');
console.log('tacticsboard personal checkout: ok');
