// Tacticsboard's library, step 2 (2026-10-25): TeamZone's shared library —
// sharing as locked versions, the starters, search and filters, the writer's
// name, removal, reports that hide, and support's decision.
// node supabase/tests/tactics_shared_library.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const anna = id(1), bo = id(2), c1 = id(3), c2 = id(4), c3 = id(5), support = id(9), project = id(30);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth; create schema audit;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${anna}','Anna Tränare'),('${bo}','Bo Ledare'),('${c1}',''),('${c2}',''),('${c3}',''),('${support}','Support');
create table core.tactics_projects(id uuid primary key, owner_id uuid); insert into core.tactics_projects values ('${project}','${anna}');
create table audit.command_events(id uuid primary key default gen_random_uuid(), club_id uuid, actor_profile_id uuid, command_type text,
  aggregate_type text, aggregate_id uuid, aggregate_revision bigint, reason text, metadata jsonb, occurred_at timestamptz default now());
create function internal.actor_is_support_admin() returns boolean language sql stable as $$ select auth.uid() = '${support}'::uuid $$;
grant usage on schema api, internal, core, auth to authenticated;`);
for (const name of ['20261213090000_tactics_library', '20261214090000_tactics_shared_library']) {
  await db.exec(read(`supabase/migrations/${name}.sql`));
}
const call = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  await db.exec('set role authenticated');
  try {
    const rows = (await db.query(sql, params)).rows;
    return Object.values(rows[0] ?? {})[0];
  } finally {
    await db.exec('reset role');
  }
};
const fails = async (who, sql, params, pattern) => assert.rejects(call(who, sql, params), pattern);
const search = (who, text = '', filters = {}) => call(who, 'select api.search_tactics_shared_items($1,$2,$3,$4,$5,$6,0)',
  [text, filters.kind ?? null, filters.part ?? null, filters.phase ?? null, filters.age ?? null, filters.form ?? null]);
const board = { id: 'b1', name: 'Rondo', frames: [{ id: 'f', objects: [] }] };
const saveLibrary = (minutes) => call(anna, 'select api.save_tactics_library_item($1,$2,$3::jsonb,$4::jsonb,$5,$6)',
  ['exercise', 'Rondo 5 mot 2', JSON.stringify({ part: 'warmup', minutes, phase: 'regaining', organisation: 'Fem mot två',
    age_classes: ['10-12'], game_forms: ['5v5'] }), JSON.stringify({ schemaVersion: 1, boards: [board] }), project, 'b1']);

// TeamZone's starters are there for everyone.
let found = await search(bo);
assert.equal(found.length, 15);
assert.ok(found.every(item => item.starter && item.author === 'TeamZone' && !item.mine));
assert.equal((await search(bo, '', { part: 'warmup' })).length, 3);
assert.equal((await search(bo, 'kontring')).length, 1);

// Anna shares her exercise: a locked copy with her name, found by its filters.
const mine = await saveLibrary(12);
const shared = await call(anna, 'select api.share_tactics_library_item($1)', [mine.id]);
assert.deepEqual([shared.author, shared.version, shared.mine], ['Anna Tränare', 1, true]);
found = await search(bo, 'rondo', { kind: 'exercise', phase: 'regaining', age: '10-12', form: '5v5' });
assert.deepEqual(found.map(item => [item.title, item.author, item.mine]), [['Rondo 5 mot 2', 'Anna Tränare', false]]);
assert.deepEqual(await search(bo, 'rondo', { form: '11v11' }), []);
assert.equal((await search(bo)).length, 16);
assert.equal((await search(bo))[0].starter, false, 'shared by coaches before TeamZone\'s own');

// A change in her library is not shared until she shares again: then a new version.
await saveLibrary(15);
let library = await call(anna, 'select api.list_my_tactics_library()');
assert.deepEqual([library[0].shared.version, library[0].shared.current], [1, false]);
assert.equal((await call(bo, 'select api.get_tactics_shared_item($1)', [shared.id])).details.minutes, 12, 'the shared copy is locked');
const again = await call(anna, 'select api.share_tactics_library_item($1)', [mine.id]);
assert.deepEqual([again.id, again.version], [shared.id, 2]);
assert.equal((await call(bo, 'select api.get_tactics_shared_item($1)', [shared.id])).details.minutes, 15);
await fails(bo, 'select api.share_tactics_library_item($1)', [mine.id], /not_found/);

// Reports: not your own; three hide it from everyone but its writer, until support decides.
await fails(anna, "select api.report_tactics_shared_item($1,'Eget')", [shared.id], /not_found/);
for (const who of [c1, c2]) await call(who, "select api.report_tactics_shared_item($1,'Olämpligt')", [shared.id]);
assert.equal((await search(bo, 'rondo', { form: '5v5' })).length, 1, 'two reports do not hide');
await call(c3, "select api.report_tactics_shared_item($1,'Olämpligt')", [shared.id]);
assert.deepEqual(await search(bo, 'rondo', { form: '5v5' }), []);
await fails(bo, 'select api.get_tactics_shared_item($1)', [shared.id], /not_found/);
assert.equal((await search(anna, 'rondo', { form: '5v5' }))[0].hidden, true, 'the writer still sees it, hidden');
await fails(bo, 'select api.list_tactics_shared_reports(true)', [], /not_found/);
const reports = await call(support, 'select api.list_tactics_shared_reports(true)');
assert.deepEqual([reports.length, reports[0].reports.length], [1, 3]);
await call(support, "select api.decide_tactics_shared_reports($1,false,'Inget olämpligt')", [shared.id]);
assert.equal((await search(bo, 'rondo', { form: '5v5' })).length, 1, 'shown again');
assert.equal((await call(support, 'select api.list_tactics_shared_reports(true)')).length, 0);
await call(support, "select api.decide_tactics_shared_reports($1,true,'Upphovsrätt')", [shared.id]);
await fails(anna, 'select api.share_tactics_library_item($1)', [mine.id], /hidden_by_support/);

// The writer removes it; her library keeps her own item.
await call(anna, 'select api.unshare_tactics_item($1)', [shared.id]);
assert.deepEqual(await search(anna, 'rondo', { form: '5v5' }), []);
library = await call(anna, 'select api.list_my_tactics_library()');
assert.deepEqual([library.length, library[0].shared], [1, null]);
await fails(bo, 'select api.unshare_tactics_item($1)', [found[0]?.id ?? shared.id], /not_found/);

console.log('tactics_shared_library: ok');
