// Webtools Turneringsplanerare, part 3 (2026-10-21): search, registering a
// TeamZone team and the team's calendar. The event commands are stubbed.
// node supabase/tests/tournament_teamzone.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const host = id(1), coach = id(2), parent = id(3), stranger = id(4);
const club = id(10), team = id(20), otherTeam = id(21);
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
create table core.profiles(id uuid primary key, display_name text);
insert into core.profiles values ('${host}','Hanna'),('${coach}','Coach'),('${parent}','Pia'),('${stranger}','Sten');
create table core.clubs(id uuid primary key, name text); insert into core.clubs values ('${club}','Demoklubben IF');
create table core.teams(id uuid primary key, club_id uuid, name text, status text default 'active');
insert into core.teams values ('${team}','${club}','P2012'),('${otherTeam}','${club}','F2013');
create table core.person_account_links(profile_id uuid, club_id uuid, club_person_id uuid, state text);
insert into core.person_account_links values ('${coach}','${club}','${id(50)}','active');
create table core.assignments(club_id uuid, team_id uuid, club_person_id uuid, role_package text, state text default 'active',
  starts_at timestamptz default now()-interval '1 year', ends_at timestamptz);
insert into core.assignments(club_id, team_id, club_person_id, role_package) values ('${club}','${team}','${id(50)}','leader');
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$select true$$;
create function internal.booking_person_name(p uuid) returns text language sql stable as $$select display_name from core.profiles where id = p$$;
create function internal.actor_can_read_event(e uuid) returns boolean language sql stable as $$select auth.uid() in ('${coach}'::uuid, '${parent}'::uuid)$$;
-- The event commands, as stubs that keep what they were given.
create table core.events(id uuid primary key default gen_random_uuid(), club_id uuid, team_id uuid, title text, description text,
  event_type text, state text, starts_at timestamptz, ends_at timestamptz, location text, audiences text[], revision bigint default 1, created_by uuid);
create function internal.create_event_v2_for_actor(c uuid, t uuid, title text, description text, kind text, state text, s timestamptz, e timestamptz,
  all_day boolean, zone text, audiences text[], location text, f text, i integer, n integer, typed jsonb, k uuid)
  returns uuid language sql as $$insert into core.events(club_id, team_id, title, description, event_type, state, starts_at, ends_at, location, audiences, created_by)
  values (c, t, title, description, kind, state, s, e, location, audiences, auth.uid()) returning id$$;
create function internal.revise_event_v3_for_actor(e uuid, scope text, patch jsonb, expected bigint, k uuid) returns bigint language sql as
  $$update core.events set starts_at = (patch->>'starts_at')::timestamptz, ends_at = (patch->>'ends_at')::timestamptz, revision = revision + 1
  where id = e and revision = expected returning revision$$;
grant usage on schema api, internal, core, auth to authenticated, service_role;`);
await db.exec(read('supabase/migrations/20261119090000_tournament_planner.sql'));
await db.exec(read('supabase/migrations/20261120090000_tournament_schedule.sql'));
await db.exec(read('supabase/migrations/20261121090000_tournament_teamzone.sql'));
await db.exec(read('supabase/migrations/20261122090000_tournament_public_page.sql'));
await db.exec('begin');

const cup = await call(host, "select api.create_tournament('Höstcupen','Fotboll','Demovallen','2099-11-14','2099-11-15')");
const p12 = await call(host, "select api.save_tournament_class($1,null,'P12',null,'groups_playoff',null,1500,15,1)", [cup]);
const update = searchable => call(host, "select api.update_tournament_v2($1,'Höstcupen','Fotboll','Demovallen','2099-11-14','2099-11-15',null,null,'Swish 123',$2,true,null,$3)",
  [cup, 'published', searchable]);

// Searchable only when the organiser says so; by name, place or sport.
await update(false);
assert.deepEqual(await call(coach, "select api.search_tournaments('höst')"), []);
await update(true);
assert.equal((await call(host, 'select api.get_tournament($1)', [cup])).searchable, true);
const found = await call(coach, "select api.search_tournaments('demoval')");
assert.deepEqual(found.map(t => [t.name, t.registration_is_open, t.classes.map(c => c.name)]), [['Höstcupen', true, ['P12']]]);
assert.equal((await call(coach, "select api.search_tournaments('100%')")).length, 0, 'the pattern is escaped');
assert.equal((await call(coach, "select api.search_tournaments('')")).length, 1);

// A leader registers their own team, once per class; others cannot.
assert.deepEqual(await call(coach, 'select api.list_tournament_leader_teams()'), [{ team_id: team, team_name: 'P2012', club_id: club, club_name: 'Demoklubben IF' }]);
assert.deepEqual(await call(parent, 'select api.list_tournament_leader_teams()'), []);
const register = (who, teamId, name) => call(who, "select api.register_tournament_team_v2($1,$2,$3,'Demoklubben IF','Coach','coach@example.se',null,null)", [p12, teamId, name]);
await fails(coach, "select api.register_tournament_team_v2($1,$2,'F13',null,'Coach','coach@example.se',null,null)", [p12, otherTeam], /not_team_leader/);
const mine = await register(coach, team, 'Demoklubben P12');
assert.equal(mine.teamzone_team_id, team);
await fails(coach, "select api.register_tournament_team_v2($1,$2,'Demoklubben P12 Vit',null,'Coach','coach@example.se',null,null)", [p12, team], /team_already_registered/);
const other = await register(stranger, null, 'Aneby SK');
assert.equal(other.teamzone_team_id, null);
const teams = await call(coach, 'select api.list_my_team_tournaments()');
assert.deepEqual(teams.map(t => [t.tournament_name, t.team_name, t.teamzone_team_name, t.status, t.schedule_published, t.calendar_days]),
  [['Höstcupen', 'Demoklubben P12', 'P2012', 'pending', false, 0]]);

// The calendar waits for approval and a published schedule.
await fails(coach, 'select api.sync_tournament_team_calendar($1)', [mine.id], /not_approved/);
await call(host, 'select api.decide_tournament_registration($1,true)', [mine.id]);
await call(host, 'select api.decide_tournament_registration($1,true)', [other.id]);
await fails(coach, 'select api.sync_tournament_team_calendar($1)', [mine.id], /schedule_not_published/);
await fails(stranger, 'select api.sync_tournament_team_calendar($1)', [other.id], /not_found/);
const pitch = await call(host, "select api.save_tournament_pitch($1,null,'Plan 1',1)", [cup]);
// 08:00 and 09:00 UTC are 09:00 and 10:00 in Stockholm, both days.
const at = (day, h) => `2099-11-${day}T${String(h).padStart(2, '0')}:00:00Z`;
const groups = [{ name: 'A', registration_ids: [mine.id, other.id] }];
const games = [
  { group: 0, round: 1, home: mine.id, away: other.id, pitch_id: pitch, starts_at: at(14, 8), ends_at: at(14, 8) .replace(':00:00', ':15:00') },
  { group: 0, round: 2, home: other.id, away: mine.id, pitch_id: pitch, starts_at: at(14, 10), ends_at: at(14, 10).replace(':00:00', ':15:00') },
  { group: 0, round: 3, home: mine.id, away: other.id, pitch_id: pitch, starts_at: at(15, 9), ends_at: at(15, 9).replace(':00:00', ':15:00') },
];
await call(host, "select api.save_tournament_class_schedule($1,'group',$2,$3)", [p12, JSON.stringify(groups), JSON.stringify(games)]);
await call(host, 'select api.set_tournament_class_schedule_published($1,true)', [p12]);
assert.deepEqual(await call(coach, 'select api.sync_tournament_team_calendar($1)', [mine.id]), { created: 2, moved: 0, days: 2 });
let events = (await db.query('select title, event_type, state, starts_at, ends_at, location, audiences, team_id, created_by from core.events order by starts_at')).rows;
assert.deepEqual(events.map(e => [e.title, e.event_type, e.state, e.location, e.team_id, e.created_by]),
  [['Höstcupen · dag 1', 'activity', 'scheduled', 'Demovallen', team, coach], ['Höstcupen · dag 2', 'activity', 'scheduled', 'Demovallen', team, coach]]);
assert.deepEqual([events[0].starts_at.toISOString(), events[0].ends_at.toISOString()], ['2099-11-14T08:00:00.000Z', '2099-11-14T10:15:00.000Z']);
assert.deepEqual(events[0].audiences, ['players', 'leaders', 'guardians']);

// Synced again: the same days, moved to the new times.
assert.deepEqual(await call(coach, 'select api.sync_tournament_team_calendar($1)', [mine.id]), { created: 0, moved: 0, days: 2 });
const late = (await call(host, 'select api.get_tournament_schedule($1)', [cup])).classes[0].matches.find(m => m.round === 3);
await call(host, 'select api.set_tournament_match_time($1,$2,$3,$4)', [late.id, pitch, at(15, 11), at(15, 11).replace(':00:00', ':15:00')]);
assert.deepEqual(await call(coach, 'select api.sync_tournament_team_calendar($1)', [mine.id]), { created: 0, moved: 1, days: 2 });
assert.equal((await db.query("select starts_at from core.events where title = 'Höstcupen · dag 2'")).rows[0].starts_at.toISOString(), '2099-11-15T11:00:00.000Z');
assert.deepEqual((await call(coach, 'select api.list_my_team_tournaments()'))[0].calendar_days, 2);
assert.equal((await call(coach, 'select api.get_tournament($1)', [cup])).my_registrations[0].can_sync, true);

// The activity shows the team's matches that day and its group.
const day1 = (await db.query("select id from core.events where title = 'Höstcupen · dag 1'")).rows[0].id;
await call(host, 'select api.report_tournament_match_result($1,3,1,null,null)', [(await call(host, 'select api.get_tournament_schedule($1)', [cup])).classes[0].matches.find(m => m.round === 1).id]);
const onEvent = await call(parent, 'select api.get_event_tournament($1)', [day1]);
assert.deepEqual([onEvent.tournament_name, onEvent.class_name, onEvent.team_name], ['Höstcupen', 'P12', 'Demoklubben P12']);
assert.deepEqual(onEvent.matches.map(m => [m.home_name, m.away_name, m.home_score, m.pitch_name, m.group_name]),
  [['Demoklubben P12', 'Aneby SK', 3, 'Plan 1', 'A'], ['Aneby SK', 'Demoklubben P12', null, 'Plan 1', 'A']]);
assert.deepEqual(onEvent.groups[0].standings.map(r => [r.team_name, r.points]), [['Demoklubben P12', 3], ['Aneby SK', 0]]);
await fails(stranger, 'select api.get_event_tournament($1)', [day1], /not_found/);
assert.equal(await call(coach, 'select api.get_event_tournament($1)', [id(99)]), null, 'an activity without a tournament');
// Unpublished again: the activity shows nothing of it.
await call(host, 'select api.set_tournament_class_schedule_published($1,false)', [p12]);
assert.equal(await call(parent, 'select api.get_event_tournament($1)', [day1]), null);

// A new tournament is searchable once published, unless turned off.
const fresh = await call(host, "select api.create_tournament('Vårcupen',null,null,'2099-05-01','2099-05-01')");
assert.equal((await call(host, 'select api.get_tournament($1)', [fresh])).searchable, true);

// The public page, read by Webtools' server: published only, no contacts.
const publicView = async target => { await as(null); return asRole('service_role', async () => (await db.query('select api.get_public_tournament($1) v', [target])).rows[0].v); };
assert.equal(await publicView(fresh), null, 'a draft has no public page');
await call(host, 'select api.set_tournament_class_schedule_published($1,true)', [p12]);
const page = await publicView(cup);
assert.equal(page.name, 'Höstcupen');
assert.deepEqual(page.classes.map(c => [c.name, c.teams.map(t => t.team_name)]), [['P12', ['Demoklubben P12', 'Aneby SK']]]);
assert.ok(!JSON.stringify(page).includes('coach@example.se'), 'no team contacts');
assert.deepEqual(page.schedule.map(c => [c.name, c.matches.length, c.groups[0].standings[0].team_name]), [['P12', 3, 'Demoklubben P12']]);
await call(host, 'select api.set_tournament_class_schedule_published($1,false)', [p12]);
assert.deepEqual((await publicView(cup)).schedule, [], 'an unpublished schedule stays hidden');
await fails(coach, 'select api.get_public_tournament($1)', [cup], /permission denied/);

console.log('tournament teamzone: ok');
