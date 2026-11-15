// Miniatyr av länkad tavla (2026-11-15): the linked board's first frame in
// short form, without player names or hidden objects.
// node supabase/tests/training_board_preview.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const project = '00000000-0000-4000-8000-000000000001', shared = '00000000-0000-4000-8000-000000000002';
const board = {
  id: 'board-1', view: 'empty', crop: null,
  teams: { home: { name: 'Hemma', color: '#1d4ed8', numberColor: '#ffffff' }, away: { name: 'Borta', color: '#dc2626', numberColor: '#ffffff' } },
  frames: [{ objects: [
    { id: 'p1', type: 'player', x: 10, y: 20, side: 'home', number: 7, name: 'Alex Spelare', personId: 'person-1', color: null, hidden: false },
    { id: 'p2', type: 'player', x: 12, y: 22, side: 'away', number: 4, name: 'Dold', hidden: true },
    { id: 'b1', type: 'ball', x: 11, y: 21, attachedTo: 'p1', hidden: false },
    { id: 'r1', type: 'rect', x: 15, y: 25, width: 24, height: 18, color: '#facc15', fill: 0.18, dashed: true, rotation: 0, hidden: false },
    { id: 't1', type: 'text', x: 1, y: 1, text: 'Hemligt', hidden: false },
  ] }, { objects: [] }],
};
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema core;
create table core.tactics_projects(id uuid primary key, document jsonb);
create table core.tactics_shared_items(id uuid primary key, document jsonb);
insert into core.tactics_projects values ('${project}', '${JSON.stringify({ boards: [board] })}');
insert into core.tactics_shared_items values ('${shared}', '${JSON.stringify({ boards: [{ ...board, id: 'board-2', view: 'full' }] })}');
create function internal.training_players_json(players jsonb, club uuid) returns jsonb language sql as $$ select '[]'::jsonb $$;
create function internal.training_session_roster(event_row jsonb) returns jsonb language sql as $$ select null::jsonb $$;`);
// Only the preview function: the session JSON needs the whole schema.
const sql = read('supabase/migrations/20270327090000_training_board_preview.sql');
await db.exec(sql.slice(0, sql.indexOf('create or replace function internal.training_session_json')));
const preview = async (source, ref, key) =>
  (await db.query('select internal.training_board_preview($1, $2, $3) p', [source, ref, key])).rows[0].p;

const mine = await preview('mine', project, 'board-1');
assert.equal(mine.view, 'empty');
assert.deepEqual(mine.teams.home, { color: '#1d4ed8', number_color: '#ffffff' });
assert.deepEqual(mine.objects.map(o => o.type), ['player', 'ball', 'rect']);
assert.deepEqual(mine.objects[0], { type: 'player', x: 10, y: 20, side: 'home', number: 7 });
assert.equal(mine.objects[1].attached, true);
assert.deepEqual(mine.objects[2], { type: 'rect', x: 15, y: 25, width: 24, height: 18, color: '#facc15', fill: 0.18, dashed: true, rotation: 0 });
assert.ok(!JSON.stringify(mine).includes('Alex'), 'no player names');
assert.ok(!JSON.stringify(mine).includes('person-1'), 'no person ids');

assert.equal((await preview('club', shared, 'board-2')).view, 'full');
assert.equal(await preview('mine', project, 'missing'), null);
assert.equal(await preview('club', project, 'board-1'), null);
console.log('training board preview: ok');
