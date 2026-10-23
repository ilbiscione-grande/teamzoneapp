// Webtools Tacticsboard live lessons, step 4 (2026-10-23): questions on the
// pitch, answers kept from the others until shown, and the summary.
// node supabase/tests/tactics-live-questions.local.mjs
import assert from 'node:assert/strict';
import { guest, host, liveDb, member, stranger } from './tactics-live-db.mjs';
const { db, call, fails } = await liveDb(['20261126090000_tactics_live', '20261127090000_tactics_live_chat',
  '20261128090000_tactics_live_idle', '20261129090000_tactics_live_draw', '20261201090000_tactics_live_questions']);
const sent = async () => (await db.query('select topic, event, payload from realtime.sent')).rows;
const clearSent = () => db.exec('delete from realtime.sent');

const project = await call(host, "select api.create_tactics_project('Omställning','education',null,$1)", [JSON.stringify({ schemaVersion: 1, boards: [{ id: 'b1' }] })]);
const session = await call(host, 'select api.start_tactics_live($1,true)', [project.id]);
await call(member, "select api.join_tactics_live($1,'')", [session.code]);
await call(guest, "select api.join_tactics_live($1,'Gästen')", [session.code], true);
const answer = (who, id, x, y, anonymous = false) => call(who, 'select api.answer_tactics_live_question($1,$2,$3)', [id, x, y], anonymous);

// Asking: the host alone; everyone hears the question, without answers.
await clearSent();
await fails(member, "select api.ask_tactics_live_question($1,'b1',0,'Var?')", [session.id], /not_found/);
await fails(host, "select api.ask_tactics_live_question($1,'b1',0,'  ')", [session.id], /invalid_question/);
const asked = await call(host, "select api.ask_tactics_live_question($1,'b1',2,'Var ska 6:an stå?')", [session.id]);
assert.deepEqual([asked.prompt, asked.status, asked.frame_index, asked.answers], ['Var ska 6:an stå?', 'open', 2, []]);
const [heard] = await sent();
assert.deepEqual([heard.topic, heard.event, heard.payload.prompt, heard.payload.answers, heard.payload.points], [`tactics-live:${session.id}`, 'question', 'Var ska 6:an stå?', null, null]);

// Answering: one marker each, movable; only the host hears of it.
await clearSent();
assert.deepEqual(await answer(member, asked.id, 40, 30), { x: 40, y: 30 });
await answer(member, asked.id, 42.123, 31);
await answer(guest, asked.id, 60, 20, true);
assert.ok((await sent()).every(row => row.topic === `tactics-live-host:${session.id}` && row.event === 'answer'));
await fails(host, 'select api.answer_tactics_live_question($1,1,1)', [asked.id], /host_does_not_answer/);
await fails(stranger, 'select api.answer_tactics_live_question($1,1,1)', [asked.id], /not_found/);
await fails(member, 'select api.answer_tactics_live_question($1,1,999)', [asked.id], /invalid_answer/);
const forHost = (await call(host, 'select api.list_tactics_live_questions($1)', [session.id]))[0];
assert.deepEqual(forHost.answers.map(a => [a.name, Number(a.x), Number(a.y)]), [['Mats', 42.12, 31], ['Gästen', 60, 20]]);
const forMember = (await call(member, 'select api.list_tactics_live_questions($1)', [session.id]))[0];
assert.deepEqual([forMember.answers, forMember.points, Number(forMember.mine.x), forMember.answer_count], [null, null, 42.12, 2], 'no one else’s answer');

// Closing, then showing: the points without names for everyone.
await call(host, 'select api.close_tactics_live_question($1,false)', [asked.id]);
await fails(member, 'select api.answer_tactics_live_question($1,1,1)', [asked.id], /question_closed/);
await clearSent();
const shown = await call(host, 'select api.close_tactics_live_question($1,true)', [asked.id]);
assert.equal(shown.revealed, true);
const [reveal] = await sent();
assert.deepEqual([reveal.event, reveal.payload.points.length, JSON.stringify(reveal.payload).includes('Mats')], ['question', 2, false]);

// A new question closes the one before.
const second = await call(host, "select api.ask_tactics_live_question($1,'b1',0,'Och 8:an?')", [session.id]);
await answer(member, second.id, 50, 34);
await call(host, "select api.ask_tactics_live_question($1,'b1',0,'Och 10:an?')", [session.id]);
assert.deepEqual((await call(host, 'select api.list_tactics_live_questions($1)', [session.id])).map(q => q.status), ['closed', 'closed', 'open']);

// The summary and the earlier lessons: the host's alone, also after the end.
await call(member, 'select api.send_tactics_live_message($1,$2)', [session.id, 'Tack!']);
await call(host, 'select api.end_tactics_live($1)', [session.id]);
const summary = await call(host, 'select api.get_tactics_live_summary($1)', [session.id]);
assert.deepEqual([summary.participants.map(p => p.name), summary.messages.map(m => m.body), summary.questions.length], [['Mats', 'Gästen'], ['Tack!'], 3]);
assert.ok(summary.ended_at);
await fails(member, 'select api.get_tactics_live_summary($1)', [session.id], /not_found/);
const lessons = await call(host, 'select api.list_tactics_live_sessions($1)', [project.id]);
assert.deepEqual(lessons.map(l => [l.participant_count, l.question_count, l.live]), [[2, 3, false]]);
assert.deepEqual(await call(member, 'select api.list_tactics_live_sessions($1)', [project.id]), []);
console.log('tactics live questions: ok');
