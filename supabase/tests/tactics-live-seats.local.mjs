// A live lesson takes 12 participants; whoever has joined keeps their seat.
// node supabase/tests/tactics-live-seats.local.mjs
import assert from 'node:assert/strict';
import { guest, host, liveDb, member, stranger } from './tactics-live-db.mjs';
const { db, call, fails } = await liveDb(['20261126090000_tactics_live', '20261127090000_tactics_live_chat', '20270212090000_tactics_live_twelve_seats']);

const project = await call(host, "select api.create_tactics_project('Pressspel','education',null,$1)", [JSON.stringify({ schemaVersion: 1, boards: [{ id: 'b1' }] })]);
const session = await call(host, 'select api.start_tactics_live($1,true)', [project.id]);
await call(member, "select api.join_tactics_live($1,'')", [session.code]);
await db.query(`insert into core.tactics_live_participants (session_id, profile_id, display_name, is_guest)
  select $1, gen_random_uuid(), 'Gäst ' || n, true from generate_series(1, 10) n`, [session.id]);

// The 12th gets in, the 13th does not, and one already in comes back.
await call(guest, "select api.join_tactics_live($1,'Sista')", [session.code], true);
await fails(stranger, "select api.join_tactics_live($1,'En till')", [session.code], /session_full/);
await call(member, "select api.join_tactics_live($1,'')", [session.code]);
const seats = await db.query('select count(*)::int n from core.tactics_live_participants where session_id = $1', [session.id]);
assert.equal(seats.rows[0].n, 12);
console.log('ok');
