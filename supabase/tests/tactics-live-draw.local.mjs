// Webtools Tacticsboard live lessons, step 3 (2026-10-22): drawing on a
// shared layer, and the floor given to one participant.
// node supabase/tests/tactics-live-draw.local.mjs
import assert from 'node:assert/strict';
import { guest, host, liveDb, member, stranger } from './tactics-live-db.mjs';
const { db, call, fails } = await liveDb(['20261126090000_tactics_live', '20261127090000_tactics_live_chat',
  '20261128090000_tactics_live_idle', '20261129090000_tactics_live_draw']);
const sent = async () => (await db.query('select topic, event, payload from realtime.sent')).rows;
const clearSent = () => db.exec('delete from realtime.sent');

const project = await call(host, "select api.create_tactics_project('Anfall','education',null,$1)", [JSON.stringify({ schemaVersion: 1, boards: [{ id: 'b1' }] })]);
const session = await call(host, 'select api.start_tactics_live($1,true)', [project.id]);
assert.deepEqual([session.draw_mode, session.floor_holder], ['off', null]);
await call(member, "select api.join_tactics_live($1,'')", [session.code]);
await call(guest, "select api.join_tactics_live($1,'Gästen')", [session.code], true);
const stroke = (who, points = [10, 10, 20, 15], anonymous = false) =>
  call(who, "select api.add_tactics_live_stroke($1,'b1','#ef4444',$2)", [session.id, JSON.stringify(points)], anonymous);

// Drawing off or own notes: nothing on the shared layer from participants; the host may.
await fails(member, "select api.add_tactics_live_stroke($1,'b1','#ef4444',$2)", [session.id, '[1,1,2,2]'], /drawing_off/);
assert.equal((await call(host, "select api.set_tactics_live_drawing($1,'own')", [session.id])).draw_mode, 'own');
await fails(member, "select api.add_tactics_live_stroke($1,'b1','#ef4444',$2)", [session.id, '[1,1,2,2]'], /drawing_off/);
await fails(member, "select api.set_tactics_live_drawing($1,'shared')", [session.id], /not_found/);

// Shared: a stroke is kept and sent to everyone; odd, empty or far-off points are refused.
await call(host, "select api.set_tactics_live_drawing($1,'shared')", [session.id]);
await clearSent();
const drawn = await stroke(member);
assert.deepEqual([drawn.name, drawn.color, drawn.points], ['Mats', '#ef4444', [10, 10, 20, 15]]);
assert.deepEqual((await sent()).map(row => [row.topic, row.event]), [[`tactics-live:${session.id}`, 'stroke']]);
await stroke(guest, [30, 30, 31, 31], true);
for (const bad of [[1, 1, 2], [1, 1], [1, 1, 2, 'x'], [1, 1, 2, 999], Array(602).fill(1)]) {
  await fails(member, "select api.add_tactics_live_stroke($1,'b1','#ef4444',$2)", [session.id, JSON.stringify(bad)], /invalid_stroke/);
}
await fails(member, "select api.add_tactics_live_stroke($1,'b1','red',$2)", [session.id, '[1,1,2,2]'], /invalid_stroke/);
await fails(stranger, "select api.add_tactics_live_stroke($1,'b1','#ef4444',$2)", [session.id, '[1,1,2,2]'], /not_found/);
assert.equal((await call(guest, 'select api.list_tactics_live_strokes($1)', [session.id], true)).length, 2);

// The host clears the layer, and everyone hears of it.
await fails(member, "select api.clear_tactics_live_strokes($1,'b1')", [session.id], /not_found/);
await clearSent();
await call(host, "select api.clear_tactics_live_strokes($1,'b1')", [session.id]);
assert.equal((await call(member, 'select api.list_tactics_live_strokes($1)', [session.id])).length, 0);
assert.deepEqual((await sent()).map(row => [row.event, row.payload.boardId]), [['strokes-cleared', 'b1']]);

// The floor: given to one participant, whose moves go to everyone, cleaned; nobody else's.
const moves = JSON.stringify({ p1: { x: 40, y: 30, extra: 'bort' } });
await fails(member, "select api.move_tactics_live_floor($1,'b1',0,$2,false)", [session.id, moves], /no_floor/);
await fails(member, 'select api.give_tactics_live_floor($1,$2)', [session.id, member], /not_found/);
await fails(host, 'select api.give_tactics_live_floor($1,$2)', [session.id, stranger], /not_found/);
const given = await call(host, 'select api.give_tactics_live_floor($1,$2)', [session.id, member]);
assert.deepEqual([given.floor_holder, given.floor_name], [member, 'Mats']);
await clearSent();
await call(member, "select api.move_tactics_live_floor($1,'b1',0,$2,true)", [session.id, moves]);
const [move] = await sent();
assert.deepEqual([move.event, move.payload.moves, move.payload.dropped, move.payload.by], ['floor-move', { p1: { x: 40, y: 30 } }, true, member]);
await fails(guest, "select api.move_tactics_live_floor($1,'b1',0,$2,false)", [session.id, moves], /no_floor/, true);
for (const bad of [{}, { p1: { x: 'a', y: 1 } }, { p1: { x: 1, y: 900 } }]) {
  await fails(member, "select api.move_tactics_live_floor($1,'b1',0,$2,false)", [session.id, JSON.stringify(bad)], /invalid_move/);
}
assert.equal((await call(host, 'select api.give_tactics_live_floor($1,null)', [session.id])).floor_holder, null, 'taken back');
await fails(member, "select api.move_tactics_live_floor($1,'b1',0,$2,false)", [session.id, moves], /no_floor/);
console.log('tactics live draw: ok');
