// Webtools Tacticsboard live lessons (2026-10-22): a session ends by itself
// after 30 minutes without activity; the host's page, a message or someone
// joining keeps it going.
// node supabase/tests/tactics-live-idle.local.mjs
import assert from 'node:assert/strict';
import { host, liveDb, member, stranger } from './tactics-live-db.mjs';
const { db, call, fails } = await liveDb(['20261126090000_tactics_live', '20261127090000_tactics_live_chat', '20261128090000_tactics_live_idle']);
const idleFor = minutes => db.query(`update core.tactics_live_sessions set last_activity_at = now() - interval '${minutes} minutes'`);
const lastActivity = async () => (await db.query('select extract(epoch from now() - last_activity_at)::int s from core.tactics_live_sessions where status = $1', ['live'])).rows[0].s;

const project = await call(host, "select api.create_tactics_project('Omställning','education',null,$1)", [JSON.stringify({ schemaVersion: 1, boards: [{ id: 'b1' }] })]);
const session = await call(host, 'select api.start_tactics_live($1,true)', [project.id]);
await call(member, "select api.join_tactics_live($1,'')", [session.code]);
const open = who => call(who, 'select api.tactics_live_open($1)', [session.id]);
assert.deepEqual([await open(host), await open(member), await open(stranger)], [true, true, false]);

// The host's page keeps it going; only the host may.
await idleFor(20);
assert.equal(await call(host, 'select api.touch_tactics_live($1)', [session.id]), true);
assert.ok(await lastActivity() < 5);
await fails(member, 'select api.touch_tactics_live($1)', [session.id], /not_found/);

// A message keeps it going too.
await idleFor(20);
await call(member, 'select api.send_tactics_live_message($1,$2)', [session.id, 'Hej']);
assert.ok(await lastActivity() < 5);

// 30 minutes without anything: over for everyone, and the code leads nowhere.
await idleFor(31);
assert.deepEqual([await open(host), await open(member)], [false, false]);
assert.equal(await call(host, 'select api.touch_tactics_live($1)', [session.id]), false, 'too late to keep it going');
await fails(member, "select api.join_tactics_live($1,'')", [session.code], /not_found/);
assert.equal(await call(member, 'select internal.tactics_live_can_listen($1)', [`tactics-live:${session.id}`]), false);
assert.equal(await call(host, 'select api.get_tactics_live($1)', [project.id]), null);

// Starting again ends it properly and makes a new one.
const next = await call(host, 'select api.start_tactics_live($1,true)', [project.id]);
assert.notEqual(next.id, session.id);
assert.equal((await db.query('select status from core.tactics_live_sessions where id = $1', [session.id])).rows[0].status, 'ended');
console.log('tactics live idle: ok');
