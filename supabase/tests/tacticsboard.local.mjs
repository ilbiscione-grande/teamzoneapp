// Webtools Tacticsboard, part 1 (2026-10-21): projects on the account.
// node supabase/tests/tacticsboard.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), other = id(2), club = id(10), team = id(20), otherTeam = id(21);
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who ?? '']);
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
const call = async (who, sql, params = []) => { await as(who); return asRole('authenticated', async () => Object.values((await db.query(sql, params)).rows[0] ?? {})[0]); };
const fails = async (who, sql, params, pattern) => {
  await db.exec('savepoint s');
  // No finally: in an aborted transaction it would hide the real error.
  await assert.rejects(call(who, sql, params), pattern);
  await db.exec('rollback to s');
};
await db.exec(`create role anon; create role authenticated; create role service_role;
create schema internal; create schema api; create schema core; create schema auth;
set check_function_bodies = off;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.profiles(id uuid primary key); insert into core.profiles values ('${coach}'),('${other}');
create table core.clubs(id uuid primary key, name text); insert into core.clubs values ('${club}','Demoklubben IF');
create table core.teams(id uuid primary key, club_id uuid, name text, status text default 'active');
insert into core.teams values ('${team}','${club}','P2012'),('${otherTeam}','${club}','F2013');
create table core.club_people(id uuid primary key, display_name text);
insert into core.club_people values ('${id(50)}','Coach'),('${id(60)}','Alva'),('${id(61)}','Bror'),('${id(62)}','Cleo');
create table core.person_account_links(profile_id uuid, club_id uuid, club_person_id uuid, state text);
insert into core.person_account_links values ('${coach}','${club}','${id(50)}','active');
create table core.assignments(club_id uuid, team_id uuid, club_person_id uuid, role_package text, state text default 'active',
  starts_at timestamptz default now()-interval '1 year', ends_at timestamptz);
insert into core.assignments(club_id, team_id, club_person_id, role_package) values ('${club}','${team}','${id(50)}','leader'),
  ('${club}','${team}','${id(60)}','player'),('${club}','${team}','${id(61)}','player'),('${club}','${otherTeam}','${id(62)}','player');
insert into core.assignments(club_id, team_id, club_person_id, role_package, ends_at) values ('${club}','${team}','${id(62)}','player', now()-interval '1 day');
create table core.team_person_details(team_id uuid, club_person_id uuid, main_position text, positions text[], jersey_number smallint);
insert into core.team_person_details values ('${team}','${id(60)}','Målvakt',null,null),('${team}','${id(61)}',null,array['Mittfält','Anfall'],7);
create table core.events(id uuid primary key);
create function internal.booking_person_name(p uuid) returns text language sql stable as $$select null::text$$;
create function internal.actor_can_read_event(e uuid) returns boolean language sql stable as $$select false$$;
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$select true$$;
grant usage on schema api, internal, core, auth to authenticated, service_role;`);
await db.exec(read('supabase/migrations/20261119090000_tournament_planner.sql'));
await db.exec(read('supabase/migrations/20261120090000_tournament_schedule.sql'));
await db.exec(read('supabase/migrations/20261121090000_tournament_teamzone.sql'));
await db.exec(read('supabase/migrations/20261123090000_tacticsboard.sql'));
await db.exec(read('supabase/migrations/20261124090000_tactics_share_links.sql'));
await db.exec(read('supabase/migrations/20261125090000_tactics_templates.sql'));
await db.exec('begin');

const doc = boards => JSON.stringify({ schemaVersion: 1, boards });
// A project is yours; a team only one you lead.
const created = await call(coach, "select api.create_tactics_project('Matchgenomgång','match',$1,$2)", [team, doc([{ id: 'b1' }])]);
assert.deepEqual([created.name, created.kind, created.team_name, created.board_count, created.revision], ['Matchgenomgång', 'match', 'P2012', 1, 1]);
await fails(coach, "select api.create_tactics_project('X','match',$1,$2)", [otherTeam, doc([])], /not_team_leader/);
await fails(coach, "select api.create_tactics_project('X','party',null,$1)", [doc([])], /invalid_kind/);
await fails(coach, "select api.create_tactics_project('X','match',null,'[]')", [], /invalid_document/);
await fails(other, 'select api.get_tactics_project($1)', [created.id], /not_found/);
assert.deepEqual(await call(other, 'select api.list_my_tactics_projects()'), []);

// Saved whole with the revision read; a stale one is refused.
const loaded = await call(coach, 'select api.get_tactics_project($1)', [created.id]);
assert.deepEqual(loaded.document.boards, [{ id: 'b1' }]);
assert.equal(await call(coach, "select api.save_tactics_project($1,1,'Matchgenomgång v2','match',$2,$3)", [created.id, team, doc([{ id: 'b1' }, { id: 'b2' }])]), 2);
await fails(coach, "select api.save_tactics_project($1,1,'Gammal','match',null,$2)", [created.id, doc([])], /stale_revision/);
await fails(other, "select api.save_tactics_project($1,2,'Kapad','match',null,$2)", [created.id, doc([])], /not_found/);
await fails(coach, "select api.save_tactics_project($1,2,'X','match',$2,$3)", [created.id, otherTeam, doc([])], /not_team_leader/);
const list = await call(coach, 'select api.list_my_tactics_projects()');
assert.deepEqual(list.map(p => [p.name, p.board_count, p.revision]), [['Matchgenomgång v2', 2, 2]]);

// The squad: active players of your team, with their main position.
assert.deepEqual((await call(coach, 'select api.list_tactics_team_players($1)', [team])).map(p => [p.name, p.number, p.position]),
  [['Bror', 7, 'Mittfält'], ['Alva', null, 'Målvakt']], 'numbered first');
await fails(coach, 'select api.list_tactics_team_players($1)', [otherTeam], /not_team_leader/);

// Share links: the owner makes one per board (or the project), anyone
// with it sees the boards through Webtools' server; revoked, nothing.
const shared = async token => { await as(null); return asRole('service_role', async () => (await db.query('select api.get_shared_tactics($1) v', [token])).rows[0].v); };
const whole = await call(coach, 'select api.create_tactics_share_link($1,null)', [created.id]);
assert.match(whole, /^[0-9a-f]{40}$/);
assert.equal(await call(coach, 'select api.create_tactics_share_link($1,null)', [created.id]), whole, 'the same link again');
const one = await call(coach, "select api.create_tactics_share_link($1,'b2')", [created.id]);
assert.notEqual(one, whole);
await fails(coach, "select api.create_tactics_share_link($1,'nope')", [created.id], /not_found/);
await fails(other, 'select api.create_tactics_share_link($1,null)', [created.id], /not_found/);
assert.deepEqual((await call(coach, 'select api.list_tactics_share_links($1)', [created.id])).map(l => l.board_id), [null, 'b2']);
const page = await shared(whole);
assert.deepEqual([page.name, page.kind, page.team_name, page.boards.map(b => b.id)], ['Matchgenomgång v2', 'match', 'P2012', ['b1', 'b2']]);
assert.deepEqual((await shared(one)).boards.map(b => b.id), ['b2']);
assert.equal(await shared('0'.repeat(40)), null);
await fails(coach, 'select api.get_shared_tactics($1)', [whole], /permission denied/);
await fails(other, 'select api.revoke_tactics_share_link($1)', [one], /not_found/);
await call(coach, 'select api.revoke_tactics_share_link($1)', [one]);
assert.equal(await shared(one), null);
assert.equal((await call(coach, 'select api.list_tactics_share_links($1)', [created.id])).length, 1);

// Templates: yours alone; the same name replaces, the boards' names listed.
const tpl = await call(coach, "select api.save_tactics_template('Fasta situationer','match',$1)", [doc([{ id: 'h1', name: 'Hörna' }, { id: 'f1', name: 'Frispark' }])]);
assert.equal(await call(coach, "select api.save_tactics_template(' fasta SITUATIONER ','match',$1)", [doc([{ id: 'h1', name: 'Hörna anfall' }])]), tpl, 'replaced by name');
await call(coach, "select api.save_tactics_template('Uppvärmning','training',$1)", [doc([{ id: 'u1', name: 'Rondo' }])]);
const templates = await call(coach, 'select api.list_my_tactics_templates()');
assert.deepEqual(templates.map(t => [t.name, t.kind, t.boards.map(b => b.name)]).sort(), [['Uppvärmning', 'training', ['Rondo']], ['fasta SITUATIONER', 'match', ['Hörna anfall']]]);
assert.deepEqual((await call(coach, 'select api.get_tactics_template($1)', [tpl])).document.boards, [{ id: 'h1', name: 'Hörna anfall' }]);
assert.deepEqual(await call(other, 'select api.list_my_tactics_templates()'), []);
await fails(other, 'select api.get_tactics_template($1)', [tpl], /not_found/);
await fails(other, 'select api.delete_tactics_template($1)', [tpl], /not_found/);
await fails(coach, "select api.save_tactics_template('Tom','match',$1)", [doc([])], /invalid_document/);
await fails(coach, "select api.save_tactics_template('  ','match',$1)", [doc([{ id: 'x' }])], /invalid_name/);
await fails(coach, "select api.save_tactics_template('X','party',$1)", [doc([{ id: 'x' }])], /invalid_kind/);
await call(coach, 'select api.delete_tactics_template($1)', [tpl]);
assert.equal((await call(coach, 'select api.list_my_tactics_templates()')).length, 1);

await fails(other, 'select api.delete_tactics_project($1)', [created.id], /not_found/);
await call(coach, 'select api.delete_tactics_project($1)', [created.id]);
assert.deepEqual(await call(coach, 'select api.list_my_tactics_projects()'), []);
console.log('tacticsboard: ok');
