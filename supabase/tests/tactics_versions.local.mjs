// Tacticsboard's versions (20270101090000), in isolated Postgres with a
// reduced schema. node supabase/tests/tactics_versions.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const owner = id(1), stranger = id(2), helper = id(3);
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who ?? '']);
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
const call = async (who, sql, params = []) => { await as(who); return asRole('authenticated', async () => Object.values((await db.query(sql, params)).rows[0] ?? {})[0]); };
const fails = async (who, sql, params, pattern) => {
  await db.exec('savepoint s');
  await assert.rejects(call(who, sql, params), pattern);
  await db.exec('rollback to s');
};
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
set check_function_bodies = off;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${owner}','Ägaren'),('${stranger}','Någon annan'),('${helper}','Anna');
create table core.teams(id uuid primary key, name text);
create function internal.tournament_actor_teams() returns table(team_id uuid, team_name text, club_id uuid, club_name text) language sql stable as $$select null::uuid, null, null::uuid, null where false$$;
grant usage on schema api, internal, core, auth to authenticated;`);
await db.exec(read('supabase/migrations/20261123090000_tacticsboard.sql'));
await db.exec(read('supabase/migrations/20270101090000_tactics_versions.sql'));
await db.exec('begin');

const doc = boards => JSON.stringify({ version: 1, boards: boards.map(name => ({ id: name, name })) });
const project = (await call(owner, 'select api.create_tactics_project($1,$2,$3,$4::jsonb)', ['Spelidé', 'match', null, doc(['A'])])).id;
const save = (who, revision, boards, name = 'Spelidé') =>
  call(who, 'select api.save_tactics_project($1,$2,$3,$4,$5,$6::jsonb)', [project, revision, name, 'match', null, doc(boards)]);
const versions = () => call(owner, 'select api.list_tactics_versions($1)', [project]);
const count = async () => (await db.query('select count(*)::int n from core.tactics_project_versions')).rows[0].n;

// The first save keeps the project as it was; autosaves right after keep nothing more.
let revision = Number(await save(owner, 1, ['A', 'B']));
assert.equal(revision, 2);
assert.equal(await count(), 1);
revision = Number(await save(owner, revision, ['A', 'B', 'C']));
revision = Number(await save(owner, revision, ['A', 'B', 'C', 'D']));
assert.equal(await count(), 1, 'no version per autosave');
let list = await versions();
assert.deepEqual(list[0].boards, ['A']);
assert.equal(list[0].reason, 'edit');
assert.equal(list[0].saved_by_me, true);
assert.equal(list[0].saved_by_name, 'Ägaren');

// Half an hour later another editing session keeps a new version.
await db.exec("update core.tactics_project_versions set created_at = now() - interval '31 minutes'");
revision = Number(await save(owner, revision, ['A']));
assert.equal(await count(), 2);
assert.deepEqual((await versions())[0].boards, ['A', 'B', 'C', 'D']);

// Saving the same content keeps nothing.
await db.exec("update core.tactics_project_versions set created_at = now() - interval '31 minutes'");
revision = Number(await save(owner, revision, ['A']));
assert.equal(await count(), 2, 'an unchanged save is no version');

// Someone else saving (a written-back pass, later other leaders) keeps the content before it.
await as(helper);
await db.exec(`update core.tactics_projects set document = '${doc(['A', 'H'])}'::jsonb, revision = revision + 1 where id = '${project}'`);
revision += 1;
list = await versions();
assert.equal(list[0].reason, 'other_editor');
assert.deepEqual(list[0].boards, ['A']);
assert.equal(list[0].saved_by_me, true);
// The helper's next save straight after is the same editing session.
const kept = await count();
await as(helper);
await db.exec(`update core.tactics_projects set document = '${doc(['A', 'H2'])}'::jsonb, revision = revision + 1 where id = '${project}'`);
revision += 1;
assert.equal(await count(), kept);
// The owner saving over the helper's content keeps it, as the helper's.
await db.exec("update core.tactics_project_versions set created_at = now() - interval '1 minute'");
revision = Number(await save(owner, revision, ['A', 'H3']));
list = await versions();
assert.equal(list[0].reason, 'other_editor');
assert.equal(list[0].saved_by_name, 'Anna');
assert.deepEqual(list[0].boards, ['A', 'H2']);
revision = Number(await save(owner, revision, ['A', 'H2']));

// Only the owner sees, reads or restores versions.
await fails(stranger, 'select api.list_tactics_versions($1)', [project], /not_found/);
await fails(stranger, 'select api.get_tactics_version($1)', [list[0].id], /not_found/);
await fails(stranger, 'select api.restore_tactics_version($1,$2)', [list[0].id, revision], /not_found/);
const version = await call(owner, 'select api.get_tactics_version($1)', [list.at(-1).id]);
assert.deepEqual(version.document.boards.map(board => board.name), ['A']);

// A restore refuses a stale revision, keeps the content before it, and can be undone.
await fails(owner, 'select api.restore_tactics_version($1,$2)', [list.at(-1).id, revision - 1], /stale_revision/);
const before = await count();
revision = Number(await call(owner, 'select api.restore_tactics_version($1,$2)', [list.at(-1).id, revision]));
const restored = await call(owner, 'select api.get_tactics_project($1)', [project]);
assert.deepEqual(restored.document.boards.map(board => board.name), ['A']);
assert.equal(restored.revision, revision);
assert.equal(await count(), before + 1);
list = await versions();
assert.equal(list[0].reason, 'before_restore');
assert.deepEqual(list[0].boards, ['A', 'H2']);
// The setting does not outlive the restore: the next save is an ordinary one.
revision = Number(await save(owner, revision, ['A', 'X']));
assert.equal(await count(), before + 1);

// Old versions go after 90 days, but the ten latest always stay.
await db.exec(`insert into core.tactics_project_versions (project_id, revision, name, document, saved_at, reason, created_at)
  select '${project}', n, 'Gammal', '{}'::jsonb, now(), 'edit', now() - interval '100 days' - n * interval '1 day' from generate_series(1, 15) n`);
await db.exec("update core.tactics_project_versions set created_at = now() - interval '95 days' where name <> 'Gammal'");
revision = Number(await save(owner, revision, ['A', 'Y']));
assert.equal(await count(), 10);

// Removing the project removes its versions.
await call(owner, 'select api.delete_tactics_project($1)', [project]);
assert.equal(await count(), 0);

await db.exec('rollback');
console.log('tactics_versions.local: ok');
