// The real failed-sign-in limit migration in isolated Postgres.
// node supabase/tests/sign_in_attempt_limits.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const hash = c => c.repeat(64);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const allowed = (email, ip) => one('select api.sign_in_attempt_allowed($1,$2)', [email, ip]);
const record = (email, ip, ok) => db.query('select api.record_sign_in_result($1,$2,$3)', [email, ip, ok]);
try {
  await db.exec(`create role anon;create role authenticated;create role service_role;
  create schema internal;create schema api;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);`);
  const migration = read('supabase/migrations/20261022090000_sign_in_attempt_limits.sql').replace(/notify pgrst[^;]*;/, '');
  await db.exec(migration);
  const anna = hash('a'), bo = hash('b'), home = hash('1'), cafe = hash('2');

  // 1. Ten failures for one e-mail block it, from any address.
  for (let i = 0; i < 9; i++) await record(anna, home, false);
  assert.equal(await allowed(anna, home), true, 'nine failures still allowed');
  await record(anna, home, false);
  assert.equal(await allowed(anna, home), false, 'tenth failure blocks the e-mail');
  assert.equal(await allowed(anna, cafe), false, 'also from another address');
  assert.equal(await allowed(bo, cafe), true, 'other accounts are unaffected');

  // 2. A successful sign-in clears that e-mail's count.
  await record(anna, home, true);
  assert.equal(await allowed(anna, home), true);

  // 3. Fifty failures from one address block it for every e-mail.
  for (let i = 0; i < 50; i++) await record(hash((i % 9 + 3).toString(16)), cafe, false);
  assert.equal(await allowed(bo, cafe), false, 'the address is blocked');
  assert.equal(await allowed(bo, home), true, 'other addresses are not');

  // 4. A new window starts over; old windows are cleaned up.
  await db.exec(`update internal.sign_in_failures set window_started_at=window_started_at-interval '15 minutes'`);
  assert.equal(await allowed(bo, cafe), true, 'the next window is open again');
  await db.exec(`update internal.sign_in_failures set window_started_at=now()-interval '2 days'`);
  await record(bo, home, false);
  assert.equal(await one('select count(*)::int from internal.sign_in_failures'), 2, 'only the new failure remains');

  // 5. Only hashes are stored, of the right length.
  await assert.rejects(() => record('abcd', home, false), /invalid_hash/);
  assert.equal(await one(`select bool_and(octet_length(key_hash)=32) from internal.sign_in_failures`), true);

  // 6. Service role only, and the migration can run twice.
  for (const role of ['anon', 'authenticated']) {
    for (const fn of ['api.sign_in_attempt_allowed(text,text)', 'api.record_sign_in_result(text,text,boolean)']) {
      assert.equal(await one('select has_function_privilege($1,$2,$3)', [role, fn, 'execute']), false, `${role} ${fn}`);
    }
    assert.equal(await one("select has_table_privilege($1,'internal.sign_in_failures','select')", [role]), false);
  }
  assert.equal(await one("select has_function_privilege('service_role','api.record_sign_in_result(text,text,boolean)','execute')"), true);
  await db.exec(migration);
  assert.equal(await one('select count(*)::int from internal.migration_provenance'), 1);
  console.log('sign-in attempt limits: ok');
} finally {
  await db.close();
}
