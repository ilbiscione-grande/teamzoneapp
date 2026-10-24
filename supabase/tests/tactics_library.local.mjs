// Tacticsboard's library, step 1 (2026-10-24): saving exercises, passes and
// sessions in your own library, again as a new version, and their checks.
// node supabase/tests/tactics_library.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), other = id(2), project = id(30), othersProject = id(31);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.profiles(id uuid primary key); insert into core.profiles values ('${coach}'),('${other}');
create table core.tactics_projects(id uuid primary key, owner_id uuid);
insert into core.tactics_projects values ('${project}','${coach}'),('${othersProject}','${other}');
grant usage on schema api, internal, core, auth to authenticated;`);
await db.exec(read('supabase/migrations/20261213090000_tactics_library.sql'));
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
const board = (boardId, name) => ({ id: boardId, name, frames: [{ id: 'f', objects: [] }] });
const save = (who, kind, title, details, boards, fromProject = null, fromBoard = null) => call(who,
  'select api.save_tactics_library_item($1,$2,$3::jsonb,$4::jsonb,$5,$6)',
  [kind, title, JSON.stringify(details), JSON.stringify({ schemaVersion: 1, boards }), fromProject, fromBoard]);
const rondo = { part: 'warmup', minutes: 12, players: 7, area: '10x10 m', organisation: 'Fem mot två',
  coaching_points: 'Kroppsställning', phase: null, age_classes: ['10-12', '13-15'], game_forms: ['5v5', '7v7'] };

// An exercise from a board, then saved again: the same entry, a new version.
let item = await save(coach, 'exercise', 'Rondo 5 mot 2', rondo, [board('b1', 'Rondo')], project, 'b1');
assert.deepEqual([item.kind, item.version, item.created, item.board_count, item.details.game_forms], ['exercise', 1, true, 1, ['5v5', '7v7']]);
item = await save(coach, 'exercise', 'Rondo 5 mot 2', { ...rondo, minutes: 15 }, [board('b1', 'Rondo')], project, 'b1');
assert.deepEqual([item.version, item.created, item.details.minutes], [2, false, 15]);
// Another board of the project is another exercise.
await save(coach, 'exercise', 'Press 4 mot 4', { part: 'main', minutes: 20, phase: 'regaining' }, [board('b2', 'Press')], project, 'b2');

// A pass: the project's boards with each exercise's details; and a session.
const pass = await save(coach, 'plan', 'Press och återerövring', { theme: 'Press', goal: 'Vinna bollen högt',
  exercises: [rondo, { part: 'main', minutes: 20, phase: 'regaining' }] }, [board('b1', 'Rondo'), board('b2', 'Press')], project, 'b1');
assert.deepEqual([pass.kind, pass.board_count, pass.source_board_id], ['plan', 2, null], 'a pass belongs to the project, not a board');
const again = await save(coach, 'plan', 'Press och återerövring', { theme: 'Press', exercises: [] }, [board('b1', 'Rondo')], project, null);
assert.deepEqual([again.id, again.version], [pass.id, 2]);
await save(coach, 'lesson', 'Spelidén', {}, [board('b1', 'Princip'), board('b2', 'Press')]);

// The list, newest first, without the boards; one item with its boards.
const list = await call(coach, 'select api.list_my_tactics_library()');
assert.deepEqual(list.map(i => i.kind), ['lesson', 'plan', 'exercise', 'exercise']);
assert.equal(list[0].document, undefined);
const full = await call(coach, 'select api.get_tactics_library_item($1)', [item.id]);
assert.equal(full.document.boards[0].id, 'b1');

// The checks: details, one board for an exercise, your own project, and your own items.
await fails(coach, "select api.save_tactics_library_item('exercise','X',$1::jsonb,$2::jsonb,null,null)",
  [JSON.stringify({ part: 'cooldown' }), JSON.stringify({ boards: [board('x', 'X')] })], /invalid_input/);
await fails(coach, "select api.save_tactics_library_item('exercise','X',$1::jsonb,$2::jsonb,null,null)",
  [JSON.stringify({ age_classes: ['5-6'] }), JSON.stringify({ boards: [board('x', 'X')] })], /invalid_input/);
await fails(coach, "select api.save_tactics_library_item('exercise','X','{}'::jsonb,$1::jsonb,null,null)",
  [JSON.stringify({ boards: [board('x', 'X'), board('y', 'Y')] })], /invalid_input/);
await fails(coach, "select api.save_tactics_library_item('exercise','X','{}'::jsonb,$1::jsonb,$2,'b')",
  [JSON.stringify({ boards: [board('x', 'X')] }), othersProject], /not_found/);
await fails(other, 'select api.get_tactics_library_item($1)', [item.id], /not_found/);
await fails(other, 'select api.delete_tactics_library_item($1)', [item.id], /not_found/);
assert.deepEqual(await call(other, 'select api.list_my_tactics_library()'), []);

await call(coach, 'select api.delete_tactics_library_item($1)', [item.id]);
assert.equal((await call(coach, 'select api.list_my_tactics_library()')).length, 3);

console.log('tactics_library: ok');
