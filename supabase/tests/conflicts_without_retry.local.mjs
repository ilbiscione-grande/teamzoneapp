// Conflicts without SQLSTATE 40001 (20270213090000). PostgREST 14 runs a call
// that fails with 40001 again and again, with no end.
// 1. No migration after it raises serialization_failure again.
// 2. In PGlite: the migration defines such functions again with PT409, the
//    message, owner, grants, settings and comment kept; others are left alone.
// node supabase/tests/conflicts_without_retry.local.mjs
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const NAME = '20270213090000_conflicts_without_retry.sql';
const dir = new URL('../migrations/', import.meta.url);
const later = readdirSync(dir).filter(file => file.endsWith('.sql') && file > NAME);
for (const file of later) {
  assert.doesNotMatch(readFileSync(new URL(file, dir), 'utf8'), /raise\s+serialization_failure/i,
    `${file} raises serialization_failure: PostgREST retries it forever, use raise sqlstate 'PT409'`);
}

const db = new PGlite();
await db.exec(`create role authenticated; create schema internal; create schema api;
create function internal.save(expected bigint) returns bigint language plpgsql security definer set search_path = '' as $$
begin
  if expected <> 2 then raise serialization_failure using message = 'stale_revision'; end if;
  if expected < 0 then RAISE  Serialization_Failure  USING message = 'other_conflict'; end if;
  return expected + 1;
end;
$$;
revoke all on function internal.save(bigint) from public;
grant execute on function internal.save(bigint) to authenticated;
comment on function internal.save(bigint) is 'Saves.';
create function api.save(expected bigint) returns bigint language sql as $$ select internal.save(expected) $$;
create function internal.untouched() returns int language plpgsql as $$ begin raise exception 'not_found'; end; $$;`);
const before = (await db.query(`select prosrc from pg_proc where proname = 'untouched'`)).rows[0].prosrc;

await db.exec(readFileSync(new URL(NAME, dir), 'utf8'));

const failure = await db.query('select api.save(1)').then(() => null, error => error);
assert.ok(failure, 'a stale save still fails');
assert.equal(failure.code, 'PT409');
assert.equal(failure.message, 'stale_revision');
assert.equal((await db.query('select api.save(2) as r')).rows[0].r, 3, 'a save at the right revision works');

const [save] = (await db.query(`select p.prosrc, p.prosecdef, p.proconfig, p.proacl::text as acl, obj_description(p.oid, 'pg_proc') as note
  from pg_proc p where p.oid = 'internal.save(bigint)'::regprocedure`)).rows;
assert.doesNotMatch(save.prosrc, /serialization_failure/i, 'every raise is changed');
assert.equal((save.prosrc.match(/raise sqlstate 'PT409' using/g) ?? []).length, 2);
assert.equal(save.prosecdef, true, 'still security definer');
assert.deepEqual(save.proconfig, ['search_path=""']);
assert.match(save.acl, /authenticated=X/, 'grant kept');
assert.doesNotMatch(save.acl, /(^|[{,])=X/, 'still not open to public');
assert.equal(save.note, 'Saves.');
assert.equal((await db.query(`select prosrc from pg_proc where proname = 'untouched'`)).rows[0].prosrc, before);

await db.exec(readFileSync(new URL(NAME, dir), 'utf8'));
console.log(`conflicts without retry: ok (${later.length} later migrations checked)`);
