// Webtools Tacticsboard live lessons, step 2 (2026-10-22): the chat, its
// modes and moderation, and what the database sends where.
// node supabase/tests/tactics-live-chat.local.mjs
import assert from 'node:assert/strict';
import { guest, host, liveDb, member, stranger } from './tactics-live-db.mjs';
const { db, call, fails } = await liveDb(['20261126090000_tactics_live', '20261127090000_tactics_live_chat']);
const sent = async () => (await db.query('select topic, event, payload from realtime.sent')).rows;
const clearSent = () => db.exec('delete from realtime.sent');

const project = await call(host, "select api.create_tactics_project('Pressspel','education',null,$1)", [JSON.stringify({ schemaVersion: 1, boards: [{ id: 'b1' }] })]);
const session = await call(host, 'select api.start_tactics_live($1,true)', [project.id]);
assert.deepEqual([session.chat_mode, session.hands], ['on', true]);
const joined = await call(member, "select api.join_tactics_live($1,'')", [session.code]);
assert.equal(joined.muted, false);
await call(guest, "select api.join_tactics_live($1,'Gästen')", [session.code], true);
const send = (who, body, anonymous = false) => call(who, 'select api.send_tactics_live_message($1,$2)', [session.id, body], anonymous);
const history = (who, anonymous = false) => call(who, 'select api.list_tactics_live_messages($1)', [session.id], anonymous);

// Chat on: everyone's message goes to everyone on the session's topic.
const hello = await send(member, '  Hej! ');
assert.deepEqual([hello.name, hello.body, hello.from_host, hello.to_host], ['Mats', 'Hej!', false, false]);
const welcome = await send(host, 'Välkomna');
assert.deepEqual([welcome.name, welcome.from_host], ['Tränare Tina', true]);
assert.deepEqual((await sent()).map(row => [row.topic, row.event, row.payload.body]),
  [[`tactics-live:${session.id}`, 'chat', 'Hej!'], [`tactics-live:${session.id}`, 'chat', 'Välkomna']]);
await fails(stranger, 'select api.send_tactics_live_message($1,$2)', [session.id, 'Hej'], /not_found/);
await fails(member, 'select api.send_tactics_live_message($1,$2)', [session.id, '   '], /invalid_message/);
await fails(member, 'select api.send_tactics_live_message($1,$2)', [session.id, 'x'.repeat(501)], /invalid_message/);

// Questions only: a participant's message reaches the host alone, and the participant's own history.
assert.equal((await call(host, "select api.set_tactics_live_chat($1,'questions',false)", [session.id])).chat_mode, 'questions');
await clearSent();
const question = await send(guest, 'Varför pressar 9:an?', true);
assert.equal(question.to_host, true);
assert.deepEqual((await sent()).map(row => [row.topic, row.event]), [[`tactics-live-host:${session.id}`, 'chat']]);
assert.deepEqual((await history(member)).map(message => message.body), ['Hej!', 'Välkomna'], 'not the guest’s question');
assert.deepEqual((await history(guest, true)).map(message => message.body), ['Hej!', 'Välkomna', 'Varför pressar 9:an?']);
assert.deepEqual((await history(host)).map(message => message.body), ['Hej!', 'Välkomna', 'Varför pressar 9:an?']);
await fails(stranger, 'select api.list_tactics_live_messages($1)', [session.id], /not_found/);
await fails(member, "select api.set_tactics_live_chat($1,'on',true)", [session.id], /not_found/);

// Off: participants are quiet; the host still speaks.
await call(host, "select api.set_tactics_live_chat($1,'off',true)", [session.id]);
await fails(member, 'select api.send_tactics_live_message($1,$2)', [session.id, 'Hallå?'], /chat_off/);
await send(host, 'Nu lyssnar vi');

// One participant's chat turned off, and on again.
await call(host, "select api.set_tactics_live_chat($1,'on',true)", [session.id]);
await call(host, 'select api.mute_tactics_live_participant($1,$2,true)', [session.id, member]);
await fails(member, 'select api.send_tactics_live_message($1,$2)', [session.id, 'Får jag?'], /muted/);
assert.equal((await call(member, "select api.join_tactics_live($1,'')", [session.code])).muted, true, 'joining again keeps it');
await fails(member, 'select api.mute_tactics_live_participant($1,$2,false)', [session.id, guest], /not_found/);
await call(host, 'select api.mute_tactics_live_participant($1,$2,false)', [session.id, member]);
await send(member, 'Tack');

// The host removes a message: gone from the history, and said on both topics.
await clearSent();
await fails(member, 'select api.delete_tactics_live_message($1)', [hello.id], /not_found/);
await call(host, 'select api.delete_tactics_live_message($1)', [hello.id]);
assert.ok(!(await history(member)).some(message => message.id === hello.id));
assert.deepEqual((await sent()).map(row => [row.topic.split(':')[0], row.event]), [['tactics-live', 'chat-deleted'], ['tactics-live-host', 'chat-deleted']]);

// Five messages in ten seconds at most.
for (let i = 0; i < 4; i++) await send(guest, `Rad ${i}`, true);
await fails(guest, 'select api.send_tactics_live_message($1,$2)', [session.id, 'En till'], /too_fast/, true);

// The host's own topic is for the host alone.
assert.equal(await call(host, 'select internal.tactics_live_host_topic_open($1)', [`tactics-live-host:${session.id}`]), true);
assert.equal(await call(member, 'select internal.tactics_live_host_topic_open($1)', [`tactics-live-host:${session.id}`]), false);
console.log('tactics live chat: ok');
