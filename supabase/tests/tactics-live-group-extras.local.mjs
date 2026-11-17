// Webtools Tacticsboard live lessons, group work step 3 (2026-11-17): drawing
// and a chat inside a group, and the group work's time. The class's own
// drawing and chat leave the groups' rows alone, and everything goes with
// the groups.
// node supabase/tests/tactics-live-group-extras.local.mjs
import assert from 'node:assert/strict';
import { guest, host, liveDb, member, stranger } from './tactics-live-db.mjs';
const { db, call, fails } = await liveDb(['20261126090000_tactics_live', '20261127090000_tactics_live_chat',
  '20261128090000_tactics_live_idle', '20261129090000_tactics_live_draw', '20270401090000_tactics_live_groups',
  '20270402090000_tactics_live_group_overview', '20270403090000_tactics_live_group_extras']);
const sent = async () => (await db.query('select topic, event, payload from realtime.sent')).rows;
const clearSent = () => db.exec('delete from realtime.sent');

const board = { id: 'b1', frames: [{ objects: [{ id: 'p1', x: 10, y: 10 }] }] };
const project = await call(host, "select api.create_tactics_project('Anfall','education',null,$1)", [JSON.stringify({ schemaVersion: 1, boards: [board] })]);
const session = await call(host, 'select api.start_tactics_live($1,true)', [project.id]);
await call(member, "select api.join_tactics_live($1,'')", [session.code]);
await call(guest, "select api.join_tactics_live($1,'Gästen')", [session.code], true);
const lesson = `tactics-live:${session.id}`;
const points = JSON.stringify([1, 1, 5, 5]);

// Outside group work there is no group to draw or chat in, nor a time to set.
await fails(member, 'select api.add_tactics_live_group_stroke($1,$2,$3)', [session.id, '#ff0000', points], /no_group/);
await fails(member, "select api.send_tactics_live_group_message($1,'hej')", [session.id], /no_group/);
await fails(host, 'select api.set_tactics_live_groups_timer($1,5)', [session.id], /no_groups/);

let groups = await call(host, 'select api.start_tactics_live_groups($1,2,$2,0)', [session.id, JSON.stringify(board)]);
const mine = await call(member, 'select api.get_tactics_live_group($1)', [session.id]);
const theirs = groups.find(group => group.id !== mine.id);
assert.deepEqual([mine.strokes, mine.messages, mine.ends_in], [[], [], null]);

// Drawing in a group, whatever the class's drawing mode (off here): on the group's channel only.
await fails(member, 'select api.add_tactics_live_group_stroke($1,$2,$3)', [session.id, 'red', points], /invalid_stroke/);
await fails(member, 'select api.add_tactics_live_group_stroke($1,$2,$3)', [session.id, '#ff0000', '[1,1]'], /invalid_stroke/);
await fails(host, 'select api.add_tactics_live_group_stroke($1,$2,$3)', [session.id, '#ff0000', points], /no_group/);
await fails(stranger, 'select api.add_tactics_live_group_stroke($1,$2,$3)', [session.id, '#ff0000', points], /not_found/);
await clearSent();
const stroke = await call(member, 'select api.add_tactics_live_group_stroke($1,$2,$3)', [session.id, '#ff0000', points]);
assert.deepEqual([stroke.board_id, stroke.name, stroke.points, stroke.group_id], ['b1', 'Mats', [1, 1, 5, 5], mine.id]);
assert.deepEqual((await sent()).map(row => [row.topic, row.event]), [[`tactics-live-group:${mine.id}`, 'group-stroke']]);
assert.equal((await call(member, 'select api.get_tactics_live_group($1)', [session.id])).strokes.length, 1);
assert.deepEqual((await call(guest, 'select api.get_tactics_live_group($1)', [session.id], true)).strokes, [], 'the other group does not see it');
assert.deepEqual(await call(member, 'select api.list_tactics_live_strokes($1)', [session.id]), [], 'not on the class layer');

// A shown group's strokes reach the whole lesson.
await call(host, 'select api.show_tactics_live_group($1,$2)', [session.id, mine.id]);
await clearSent();
await call(member, 'select api.add_tactics_live_group_stroke($1,$2,$3)', [session.id, '#00ff00', points]);
assert.deepEqual((await sent()).map(row => [row.topic, row.event]), [[`tactics-live-group:${mine.id}`, 'group-stroke'], [lesson, 'shown-stroke']]);
assert.equal((await call(guest, 'select api.get_tactics_live_shown_group($1)', [session.id], true)).strokes.length, 2);

// Clearing the class layer leaves the groups' strokes.
await call(host, 'select api.clear_tactics_live_strokes($1,null)', [session.id]);
assert.equal((await call(member, 'select api.get_tactics_live_group($1)', [session.id])).strokes.length, 2);

// The group's chat: its own, on its channel, not in the class chat; a participant whose chat is off cannot write.
await fails(member, "select api.send_tactics_live_group_message($1,'  ')", [session.id], /invalid_message/);
await clearSent();
const message = await call(member, "select api.send_tactics_live_group_message($1,'Vi trycker upp')", [session.id]);
assert.deepEqual([message.body, message.name, message.from_host, message.group_id], ['Vi trycker upp', 'Mats', false, mine.id]);
assert.deepEqual((await sent()).map(row => [row.topic, row.event]), [[`tactics-live-group:${mine.id}`, 'group-chat']]);
assert.deepEqual((await call(member, 'select api.get_tactics_live_group($1)', [session.id])).messages.map(m => m.body), ['Vi trycker upp']);
assert.deepEqual(await call(member, 'select api.list_tactics_live_messages($1)', [session.id]), [], 'not in the class chat');
assert.deepEqual(await call(host, 'select api.list_tactics_live_messages($1)', [session.id]), [], 'nor in the host\'s');
assert.equal((await call(host, 'select api.list_tactics_live_groups($1)', [session.id])).find(group => group.id === mine.id).messages.length, 1, 'the host reads it with the group');
await call(host, 'select api.mute_tactics_live_participant($1,$2,true)', [session.id, member]);
await fails(member, "select api.send_tactics_live_group_message($1,'hej')", [session.id], /muted/);
await call(host, 'select api.mute_tactics_live_participant($1,$2,false)', [session.id, member]);

// The time: only the host, 1–60 minutes, everyone told; read with the group; none again.
await fails(member, 'select api.set_tactics_live_groups_timer($1,5)', [session.id], /not_found/);
await fails(host, 'select api.set_tactics_live_groups_timer($1,0)', [session.id], /invalid_minutes/);
await fails(host, 'select api.set_tactics_live_groups_timer($1,61)', [session.id], /invalid_minutes/);
await clearSent();
await call(host, 'select api.set_tactics_live_groups_timer($1,5)', [session.id]);
assert.deepEqual((await sent()).map(row => [row.topic, row.event, row.payload]), [[lesson, 'groups-timer', { seconds: 300 }]]);
const endsIn = Number((await call(guest, 'select api.get_tactics_live_group($1)', [session.id], true)).ends_in);
assert.ok(endsIn > 290 && endsIn <= 300, `about five minutes left, ${endsIn}`);
await db.query("update core.tactics_live_sessions set groups_ends_at = now() - interval '1 minute' where id = $1", [session.id]);
assert.equal(Number((await call(member, 'select api.get_tactics_live_group($1)', [session.id])).ends_in), 0, 'time out is 0');
await clearSent();
await call(host, 'select api.set_tactics_live_groups_timer($1,null)', [session.id]);
assert.deepEqual((await sent()).map(row => row.payload), [{ seconds: null }]);
assert.equal((await call(member, 'select api.get_tactics_live_group($1)', [session.id])).ends_in, null);

// Ending the group work takes the groups' strokes, messages and time with it.
await call(host, 'select api.set_tactics_live_groups_timer($1,5)', [session.id]);
await call(host, 'select api.end_tactics_live_groups($1)', [session.id]);
assert.equal((await db.query('select count(*)::int n from core.tactics_live_strokes where group_id is not null')).rows[0].n, 0);
assert.equal((await db.query('select count(*)::int n from core.tactics_live_messages where group_id is not null')).rows[0].n, 0);
assert.equal((await db.query('select groups_ends_at from core.tactics_live_sessions where id = $1', [session.id])).rows[0].groups_ends_at, null);
assert.ok(theirs, 'two groups');

// A shown group with time running, and then the lesson ends: nothing left behind.
groups = await call(host, 'select api.start_tactics_live_groups($1,2,$2,0)', [session.id, JSON.stringify(board)]);
await call(host, 'select api.show_tactics_live_group($1,$2)', [session.id, groups[0].id]);
await call(host, 'select api.set_tactics_live_groups_timer($1,5)', [session.id]);
await call(host, 'select api.end_tactics_live($1)', [session.id]);
assert.deepEqual((await db.query('select shown_group, groups_ends_at from core.tactics_live_sessions where id = $1', [session.id])).rows[0], { shown_group: null, groups_ends_at: null });
console.log('tactics live group extras: ok');
