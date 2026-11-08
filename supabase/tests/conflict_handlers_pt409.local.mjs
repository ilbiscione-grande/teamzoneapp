// Conflict handlers catch PT409 too (20270214090000).
// 1. No migration file catches serialization_failure without PT409.
// 2. In PGlite: a handler that caught serialization_failure catches PT409,
//    settings and grants kept, others untouched, rerun safe.
// node supabase/tests/conflict_handlers_pt409.local.mjs
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const NAME = '20270214090000_conflict_handlers_pt409.sql';
const dir = new URL('../migrations/', import.meta.url);
const files = readdirSync(dir).filter(file => file.endsWith('.sql') && file > '20261221');
for (const file of files) {
  assert.doesNotMatch(readFileSync(new URL(file, dir), 'utf8'), /when\s+serialization_failure\s+then/i,
    `${file} catches serialization_failure only: conflicts are PT409, add "or sqlstate 'PT409'"`);
}

const db = new PGlite();
await db.exec(`create role authenticated; create schema internal;
create function internal.conflict() returns void language plpgsql as $$ begin raise sqlstate 'PT409' using message = 'stale_revision'; end; $$;
create function internal.worker() returns text language plpgsql security definer set search_path = '' as $$
begin
  begin perform internal.conflict(); exception when serialization_failure then return 'skipped'; end;
  return 'done';
end;
$$;
revoke all on function internal.worker() from public;
grant execute on function internal.worker() to authenticated;
create function internal.untouched() returns int language plpgsql as $$ begin return 1; exception when others then return 0; end; $$;`);
const before = (await db.query(`select prosrc from pg_proc where proname = 'untouched'`)).rows[0].prosrc;
const failure = await db.query('select internal.worker()').then(() => null, error => error);
assert.equal(failure?.code, 'PT409', 'before: the handler misses PT409');

await db.exec(readFileSync(new URL(NAME, dir), 'utf8'));
assert.equal((await db.query('select internal.worker() as r')).rows[0].r, 'skipped');
const [worker] = (await db.query(`select p.prosecdef, p.proconfig, p.proacl::text as acl from pg_proc p
  where p.oid = 'internal.worker()'::regprocedure`)).rows;
assert.equal(worker.prosecdef, true);
assert.deepEqual(worker.proconfig, ['search_path=""']);
assert.match(worker.acl, /authenticated=X/);
assert.doesNotMatch(worker.acl, /(^|[{,])=X/);
assert.equal((await db.query(`select prosrc from pg_proc where proname = 'untouched'`)).rows[0].prosrc, before);

await db.exec(readFileSync(new URL(NAME, dir), 'utf8'));
assert.equal((await db.query('select internal.worker() as r')).rows[0].r, 'skipped', 'rerun safe');
console.log(`conflict handlers with PT409: ok (${files.length} migrations checked)`);
