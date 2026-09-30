// Isolated check of 20260930130000_enforce_login_email_change.sql.
// Run: node supabase/tests/login_email_guard.local.mjs
import fs from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const user = '00000000-0000-0000-0000-000000000012';
await db.exec(`
create schema core; create schema internal; create schema auth;
create role authenticated; create role anon;
create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
create table auth.users(id uuid primary key,email text,email_change text default '');
create table core.login_email_change_requests(id uuid primary key default gen_random_uuid(),profile_id uuid,
  requested_email text,state text);
insert into auth.users(id,email) values('${user}','ada@x.se');
`);
await db.exec(fs.readFileSync('supabase/migrations/20260930130000_enforce_login_email_change.sql', 'utf8'));

const assert = (ok, msg) => { if (!ok) throw new Error(msg); console.log('ok -', msg); };
const refused = async (sql) => {
  try { await db.exec(sql); return false; } catch (e) { return /email_change_requires_support/.test(e.message); }
};
const row = async () => (await db.query(`select email,email_change from auth.users where id='${user}'`)).rows[0];

// Without support approval nothing changes.
assert(await refused(`update auth.users set email_change='egen@mail.se' where id='${user}'`),
  'starting a change without approval is refused');
assert(await refused(`update auth.users set email='egen@mail.se' where id='${user}'`),
  'switching the email without approval is refused');
assert((await row()).email === 'ada@x.se', 'login email is unchanged');

// Pending or rejected requests are not enough.
await db.exec(`insert into core.login_email_change_requests(profile_id,requested_email,state)
  values('${user}','ny@mail.se','pending')`);
assert(await refused(`update auth.users set email_change='ny@mail.se' where id='${user}'`),
  'a pending request does not allow the change');

// Approved: only the approved address works, in both steps.
await db.exec(`update core.login_email_change_requests set state='approved'`);
assert(await refused(`update auth.users set email_change='annan@mail.se' where id='${user}'`),
  'another address than the approved one is refused');
await db.exec(`update auth.users set email_change='NY@mail.se' where id='${user}'`);
assert((await row()).email_change === 'NY@mail.se', 'the approved address can be started');
await db.exec(`update auth.users set email='ny@mail.se',email_change='' where id='${user}'`);
assert((await row()).email === 'ny@mail.se', 'confirmation switches to the approved address');
assert((await db.query(`select state from core.login_email_change_requests`)).rows[0].state === 'completed',
  'the request is completed by the switch');

// The completed request cannot be reused for a further change.
assert(await refused(`update auth.users set email='tredje@mail.se' where id='${user}'`),
  'a completed request cannot be reused');
// Unrelated updates still work.
await db.exec(`update auth.users set email_change='' where id='${user}'`);
console.log('PASS');
