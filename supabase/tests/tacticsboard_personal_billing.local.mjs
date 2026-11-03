// Tacticsboard sold per person (20270204090000): the billing account, the
// 7-day trial that starts once, and webtool.tacticsboard, in PGlite.
// node supabase/tests/tacticsboard_personal_billing.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const buyer = id(1), other = id(2), guest = id(3);
const as = (who, anonymous = false) => db.query(
  "select set_config('request.jwt.claim.sub',$1,false), set_config('request.jwt.claims',$2,false)",
  [who ?? '', JSON.stringify({ sub: who, is_anonymous: anonymous })]);
const call = async (who, sql, params = [], anonymous = false) => {
  // No finally: in an aborted transaction it would hide the real error; the rollback resets the role.
  await as(who, anonymous); await db.exec('set role authenticated');
  const value = Object.values((await db.query(sql, params)).rows[0] ?? {})[0];
  await db.exec('reset role');
  return value;
};
const fails = async (who, sql, pattern, anonymous = false) => {
  await db.exec('savepoint s');
  await assert.rejects(call(who, sql, [], anonymous), pattern);
  await db.exec('rollback to s');
};
await db.exec(`create role anon; create role authenticated; create role service_role;
create schema internal; create schema api; create schema core; create schema auth; create schema audit;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
create table core.profiles(id uuid primary key);
insert into core.profiles values ('${buyer}'),('${other}'),('${guest}');
create table audit.command_events(id bigserial, club_id uuid, actor_profile_id uuid, command_type text, aggregate_type text,
  aggregate_id uuid, metadata jsonb);
grant usage on schema api, internal, core, auth to authenticated;`);
await db.exec(read('supabase/migrations/20270204090000_tacticsboard_personal_billing.sql'));
await db.exec('begin');

// Before the trial: locked, and the trial can be started.
let access = await call(buyer, 'select api.get_my_tacticsboard_access()');
assert.equal(access.access_mode, 'denied');
assert.equal(access.trial_available, true);
assert.equal(await call(buyer, 'select internal.actor_has_tacticsboard()'), false);

// Starting it gives seven days of write access, logged once.
access = await call(buyer, 'select api.start_tacticsboard_trial()');
assert.equal(access.access_mode, 'write');
assert.equal(access.source, 'trial');
assert.equal(access.trial_available, false);
const days = (new Date(access.trial_ends_at) - Date.now()) / 86400000;
assert.ok(days > 6.99 && days <= 7, `trial is 7 days, got ${days}`);
assert.equal(await call(buyer, 'select internal.actor_has_tacticsboard()'), true);
const firstEnd = access.trial_ends_at;
access = await call(buyer, 'select api.start_tacticsboard_trial()');
assert.equal(access.trial_ends_at, firstEnd);
assert.equal((await db.query("select count(*)::int n from audit.command_events where command_type='billing.personal_trial.started.v1'")).rows[0].n, 1);

// Another person has their own, untouched status.
assert.equal((await call(other, 'select api.get_my_tacticsboard_access()')).access_mode, 'denied');

// After the trial: locked, and it cannot be started again.
await db.exec(`update core.personal_billing_accounts set trial_started_at = now() - interval '8 days',
  trial_ends_at = now() - interval '1 day' where profile_id = '${buyer}'`);
access = await call(buyer, 'select api.start_tacticsboard_trial()');
assert.equal(access.access_mode, 'denied');
assert.equal(access.source, 'none');
assert.equal(access.trial_available, false);

// A paid subscription opens it; grace keeps it open until it ends; ended locks it.
const subscribe = (state, extra = '') => db.exec(`delete from core.personal_billing_subscriptions;
  insert into core.personal_billing_subscriptions(profile_id, provider, provider_subscription_ref_hash, billing_interval, state,
    current_period_ends_at, grace_ends_at) values ('${buyer}', 'stripe', sha256('sub_1'), 'month', '${state}', ${extra})`);
await subscribe('active', "now() + interval '20 days', null");
access = await call(buyer, 'select api.get_my_tacticsboard_access()');
assert.deepEqual([access.access_mode, access.source, access.subscription_state, access.billing_interval], ['write', 'subscription', 'active', 'month']);
await subscribe('active', "now() - interval '1 day', null");
assert.equal((await call(buyer, 'select api.get_my_tacticsboard_access()')).access_mode, 'denied');
await subscribe('grace', "now() - interval '1 day', now() + interval '3 days'");
access = await call(buyer, 'select api.get_my_tacticsboard_access()');
assert.deepEqual([access.access_mode, access.source], ['write', 'grace']);
await subscribe('grace', "now() - interval '20 days', now() - interval '1 hour'");
assert.equal((await call(buyer, 'select api.get_my_tacticsboard_access()')).access_mode, 'denied');
await subscribe('ended', "now() - interval '1 day', null");
assert.equal((await call(buyer, 'select internal.actor_has_tacticsboard()')), false);

// Guests and the signed-out get nothing, and no trial.
await fails(guest, 'select api.start_tacticsboard_trial()', /not_signed_in/, true);
await fails(null, 'select api.get_my_tacticsboard_access()', /not_signed_in/);
assert.equal((await db.query(`select count(*)::int n from core.personal_billing_accounts where profile_id = '${guest}'`)).rows[0].n, 0);

// The tables are closed to clients, and the helper that takes any profile is not callable.
await fails(buyer, 'select * from core.personal_billing_accounts', /permission denied/);
await fails(buyer, 'select * from core.personal_billing_subscriptions', /permission denied/);
await fails(buyer, `select internal.personal_entitlement_status('${other}', 'webtool.tacticsboard')`, /permission denied/);
await db.exec('rollback');
console.log('tacticsboard personal billing: ok');
