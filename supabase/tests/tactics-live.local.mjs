// Webtools Tacticsboard live lessons, step 1 (2026-10-22): sessions, joining
// with a code, guests or login only, and who may listen and send on the
// session's Realtime channel.
// node supabase/tests/tactics-live.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const host = id(1), member = id(2), guest = id(3), stranger = id(4), club = id(10), team = id(20);
// Who is calling: an account, or a guest (an anonymous sign-in).
const as = (who, anonymous = false) => db.query(
  "select set_config('request.jwt.claim.sub',$1,false), set_config('request.jwt.claims',$2,false)",
  [who ?? '', JSON.stringify({ sub: who, is_anonymous: anonymous })]);
// No finally: in an aborted transaction it would hide the real error.
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
const call = async (who, sql, params = [], anonymous = false) => {
  await as(who, anonymous);
  return asRole('authenticated', async () => Object.values((await db.query(sql, params)).rows[0] ?? {})[0]);
};
const fails = async (who, sql, params, pattern, anonymous = false) => {
  await db.exec('savepoint s');
  await assert.rejects(call(who, sql, params, anonymous), pattern);
  await db.exec('rollback to s');
};
await db.exec(`create role anon; create role authenticated; create role service_role;
create schema internal; create schema api; create schema core; create schema auth; create schema realtime;
set check_function_bodies = off;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
create table core.profiles(id uuid primary key, display_name text default '');
insert into core.profiles(id, display_name) values ('${host}','Tränare Tina'),('${member}','Mats'),('${guest}',''),('${stranger}','');
create table core.clubs(id uuid primary key, name text); insert into core.clubs values ('${club}','Demoklubben IF');
create table core.teams(id uuid primary key, club_id uuid, name text, status text default 'active');
insert into core.teams values ('${team}','${club}','P2012');
create table core.club_people(id uuid primary key, display_name text);
create table core.person_account_links(profile_id uuid, club_id uuid, club_person_id uuid, state text);
create table core.assignments(club_id uuid, team_id uuid, club_person_id uuid, role_package text, state text default 'active',
  starts_at timestamptz default now()-interval '1 year', ends_at timestamptz);
create table core.team_person_details(team_id uuid, club_person_id uuid, main_position text, positions text[], jersey_number smallint);
create table core.events(id uuid primary key);
create function internal.booking_person_name(p uuid) returns text language sql stable as $$select null::text$$;
create function internal.actor_can_read_event(e uuid) returns boolean language sql stable as $$select false$$;
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$select true$$;
-- Realtime's own table and topic, as far as the policies need them.
create table realtime.messages(topic text, extension text, payload jsonb, event text);
alter table realtime.messages enable row level security;
create function realtime.topic() returns text language sql stable as $$select current_setting('realtime.topic',true)$$;
grant usage on schema api, internal, core, auth, realtime to authenticated, service_role;
grant select, insert on realtime.messages to authenticated;`);
for (const name of ['20261119090000_tournament_planner', '20261120090000_tournament_schedule', '20261121090000_tournament_teamzone',
  '20261123090000_tacticsboard', '20261126090000_tactics_live']) await db.exec(read(`supabase/migrations/${name}.sql`));
await db.exec('begin');

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
