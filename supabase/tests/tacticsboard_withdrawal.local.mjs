// Withdrawals from a Tacticsboard purchase (20270209090000) in PGlite: one per
// purchase, only for the server, and kept after the account is gone.
// node supabase/tests/tacticsboard_withdrawal.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const buyer = '00000000-0000-4000-8000-000000000001';
await db.exec(`
  create role anon nologin; create role authenticated nologin; create role service_role nologin;
  create schema core; create schema internal; create schema api;
  grant usage on schema core, internal, api to anon, authenticated, service_role;
  create table core.profiles (id uuid primary key);
  insert into core.profiles values ('${buyer}');
`);
await db.exec(read('supabase/migrations/20270209090000_tacticsboard_withdrawals.sql'));

const asRole = async (role, sql, params = []) => {
  await db.exec(`set role ${role}`);
  try { return Object.values((await db.query(sql, params)).rows[0] ?? {})[0]; }
  finally { await db.exec('reset role'); }
};
const record = (role, ref = 'sub_1', name = 'Anna A') => asRole(role,
  "select api.record_tacticsboard_withdrawal($1,false,$2,$3,'a@b.se','2026-11-05T06:00:00Z')", [buyer, ref, name]);

await assert.rejects(record('authenticated'), /permission denied/);
await assert.rejects(record('anon'), /permission denied/);
await assert.rejects(asRole('authenticated', 'select * from internal.personal_billing_withdrawals'), /permission denied/);

const first = await record('service_role', 'sub_1', '  Anna A ');
assert.ok(first.id);
assert.equal(first.receipt_sent_at, null);
const again = await record('service_role', 'sub_1', 'Någon annan');
assert.deepEqual(again, first);
assert.equal((await db.query('select customer_name from internal.personal_billing_withdrawals')).rows[0].customer_name, 'Anna A');
assert.equal(await asRole('service_role', 'select api.tacticsboard_withdrawal($1)', ['sub_none']), null);

await asRole('service_role', 'select api.mark_tacticsboard_withdrawal_receipt($1)', [first.id]);
const marked = await asRole('service_role', 'select api.tacticsboard_withdrawal($1)', ['sub_1']);
assert.ok(marked.receipt_sent_at);

await assert.rejects(record('service_role', 'not_a_sub'), /check/);
await assert.rejects(record('service_role', 'sub_2', '  '), /check/);

await db.exec(`delete from core.profiles where id = '${buyer}'`);
const kept = (await db.query('select profile_id, customer_email from internal.personal_billing_withdrawals')).rows[0];
assert.deepEqual(kept, { profile_id: null, customer_email: 'a@b.se' });
console.log('tacticsboard withdrawal: ok');
