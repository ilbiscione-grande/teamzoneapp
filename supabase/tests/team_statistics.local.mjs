// The real team statistics migration in isolated Postgres. Teams, events,
// assignments, callups and attendance are minimal fixtures; capabilities are
// controlled per actor.
// node supabase/tests/team_statistics.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const leader = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', player = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const club = '10000000-0000-4000-8000-000000000001', team = '20000000-0000-4000-8000-000000000001', other = '20000000-0000-4000-8000-000000000002';
const ev = n => `30000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const person = n => `40000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const stats = async (from = "now()-interval '90 days'", to = 'now()') =>
  Object.values((await db.query(`select api.get_team_statistics($1,${from},${to}) as s`, [team])).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
try {
  await db.exec(`create role anon;create role authenticated;
  create schema internal;create schema api;create schema core;create schema auth;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table core.clubs(id uuid primary key,default_timezone text);
  insert into core.clubs values('${club}','Europe/Stockholm');
  create table core.teams(id uuid primary key,club_id uuid);
  insert into core.teams values('${team}','${club}'),('${other}','${club}');
  create table core.club_people(id uuid primary key,club_id uuid,display_name text,status text);
  create table core.assignments(club_id uuid,team_id uuid,club_person_id uuid,role_package text,state text);
  create table core.events(id uuid primary key,club_id uuid,event_type text,state text,starts_at timestamptz);
  create table core.event_teams(event_id uuid,club_id uuid,team_id uuid);
  create table core.callups(event_id uuid,club_person_id uuid,club_id uuid,state text);
  create table core.attendance_facts(event_id uuid,club_person_id uuid,club_id uuid,status text);
  -- Only the leader manages the team.
  create function internal.actor_has_capability(uuid,uuid,cap text) returns boolean language sql stable as $$
   select auth.uid()='${leader}' and cap in('event.attendance.manage','event.manage','team.roster.manage')$$;
  create function internal.attendance_is_expected(target_event_id uuid,target_person_id uuid) returns boolean language sql stable as $$
   select exists(select 1 from core.callups c where c.event_id=target_event_id and c.club_person_id=target_person_id and c.state<>'cancelled')
    or not exists(select 1 from core.callups c where c.event_id=target_event_id and c.state<>'cancelled')$$;`);
  await db.exec(read('supabase/migrations/20261016090000_team_statistics.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec('begin');

  // Players 1-3, leader 9, player 7 in another team only, ended person 8.
  for (const [n, name, role, t, status] of [
    [1, 'Anna', 'player', team, 'active'], [2, 'Bo', 'player', team, 'active'], [3, 'Cia', 'player', team, 'active'],
    [9, 'Ledare Lisa', 'leader', team, 'active'], [7, 'Annat Lag', 'player', other, 'active'], [8, 'Slutat', 'player', team, 'ended'],
  ]) {
    await db.query('insert into core.club_people values($1,$2,$3,$4)', [person(n), club, name, status]);
    await db.query("insert into core.assignments values($1,$2,$3,$4,'active')", [club, t, person(n), role]);
  }
  const event = async (n, type, daysAgo, state = 'completed', teamId = team) => {
    await db.query(`insert into core.events values($1,$2,$3,$4,now()-($5||' days')::interval)`, [ev(n), club, type, state, String(daysAgo)]);
    await db.query('insert into core.event_teams values($1,$2,$3)', [ev(n), club, teamId]);
  };
  const fact = (n, p, status) => db.query('insert into core.attendance_facts values($1,$2,$3,$4)', [ev(n), person(p), club, status]);
  const call = (n, p, state) => db.query('insert into core.callups values($1,$2,$3,$4)', [ev(n), person(p), club, state]);

  // Training 1 (no callups): Anna present, Bo absent (counts), Cia unknown.
  await event(1, 'training', 10);
  await fact(1, 1, 'present'); await fact(1, 2, 'absent'); await fact(1, 3, 'unknown'); await fact(1, 9, 'present');
  // Match 2 with callups: Anna and Bo called; Cia absent but not called (does not count).
  await event(2, 'match', 5);
  await call(2, 1, 'accepted'); await call(2, 2, 'pending');
  await fact(2, 1, 'late'); await fact(2, 2, 'absent'); await fact(2, 3, 'absent');
  // Training 3: Cia partial (counts as attended).
  await event(3, 'training', 3);
  await fact(3, 3, 'partial');
  // Excluded: cancelled, future, another team's event, outside the period.
  await event(4, 'training', 2, 'cancelled'); await fact(4, 1, 'absent');
  await event(5, 'training', -2, 'scheduled'); await fact(5, 1, 'absent');
  await event(6, 'training', 2, 'completed', other); await fact(6, 1, 'absent');
  await event(10, 'match', 200); await fact(10, 1, 'absent');
  // A meeting counts as "other".
  await event(11, 'meeting', 1);

  await as(player);
  await reject(() => stats(), /not_found/);
  await as(leader);
  await reject(() => stats("now()", "now()-interval '1 day'"), /invalid_period/);
  await reject(() => stats("now()-interval '500 days'", 'now()'), /invalid_period/);

  const s = await stats();
  assert.deepEqual(s.events, { total: 4, training: 2, match: 1, other: 1 });
  // Players only: counted = Anna 2 (present, late), Bo 2 (absent, absent), Cia 1 (partial).
  // Attended 3 of 5.
  assert.equal(Number(s.attendance_rate), 60);
  // Trainings: Anna present, Bo absent, Cia partial -> 2/3.
  assert.equal(Number(s.training_rate), 66.7);
  // Match: Anna late, Bo absent (called), Cia not called -> 1/2.
  assert.equal(Number(s.match_rate), 50);
  // Callups: 2 sent, 1 answered.
  assert.equal(Number(s.response_rate), 50);
  assert.equal(s.late, 1);
  assert.ok(s.months.length >= 1 && s.months.every(m => /^\d{4}-\d{2}$/.test(m.month)));

  const people = Object.fromEntries(s.people.map(p => [p.name, p]));
  assert.deepEqual(Object.keys(people).sort(), ['Anna', 'Bo', 'Cia', 'Ledare Lisa'], 'ended people and other teams are not listed');
  assert.equal(s.people[0].role, 'player', 'players first');
  assert.equal(people.Anna.attended, 2); assert.equal(people.Anna.counted, 2); assert.equal(people.Anna.late, 1);
  assert.equal(people.Anna.trainings_attended, 1); assert.equal(people.Anna.matches_attended, 1);
  assert.equal(people.Bo.attended, 0); assert.equal(people.Bo.counted, 2);
  assert.equal(people.Bo.callups, 1); assert.equal(people.Bo.answered, 0);
  assert.equal(people.Cia.counted, 1, 'unknown and uncalled absence are not counted');
  assert.equal(people['Ledare Lisa'].role, 'leader');
  assert.equal(people['Ledare Lisa'].attended, 1);

  // A short window only sees the latest training.
  const recent = await stats("now()-interval '4 days'", 'now()');
  assert.deepEqual(recent.events, { total: 2, training: 1, match: 0, other: 1 });
  assert.equal(Number(recent.attendance_rate), 100);
  assert.equal(recent.match_rate, null);

  await db.exec('rollback');
  console.log('team statistics: ok');
} finally {
  await db.close();
}
