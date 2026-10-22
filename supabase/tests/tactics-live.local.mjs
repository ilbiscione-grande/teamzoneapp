// Webtools Tacticsboard live lessons, step 1 (2026-10-22): sessions, joining
// with a code, guests or login only, and who may listen and send on the
// session's Realtime channel.
// node supabase/tests/tactics-live.local.mjs
import assert from 'node:assert/strict';
import { guest, host, liveDb, member, stranger } from './tactics-live-db.mjs';
const { db, as, asRole, call, fails } = await liveDb(['20261126090000_tactics_live']);

const project = await call(host, "select api.create_tactics_project('Försvarsspel','education',null,$1)", [JSON.stringify({ schemaVersion: 1, boards: [{ id: 'b1' }] })]);

// Starting: only your own project, and not as a guest; the same session again while it runs.
const session = await call(host, 'select api.start_tactics_live($1,true)', [project.id]);
assert.match(session.code, /^[A-HJ-NP-Z2-9]{6}$/);
assert.deepEqual([session.allow_guests, session.live], [true, true]);
assert.equal((await call(host, 'select api.start_tactics_live($1,true)', [project.id])).id, session.id, 'the running session');
assert.equal((await call(host, 'select api.get_tactics_live($1)', [project.id])).code, session.code);
await fails(member, 'select api.start_tactics_live($1,true)', [project.id], /not_found/);
await fails(guest, 'select api.start_tactics_live($1,true)', [project.id], /not_signed_in/, true);
assert.equal(await call(member, 'select api.get_tactics_live($1)', [project.id]), null);

// Joining: the board as saved, with the name; a guest needs a name, an account has its own.
const joined = await call(member, "select api.join_tactics_live($1,'')", [session.code.toLowerCase()]);
assert.deepEqual([joined.id, joined.name, joined.participant_name, joined.host_name, joined.document.boards[0].id],
  [session.id, 'Försvarsspel', 'Mats', 'Tränare Tina', 'b1']);
await fails(guest, "select api.join_tactics_live($1,'  ')", [session.code], /invalid_name/, true);
assert.equal((await call(guest, "select api.join_tactics_live($1,' Gästen ')", [session.code], true)).participant_name, 'Gästen');
await fails(member, "select api.join_tactics_live('AAAAAA','')", [], /not_found/);

// The channel: the host sends, participants listen and say they are there, others nothing.
const topic = `tactics-live:${session.id}`;
const send = async (who, extension, anonymous = false) => {
  await db.query("select set_config('realtime.topic',$1,false)", [topic]);
  return call(who, 'insert into realtime.messages(topic, extension) values ($1,$2)', [topic, extension], anonymous).then(() => true, () => false);
};
const sendOnce = async (who, extension, anonymous) => { await db.exec('savepoint m'); const ok = await send(who, extension, anonymous); await db.exec('rollback to m'); return ok; };
assert.equal(await sendOnce(host, 'broadcast'), true);
assert.equal(await sendOnce(member, 'broadcast'), false, 'participants do not broadcast');
assert.equal(await sendOnce(member, 'presence'), true);
assert.equal(await sendOnce(guest, 'presence', true), true);
assert.equal(await sendOnce(stranger, 'presence'), false);
const listens = async (who, anonymous = false) => { await as(who, anonymous); return asRole('authenticated', async () => (await db.query('select internal.tactics_live_can_listen($1) v', [topic])).rows[0].v); };
assert.deepEqual([await listens(host), await listens(member), await listens(guest, true), await listens(stranger)], [true, true, true, false]);

// Login only: guests go, and no new guests come in.
await fails(member, 'select api.set_tactics_live_guests($1,false)', [session.id], /not_found/);
assert.equal((await call(host, 'select api.set_tactics_live_guests($1,false)', [session.id])).allow_guests, false);
assert.equal(await listens(guest, true), false);
await fails(stranger, "select api.join_tactics_live($1,'Gäst 2')", [session.code], /login_required/, true);
assert.equal(await listens(member), true);

// Ended: nobody listens, the code leads nowhere, a new start makes a new session.
await call(host, 'select api.end_tactics_live($1)', [session.id]);
assert.equal(await listens(member), false);
assert.equal(await sendOnce(host, 'broadcast'), false);
await fails(member, "select api.join_tactics_live($1,'')", [session.code], /not_found/);
assert.notEqual((await call(host, 'select api.start_tactics_live($1,false)', [project.id])).id, session.id);
console.log('tactics live: ok');
