// Tacticsboard's library, my library as my projects (2026-10-25): all
// projects filtered as TeamZone's library, publishing straight from a
// project, and what each project has published.
// node supabase/tests/tactics_my_library.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const anna = id(1), bo = id(2), club = id(10), training = id(30), match = id(31), lesson = id(32);
const person = n => id(100 + n);
const board = (boardId, name, exercise, description = '') => ({ id: boardId, name, description, frames: [], exercise });
const trainingDoc = { boards: [
  board('b1', 'Rondo', { part: 'warmup', minutes: 10, phase: null, ageClasses: ['10-12'], gameForms: ['5v5'], coachingPoints: 'Titta upp' }),
  board('b2', 'Press', { part: 'main', minutes: 20, phase: 'regaining', ageClasses: [], gameForms: ['7v7'], coachingPoints: '' }),
] };
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth; create schema audit;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${anna}','Anna Tränare'),('${bo}','Bo');
create table core.clubs(id uuid primary key, name text); insert into core.clubs values ('${club}','Demoklubben IF');
create table core.person_account_links(profile_id uuid, club_id uuid, club_person_id uuid, state text);
create table core.assignments(club_id uuid, club_person_id uuid, role_package text, state text, starts_at timestamptz, ends_at timestamptz);
insert into core.person_account_links values ('${anna}','${club}','${person(1)}','active');
insert into core.assignments values ('${club}','${person(1)}','leader','active',now() - interval '1 day',null);
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$ select false $$;
create table core.tactics_projects(id uuid primary key, owner_id uuid, name text, kind text, document jsonb, updated_at timestamptz default now());
insert into core.tactics_projects values
  ('${training}','${anna}','Träning press','training','${JSON.stringify(trainingDoc)}', now() - interval '2 hours'),
  ('${match}','${anna}','Match mot Aneby','match','${JSON.stringify({ boards: [board('m1', 'Uppställning', undefined, 'Hög press')] })}', now() - interval '1 hour'),
  ('${lesson}','${bo}','Bos genomgång','education','${JSON.stringify({ boards: [board('l1', 'Princip')] })}', now());
create function internal.tactics_project_summary(project core.tactics_projects) returns jsonb language sql stable as $$
  select jsonb_build_object('id', project.id, 'name', project.name, 'kind', project.kind) $$;
create table audit.command_events(id uuid primary key default gen_random_uuid(), club_id uuid, actor_profile_id uuid, command_type text,
  aggregate_type text, aggregate_id uuid, aggregate_revision bigint, reason text, metadata jsonb, occurred_at timestamptz default now());
create function internal.actor_is_support_admin() returns boolean language sql stable as $$ select false $$;
grant usage on schema api, internal, core, auth to authenticated;`);
for (const name of ['20261213090000_tactics_library', '20261214090000_tactics_shared_library', '20261215090000_tactics_club_library',
  '20261216090000_tactics_my_library']) {
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
const mine = (text = '', f = {}) => call(anna, 'select api.search_my_tactics_projects($1,$2,$3,$4,$5,$6)',
  [text, f.kind ?? null, f.part ?? null, f.phase ?? null, f.age ?? null, f.form ?? null]);
const names = list => list.map(project => project.name);

// All of your projects, newest first; not anyone else's.
assert.deepEqual(names(await mine()), ['Match mot Aneby', 'Träning press']);
// Filtered as TeamZone's library: kind, part, phase, age, game form and words in boards.
assert.deepEqual(names(await mine('', { kind: 'match' })), ['Match mot Aneby']);
assert.deepEqual(names(await mine('', { part: 'warmup' })), ['Träning press']);
assert.deepEqual(names(await mine('', { phase: 'regaining', form: '7v7' })), ['Träning press']);
assert.deepEqual(names(await mine('', { age: '10-12', form: '11v11' })), []);
assert.deepEqual(names(await mine('titta upp')), ['Träning press'], 'coaching points');
assert.deepEqual(names(await mine('hög press')), ['Match mot Aneby'], 'board descriptions');

// Publishing straight from the project: a board as an exercise to the club, the project as a pass to all.
const exercise = await call(anna, 'select api.publish_tactics_item($1,$2,$3::jsonb,$4::jsonb,$5,$6,$7)',
  ['exercise', 'Rondo 5 mot 2', JSON.stringify({ part: 'warmup', minutes: 10 }), JSON.stringify({ boards: [trainingDoc.boards[0]] }), training, 'b1', club]);
assert.deepEqual([exercise.club_name, exercise.version], ['Demoklubben IF', 1]);
await call(anna, 'select api.publish_tactics_item($1,$2,$3::jsonb,$4::jsonb,$5,null,null)',
  ['plan', 'Press', JSON.stringify({ theme: 'Press', exercises: [] }), JSON.stringify(trainingDoc), training]);
let published = (await mine('', { kind: 'training' }))[0].published;
assert.deepEqual(published.map(p => [p.kind, p.board_id, p.club_name, p.current]),
  [['exercise', 'b1', 'Demoklubben IF', true], ['plan', null, null, true]]);
// Again: the latest version, and who sees it may change.
const again = await call(anna, 'select api.publish_tactics_item($1,$2,$3::jsonb,$4::jsonb,$5,$6,null)',
  ['exercise', 'Rondo 5 mot 2', JSON.stringify({ part: 'warmup', minutes: 12 }), JSON.stringify({ boards: [trainingDoc.boards[0]] }), training, 'b1']);
assert.deepEqual([again.id, again.version, again.club_name], [exercise.id, 2, null]);
await fails(anna, "select api.publish_tactics_item('exercise','X','{}'::jsonb,$1::jsonb,null,null,null)", [JSON.stringify({ boards: [trainingDoc.boards[0]] })], /invalid_input/);
await fails(bo, "select api.publish_tactics_item('exercise','X','{}'::jsonb,$1::jsonb,$2,'b1',null)", [JSON.stringify({ boards: [trainingDoc.boards[0]] }), training], /not_found/);

// Unpublished, it leaves the project's list.
await call(anna, 'select api.unshare_tactics_item($1)', [exercise.id]);
published = (await mine('', { kind: 'training' }))[0].published;
assert.deepEqual(published.map(p => p.kind), ['plan']);

console.log('tactics_my_library: ok');
