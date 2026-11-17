// Webtools Tacticsboard live lessons, group work step 4 (2026-11-17): full
// editing in a group. Objects are changed whole or removed, per frame;
// an edit replaces an older move of the same object; on the group's channel,
// and on the lesson's while the group is shown.
// node supabase/tests/tactics-live-group-edits.local.mjs
import assert from 'node:assert/strict';
import { guest, host, liveDb, member, stranger } from './tactics-live-db.mjs';
const { db, call, fails } = await liveDb(['20261126090000_tactics_live', '20261127090000_tactics_live_chat',
  '20261128090000_tactics_live_idle', '20261129090000_tactics_live_draw', '20270401090000_tactics_live_groups',
  '20270402090000_tactics_live_group_overview', '20270403090000_tactics_live_group_extras', '20270404090000_tactics_live_group_edits']);
const sent = async () => (await db.query('select topic, event, payload from realtime.sent')).rows;
const clearSent = () => db.exec('delete from realtime.sent');

const board = { id: 'b1', frames: [{ objects: [{ id: 'p1', type: 'player', x: 10, y: 10 }] }, { objects: [] }] };
const project = await call(host, "select api.create_tactics_project('Anfall','education',null,$1)", [JSON.stringify({ schemaVersion: 1, boards: [board] })]);
const session = await call(host, 'select api.start_tactics_live($1,true)', [project.id]);
await call(member, "select api.join_tactics_live($1,'')", [session.code]);
await call(guest, "select api.join_tactics_live($1,'Gästen')", [session.code], true);
const lesson = `tactics-live:${session.id}`;
const edit = (who, frame, objects, removed = [], anonymous = false) =>
  call(who, 'select api.edit_tactics_live_group($1,$2,$3,$4)', [session.id, frame, JSON.stringify(objects), JSON.stringify(removed)], anonymous);
const editFails = (who, frame, objects, removed, pattern) =>
  fails(who, 'select api.edit_tactics_live_group($1,$2,$3,$4)', [session.id, frame, JSON.stringify(objects), JSON.stringify(removed)], pattern);
const cone = { id: 'c1', type: 'cone', x: 50, y: 30, color: '#ff8800', scale: 1 };

await editFails(member, 0, { c1: cone }, [], /no_group/);
await call(host, 'select api.start_tactics_live_groups($1,2,$2,0)', [session.id, JSON.stringify(board)]);
const mine = await call(member, 'select api.get_tactics_live_group($1)', [session.id]);
assert.deepEqual(mine.edits, {});

// Only real objects, on a frame of the board, a sensible number at a time.
await editFails(member, 0, {}, [], /invalid_edit/);
await editFails(member, 2, { c1: cone }, [], /invalid_edit/);
await editFails(member, 0, { c1: { ...cone, id: 'other' } }, [], /invalid_edit/);
await editFails(member, 0, { c1: { ...cone, type: '' } }, [], /invalid_edit/);
await editFails(member, 0, { c1: { ...cone, x: 'far' } }, [], /invalid_edit/);
await editFails(member, 0, { c1: { ...cone, label: 'x'.repeat(20001) } }, [], /invalid_edit/);
await editFails(member, 0, {}, [5], /invalid_edit/);
await editFails(host, 0, { c1: cone }, [], /no_group/);
await editFails(stranger, 0, { c1: cone }, [], /not_found/);

// Placing, changing and removing: kept per frame, sent on the group's channel.
await clearSent();
await edit(member, 0, { c1: cone });
assert.deepEqual((await sent()).map(row => [row.topic, row.event, row.payload]),
  [[`tactics-live-group:${mine.id}`, 'group-edit', { groupId: mine.id, frameIndex: 0, objects: { c1: cone }, removed: [], by: member }]]);
await edit(member, 0, { c1: { ...cone, color: '#0000ff' } });
await edit(member, 1, { c1: cone });
await edit(member, 0, {}, ['p1']);
assert.deepEqual((await call(member, 'select api.get_tactics_live_group($1)', [session.id])).edits,
  { 0: { c1: { ...cone, color: '#0000ff' }, p1: null }, 1: { c1: cone } });
assert.deepEqual((await call(guest, 'select api.get_tactics_live_group($1)', [session.id], true)).edits, {}, 'the other group is untouched');
assert.ok((await call(host, 'select api.list_tactics_live_groups($1)', [session.id])).some(group => group.edits['0']?.c1), 'the host reads the edits');

// An edit replaces an older move of the same object; a later move stands beside it.
await call(member, 'select api.move_tactics_live_group($1,1,$2,true)', [session.id, JSON.stringify({ c1: { x: 70, y: 40 } })]);
await edit(member, 1, { c1: { ...cone, x: 60, y: 35 } });
let group = await call(member, 'select api.get_tactics_live_group($1)', [session.id]);
assert.deepEqual(group.moves['1'], {}, 'the move gave way');
await call(member, 'select api.move_tactics_live_group($1,1,$2,true)', [session.id, JSON.stringify({ c1: { x: 80, y: 41 } })]);
group = await call(member, 'select api.get_tactics_live_group($1)', [session.id]);
assert.deepEqual([group.moves['1'].c1, group.edits['1'].c1.x], [{ x: 80, y: 41 }, 60]);

// A shown group's edits reach the whole lesson.
await call(host, 'select api.show_tactics_live_group($1,$2)', [session.id, mine.id]);
await clearSent();
await edit(member, 0, {}, ['c1']);
assert.deepEqual((await sent()).map(row => [row.topic, row.event]), [[`tactics-live-group:${mine.id}`, 'group-edit'], [lesson, 'shown-edit']]);
assert.equal((await call(guest, 'select api.get_tactics_live_shown_group($1)', [session.id], true)).edits['0'].c1, null);

// Starting again starts from a clean copy.
await call(host, 'select api.start_tactics_live_groups($1,2,$2,0)', [session.id, JSON.stringify(board)]);
assert.deepEqual((await call(member, 'select api.get_tactics_live_group($1)', [session.id])).edits, {});
console.log('tactics live group edits: ok');
