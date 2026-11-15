// Bild av tavlan (2026-11-15): who edits a project saves its board
// pictures; who reads a training session gets its linked board's picture.
// node supabase/tests/tactics_board_pictures.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [owner, viewer, stranger] = [id(1), id(2), id(3)];
const [project, event, otherEvent, block, libraryBlock, hiddenBlock] = [id(10), id(20), id(21), id(30), id(31), id(32)];
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.tactics_projects(id uuid primary key, owner_id uuid, document jsonb);
insert into core.tactics_projects values ('${project}', '${owner}', '{"boards":[{"id":"board-1"},{"id":"board-2"}]}');
create function internal.tactics_project_access(project core.tactics_projects) returns text language sql stable as $$
  select case when project.owner_id = auth.uid() then 'owner' when auth.uid() = '${viewer}' then 'view' end $$;
create table core.events(id uuid primary key);
insert into core.events values ('${event}'), ('${otherEvent}');
create table core.training_sessions(event_id uuid primary key, published boolean);
insert into core.training_sessions values ('${event}', true), ('${otherEvent}', false);
create table core.training_blocks(id uuid primary key, event_id uuid, board_source text, board_ref uuid, board_id text);
insert into core.training_blocks values ('${block}', '${event}', 'mine', '${project}', 'board-1'),
  ('${libraryBlock}', '${event}', 'club', '${project}', 'board-1'), ('${hiddenBlock}', '${otherEvent}', 'mine', '${project}', 'board-1');
-- Everyone signed in reads the events here; only the owner plans them.
create function internal.training_session_event(target uuid) returns core.events language sql stable as $$
  select * from core.events where id = target $$;
create function internal.training_session_can_edit(event_row core.events) returns boolean language sql stable as $$
  select auth.uid() = '${owner}' $$;
grant usage on schema api, internal, core, auth to authenticated;`);
await db.exec(read('supabase/migrations/20270328090000_tactics_board_pictures.sql'));
const as = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who ?? '']);
  await db.exec('set role authenticated');
  try { return (await db.query(sql, params)).rows[0]?.r; } finally { await db.exec('reset role'); }
};
const png = Buffer.from('89504e470d0a1a0a', 'hex').toString('base64');
const save = (who, pictures) => as(who, 'select api.save_tactics_board_pictures($1, $2) r', [project, JSON.stringify(pictures)]);
const picture = (who, target) => as(who, 'select api.training_block_board_picture($1) r', [target]);

assert.equal(await save(owner, [{ board_id: 'board-1', media_type: 'image/png', data: png, width: 640, height: 400 }]), 1);
// Saved again: replaced, not added.
assert.equal(await save(owner, [{ board_id: 'board-1', media_type: 'image/webp', data: png, width: 600, height: 380 }]), 1);
assert.equal((await db.query('select count(*)::int n from core.tactics_board_pictures')).rows[0].n, 1);
await assert.rejects(save(viewer, []), /not_found/);
await assert.rejects(save(stranger, []), /not_found/);
await assert.rejects(save(owner, [{ board_id: 'nope', media_type: 'image/png', data: png, width: 640, height: 400 }]), /invalid_pictures/);
await assert.rejects(save(owner, [{ board_id: 'board-1', media_type: 'image/gif', data: png, width: 640, height: 400 }]), /invalid_pictures/);
await assert.rejects(save(owner, [{ board_id: 'board-1', media_type: 'image/png', data: png, width: 4000, height: 400 }]), /check constraint/);

const got = await picture(viewer, block);
assert.equal(got.media_type, 'image/webp');
assert.equal(got.data, png);
assert.deepEqual([got.width, got.height], [600, 380]);
assert.equal(await picture(viewer, libraryBlock), null);
// An unpublished session's exercise is not for its players.
await assert.rejects(picture(viewer, hiddenBlock), /not_found/);
assert.equal((await picture(owner, hiddenBlock)).width, 600);

// A board gone from the project takes its picture with it.
await db.exec(`update core.tactics_projects set document = '{"boards":[{"id":"board-2"}]}'`);
assert.equal(await save(owner, []), 0);
assert.equal((await db.query('select count(*)::int n from core.tactics_board_pictures')).rows[0].n, 0);

await db.exec('set role authenticated');
await assert.rejects(db.query('select * from core.tactics_board_pictures'), /permission denied/);
await db.exec('reset role');
console.log('tactics board pictures: ok');
