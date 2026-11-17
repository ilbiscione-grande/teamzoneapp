// Webtools Tacticsboard live lessons, group work step 2 (2026-11-17): the
// host's overview with every group's copy, moving a participant to another
// group, and showing one group's copy to everyone.
// node supabase/tests/tactics-live-group-overview.local.mjs
import assert from 'node:assert/strict';
import { guest, host, liveDb, member, stranger } from './tactics-live-db.mjs';
const { db, call, fails } = await liveDb(['20261126090000_tactics_live', '20261127090000_tactics_live_chat',
  '20261128090000_tactics_live_idle', '20261129090000_tactics_live_draw', '20270401090000_tactics_live_groups',
  '20270402090000_tactics_live_group_overview']);
const sent = async () => (await db.query('select topic, event, payload from realtime.sent')).rows;
const clearSent = () => db.exec('delete from realtime.sent');

const board = { id: 'b1', frames: [{ objects: [{ id: 'p1', x: 10, y: 10 }] }] };
const project = await call(host, "select api.create_tactics_project('Anfall','education',null,$1)", [JSON.stringify({ schemaVersion: 1, boards: [board] })]);
const session = await call(host, 'select api.start_tactics_live($1,true)', [project.id]);
await call(member, "select api.join_tactics_live($1,'')", [session.code]);
await call(guest, "select api.join_tactics_live($1,'Gästen')", [session.code], true);
const lesson = `tactics-live:${session.id}`;

// The host's list brings every group's copy and moves, none shown yet.
let groups = await call(host, 'select api.start_tactics_live_groups($1,2,$2,0)', [session.id, JSON.stringify(board)]);
assert.deepEqual(groups.map(group => [group.number, group.board.id, group.moves, group.shown]), [[1, 'b1', {}, false], [2, 'b1', {}, false]]);
const memberGroup = () => call(member, 'select api.get_tactics_live_group($1)', [session.id]);
const mine = await memberGroup();
const other = groups.find(group => group.id !== mine.id);
assert.equal(mine.board.id, 'b1', 'a participant still gets the copy');

// Moving a participant: only the host, only to a group of this lesson, only someone in it.
await fails(member, 'select api.assign_tactics_live_group($1,$2,$3)', [session.id, member, other.id], /not_found/);
await fails(host, 'select api.assign_tactics_live_group($1,$2,$3)', [session.id, member, session.id], /invalid_group/);
await fails(host, 'select api.assign_tactics_live_group($1,$2,$3)', [session.id, stranger, other.id], /invalid_participant/);
await clearSent();
groups = await call(host, 'select api.assign_tactics_live_group($1,$2,$3)', [session.id, member, other.id]);
assert.equal((await memberGroup()).id, other.id);
assert.deepEqual(groups.map(group => group.members.length), mine.id === groups[0].id ? [0, 2] : [2, 0]);
assert.deepEqual((await sent()).map(row => [row.topic, row.event, row.payload]), [[lesson, 'group-assigned', { profileId: member, groupId: other.id }]]);

// Showing a group: only the host, only a group of this lesson; everyone in the lesson reads it.
await fails(member, 'select api.show_tactics_live_group($1,$2)', [session.id, other.id], /not_found/);
await fails(host, 'select api.show_tactics_live_group($1,$2)', [session.id, session.id], /invalid_group/);
assert.equal(await call(guest, 'select api.get_tactics_live_shown_group($1)', [session.id], true), null);
await clearSent();
await call(host, 'select api.show_tactics_live_group($1,$2)', [session.id, other.id]);
assert.deepEqual((await sent()).map(row => [row.topic, row.event, row.payload]), [[lesson, 'group-shown', { groupId: other.id }]]);
assert.equal((await call(guest, 'select api.get_tactics_live_shown_group($1)', [session.id], true)).id, other.id);
assert.equal((await call(host, 'select api.get_tactics_live_shown_group($1)', [session.id])).board.id, 'b1');
assert.deepEqual((await call(host, 'select api.list_tactics_live_groups($1)', [session.id])).map(group => group.shown), groups.map(group => group.id === other.id));
await fails(stranger, 'select api.get_tactics_live_shown_group($1)', [session.id], /not_found/);

// A shown group's moves reach the whole lesson too; another group's stay in the group.
await clearSent();
await call(member, 'select api.move_tactics_live_group($1,0,$2,true)', [session.id, JSON.stringify({ p1: { x: 30, y: 31 } })]);
const shownMove = { groupId: other.id, boardId: 'b1', frameIndex: 0, moves: { p1: { x: 30, y: 31 } }, dropped: true, by: member };
assert.deepEqual((await sent()).map(row => [row.topic, row.event, row.payload]),
  [[`tactics-live-group:${other.id}`, 'group-move', shownMove], [lesson, 'shown-move', shownMove]]);
assert.deepEqual((await call(guest, 'select api.get_tactics_live_shown_group($1)', [session.id], true)).moves, { 0: { p1: { x: 30, y: 31 } } });
await call(host, 'select api.assign_tactics_live_group($1,$2,$3)', [session.id, guest, mine.id]);
await clearSent();
await call(guest, 'select api.move_tactics_live_group($1,0,$2,true)', [session.id, JSON.stringify({ p1: { x: 5, y: 5 } })], true);
assert.deepEqual((await sent()).map(row => row.event), ['group-move']);

// None shown again.
await call(host, 'select api.show_tactics_live_group($1,null)', [session.id]);
assert.equal(await call(member, 'select api.get_tactics_live_shown_group($1)', [session.id]), null);

// Ending the group work, or the lesson, leaves nothing shown.
await call(host, 'select api.show_tactics_live_group($1,$2)', [session.id, other.id]);
await call(host, 'select api.end_tactics_live_groups($1)', [session.id]);
assert.equal((await db.query('select shown_group from core.tactics_live_sessions where id = $1', [session.id])).rows[0].shown_group, null);
groups = await call(host, 'select api.start_tactics_live_groups($1,2,$2,0)', [session.id, JSON.stringify(board)]);
await call(host, 'select api.show_tactics_live_group($1,$2)', [session.id, groups[0].id]);
await call(host, 'select api.end_tactics_live($1)', [session.id]);
assert.equal((await db.query('select shown_group from core.tactics_live_sessions where id = $1', [session.id])).rows[0].shown_group, null);
assert.equal((await db.query('select count(*)::int n from core.tactics_live_groups')).rows[0].n, 0);
console.log('tactics live group overview: ok');
