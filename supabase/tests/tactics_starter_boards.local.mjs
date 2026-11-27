// The starters get their boards (20270426090000): every one of the fifteen
// has a drawn board with frames, valid details and a preview with its crop.
// node supabase/tests/tactics_starter_boards.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth; create schema audit;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.profiles(id uuid primary key, display_name text not null default '');
create table core.tactics_projects(id uuid primary key, owner_id uuid);`);
for (const name of ['20261213090000_tactics_library', '20261214090000_tactics_shared_library']) {
  await db.exec(read(`supabase/migrations/${name}.sql`));
}
const before = (await db.query(`select title, document->'boards'->0->>'id' as board from core.tactics_shared_items order by title`)).rows;
await db.exec(read('supabase/migrations/20270426090000_tactics_starter_boards.sql'));
const rows = (await db.query(`select title, details, document, internal.tactics_exercise_details_valid(details) as valid,
  internal.tactics_board_preview(document, null) as preview, version from core.tactics_shared_items order by title`)).rows;
assert.equal(rows.length, 15);
rows.forEach((row, index) => {
  const board = row.document.boards[0];
  assert.equal(board.id, before[index].board, `${row.title} keeps its board id`);
  assert.ok(row.valid, `${row.title} details valid`);
  assert.equal(row.version, 1);
  assert.ok(row.details.coaching_points.length > 20, `${row.title} has coaching points`);
  assert.ok(board.frames.length >= 3, `${row.title} has frames`);
  const players = board.frames[0].objects.filter(o => o.type === 'player');
  assert.ok(players.length >= 6, `${row.title} has players`);
  if (row.title !== 'Snabbhet och riktningsförändring') assert.ok(board.frames[0].objects.some(o => o.type === 'ball'), `${row.title} has a ball`);
  if (board.crop) assert.deepEqual(row.preview.crop, board.crop);
  assert.ok(row.preview.objects.length > players.length);
});
console.log('tactics_starter_boards: ok', rows.map(r => `${r.title} (${r.document.boards[0].frames.length} frames)`).join(', '));
