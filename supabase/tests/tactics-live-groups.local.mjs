// Webtools Tacticsboard live lessons, group work step 1 (2026-11-17): groups
// with their own copy of the board, moves merged per group, the group's
// channel for its members and the host, and the sandbox thrown away.
// node supabase/tests/tactics-live-groups.local.mjs
import assert from 'node:assert/strict';
import { guest, host, id, liveDb, member, stranger } from './tactics-live-db.mjs';
const { db, as, asRole, call, fails } = await liveDb(['20261126090000_tactics_live', '20261127090000_tactics_live_chat',
  '20261128090000_tactics_live_idle', '20261129090000_tactics_live_draw', '20270401090000_tactics_live_groups']);
const sent = async () => (await db.query('select topic, event, payload from realtime.sent')).rows;
const clearSent = () => db.exec('delete from realtime.sent');
const late = id(5);
await db.query("insert into core.profiles(id, display_name) values ($1, 'Sara')", [late]);

const board = { id: 'b1', frames: [{ objects: [{ id: 'p1', x: 10, y: 10 }, { id: 'p2', x: 20, y: 20 }] }, { objects: [] }] };
const project = await call(host, "select api.create_tactics_project('Anfall','education',null,$1)", [JSON.stringify({ schemaVersion: 1, boards: [board] })]);
const session = await call(host, 'select api.start_tactics_live($1,true)', [project.id]);
await call(member, "select api.join_tactics_live($1,'')", [session.code]);
await call(guest, "select api.join_tactics_live($1,'Gästen')", [session.code], true);
await call(host, 'select api.give_tactics_live_floor($1,$2)', [session.id, member]);

// No group work yet.
assert.equal(await call(member, 'select api.get_tactics_live_group($1)', [session.id]), null);
assert.deepEqual(await call(host, 'select api.list_tactics_live_groups($1)', [session.id]), []);

// Starting: only the host, two to six groups, a real board; everyone is placed and the floor goes back.
const start = (who, count = 2, b = board, frame = 0, anonymous = false) =>
  call(who, 'select api.start_tactics_live_groups($1,$2,$3,$4)', [session.id, count, JSON.stringify(b), frame], anonymous);
await fails(member, 'select api.start_tactics_live_groups($1,2,$2,0)', [session.id, JSON.stringify(board)], /not_found/);
await fails(host, 'select api.start_tactics_live_groups($1,1,$2,0)', [session.id, JSON.stringify(board)], /invalid_group_count/);
await fails(host, 'select api.start_tactics_live_groups($1,7,$2,0)', [session.id, JSON.stringify(board)], /invalid_group_count/);
await fails(host, 'select api.start_tactics_live_groups($1,2,$2,5)', [session.id, JSON.stringify(board)], /invalid_board/);
await fails(host, "select api.start_tactics_live_groups($1,2,'{\"id\":\"b1\"}',0)", [session.id], /invalid_board/);
await clearSent();
const groups = await start(host);
assert.deepEqual(groups.map(group => [group.number, group.board_id, group.frame_index, group.members.length]), [[1, 'b1', 0, 1], [2, 'b1', 0, 1]]);
assert.deepEqual((await sent()).map(row => [row.event, row.payload]), [['floor', { profileId: null, name: null }], ['groups', { active: true }]]);
assert.equal((await db.query('select floor_holder from core.tactics_live_sessions where id = $1', [session.id])).rows[0].floor_holder, null);

// A participant's own group: the board as the host had it, no moves yet.
const mine = await call(member, 'select api.get_tactics_live_group($1)', [session.id]);
const theirs = await call(guest, 'select api.get_tactics_live_group($1)', [session.id], true);
assert.notEqual(mine.id, theirs.id, 'two participants, two groups');
assert.deepEqual([mine.board.frames[0].objects[0], mine.moves, mine.members.map(m => m.name)], [{ id: 'p1', x: 10, y: 10 }, {}, ['Mats']]);
assert.equal(await call(host, 'select api.get_tactics_live_group($1)', [session.id]), null, 'the host is in no group');
await fails(stranger, 'select api.get_tactics_live_group($1)', [session.id], /not_found/);

// Someone coming in late goes to the smallest group, and stays there.
await call(late, "select api.join_tactics_live($1,'')", [session.code]);
const lateGroup = await call(late, 'select api.get_tactics_live_group($1)', [session.id]);
assert.equal(lateGroup.members.length, 2);
assert.equal((await call(late, 'select api.get_tactics_live_group($1)', [session.id])).id, lateGroup.id);

// Moves: on the way only sent, dropped kept; merged per frame; on the group's channel only.
const move = (who, moves, dropped, frame = 0, anonymous = false) =>
  call(who, 'select api.move_tactics_live_group($1,$2,$3,$4)', [session.id, frame, JSON.stringify(moves), dropped], anonymous);
await clearSent();
await move(member, { p1: { x: 30, y: 31 } }, false);
assert.deepEqual((await call(member, 'select api.get_tactics_live_group($1)', [session.id])).moves, {});
await move(member, { p1: { x: 30, y: 31, extra: 1 } }, true);
await move(member, { p2: { x: 40, y: 41 } }, true);
await move(member, { p2: { x: 42, y: 43 } }, true, 1);
assert.deepEqual((await call(member, 'select api.get_tactics_live_group($1)', [session.id])).moves,
  { 0: { p1: { x: 30, y: 31 }, p2: { x: 40, y: 41 } }, 1: { p2: { x: 42, y: 43 } } });
assert.deepEqual((await call(guest, 'select api.get_tactics_live_group($1)', [session.id], true)).moves, {}, 'the other group is untouched');
const rows = await sent();
assert.ok(rows.every(row => row.topic === `tactics-live-group:${mine.id}` && row.event === 'group-move'));
assert.deepEqual(rows[1].payload, { boardId: 'b1', frameIndex: 0, moves: { p1: { x: 30, y: 31 } }, dropped: true, by: member });
await fails(member, 'select api.move_tactics_live_group($1,0,$2,true)', [session.id, JSON.stringify({ p1: { x: 999, y: 1 } })], /invalid_move/);
await fails(member, "select api.move_tactics_live_group($1,0,'{}',true)", [session.id], /invalid_move/);
await fails(host, 'select api.move_tactics_live_group($1,0,$2,true)', [session.id, JSON.stringify({ p1: { x: 1, y: 1 } })], /no_group/);
await fails(stranger, 'select api.move_tactics_live_group($1,0,$2,true)', [session.id, JSON.stringify({ p1: { x: 1, y: 1 } })], /not_found/);

// The group's channel: its members and the host listen; the other group and strangers do not; nobody sends on it.
const topic = `tactics-live-group:${mine.id}`;
const listens = async (who, anonymous = false) => { await as(who, anonymous); return asRole('authenticated', async () => (await db.query('select internal.tactics_live_group_topic_open($1) v', [topic])).rows[0].v); };
assert.deepEqual([await listens(host), await listens(member), await listens(guest, true), await listens(stranger)], [true, true, false, false]);
await db.query("select set_config('realtime.topic',$1,false)", [topic]);
await db.exec('savepoint m');
const hostSends = await call(host, "insert into realtime.messages(topic, extension) values ($1,'broadcast')", [topic]).then(() => true, () => false);
await db.exec('rollback to m');
assert.equal(hostSends, false, 'only the database sends on a group channel');

// Starting again replaces the groups.
const again = await start(host, 3);
assert.equal(again.length, 3);
assert.equal(await listens(member), false, 'the old group is gone');
assert.deepEqual((await call(member, 'select api.get_tactics_live_group($1)', [session.id])).moves, {});

// Ending: only the host; the groups and their moves are deleted and everyone is told.
await fails(member, 'select api.end_tactics_live_groups($1)', [session.id], /not_found/);
await clearSent();
await call(host, 'select api.end_tactics_live_groups($1)', [session.id]);
assert.deepEqual((await sent()).map(row => [row.topic, row.event, row.payload]), [[`tactics-live:${session.id}`, 'groups', { active: false }]]);
assert.equal(await call(member, 'select api.get_tactics_live_group($1)', [session.id]), null);
assert.equal((await db.query('select count(*)::int n from core.tactics_live_groups')).rows[0].n, 0);
assert.equal((await db.query('select count(*)::int n from core.tactics_live_participants where group_id is not null')).rows[0].n, 0);

// A lesson that ends takes its groups with it.
await start(host);
await call(host, 'select api.end_tactics_live($1)', [session.id]);
assert.equal((await db.query('select count(*)::int n from core.tactics_live_groups')).rows[0].n, 0);
console.log('tactics live groups: ok');
