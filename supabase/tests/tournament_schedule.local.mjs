// Webtools Turneringsplanerare, part 2 (2026-10-21): groups, schedule,
// results, tables and play-offs. node supabase/tests/tournament_schedule.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const host = id(1), coach = id(2), helper = id(3);
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who ?? '']);
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
const call = async (who, sql, params = []) => { await as(who); return asRole('authenticated', async () => Object.values((await db.query(sql, params)).rows[0] ?? {})[0]); };
const fails = async (who, sql, params, pattern) => {
  await db.exec('savepoint s');
  // No finally: in an aborted transaction it would hide the real error.
  await assert.rejects(call(who, sql, params), pattern);
  await db.exec('rollback to s');
};
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
set check_function_bodies = off;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.profiles(id uuid primary key, display_name text);
insert into core.profiles values ('${host}','Hanna'),('${coach}','Coach'),('${helper}','Helga');
create table core.clubs(id uuid primary key, name text);
create table core.teams(id uuid primary key, club_id uuid, name text);
create function internal.booking_person_name(p uuid) returns text language sql stable as $$select display_name from core.profiles where id = p$$;
grant usage on schema api, internal, core, auth to authenticated;`);
await db.exec(read('supabase/migrations/20261119090000_tournament_planner.sql'));
await db.exec(read('supabase/migrations/20261120090000_tournament_schedule.sql'));
await db.exec('begin');

const cup = await call(host, "select api.create_tournament('Höstcupen','Fotboll',null,'2026-11-14','2026-11-15')");
const p12 = await call(host, "select api.save_tournament_class($1,null,'P12',null,'groups_playoff',null,null,15,1)", [cup]);
const knatte = await call(host, "select api.save_tournament_class($1,null,'Knatte',null,'pool',null,null,10,2)", [cup]);
await call(host, "select api.update_tournament($1,'Höstcupen',null,null,'2026-11-14','2026-11-15',null,null,null,'published',true,null)", [cup]);
const teams = {};
for (const name of ['Alfa', 'Beta', 'Cobra', 'Delta']) {
  const registration = await call(coach, "select api.register_tournament_team($1,$2,null,'Coach','coach@example.se',null,null)", [p12, name]);
  await call(host, 'select api.decide_tournament_registration($1,true)', [registration.id]);
  teams[name] = registration.id;
}
const kids = [];
for (const name of ['Knatte 1', 'Knatte 2']) {
  const registration = await call(coach, "select api.register_tournament_team($1,$2,null,'Coach','coach@example.se',null,null)", [knatte, name]);
  await call(host, 'select api.decide_tournament_registration($1,true)', [registration.id]);
  kids.push(registration.id);
}
const token = await call(host, "select api.create_tournament_staff_invitation($1,'official')", [cup]);
await call(helper, 'select api.accept_tournament_staff_invitation($1)', [token]);

// Pitches: one name each; the organiser only.
const pitch1 = await call(host, "select api.save_tournament_pitch($1,null,'Plan 1',1)", [cup]);
const pitch2 = await call(host, "select api.save_tournament_pitch($1,null,'Plan 2',2)", [cup]);
await fails(host, "select api.save_tournament_pitch($1,null,' plan 1 ',3)", [cup], /pitch_name_taken/);
await fails(helper, "select api.save_tournament_pitch($1,null,'Plan 3',3)", [cup], /not_organizer/);

// Groups and their matches, saved at once.
const at = (h, m = 0) => `2026-11-14T${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:00Z`;
const groups = [{ name: 'A', registration_ids: [teams.Alfa, teams.Beta] }, { name: 'B', registration_ids: [teams.Cobra, teams.Delta] }];
const groupMatches = [
  { group: 0, round: 1, home: teams.Alfa, away: teams.Beta, pitch_id: pitch1, starts_at: at(9), ends_at: at(9, 15) },
  { group: 1, round: 1, home: teams.Cobra, away: teams.Delta, pitch_id: pitch2, starts_at: at(9), ends_at: at(9, 15) },
];
await fails(host, "select api.save_tournament_class_schedule($1,'group',$2,$3)", [p12, JSON.stringify(groups),
  JSON.stringify([{ ...groupMatches[0], away: kids[0] }])], /invalid_schedule/);
await fails(host, "select api.save_tournament_class_schedule($1,'group',$2,$3)", [p12,
  JSON.stringify([{ name: 'A', registration_ids: [kids[0]] }]), '[]'], /team_not_approved/);
assert.equal(await call(host, "select api.save_tournament_class_schedule($1,'group',$2,$3)", [p12, JSON.stringify(groups), JSON.stringify(groupMatches)]), 2);
// Semifinals cross the groups; the final and bronze follow from them.
const playoff = [
  { round: 1, label: 'Semifinal 1', home_source: { kind: 'group_place', group: 0, place: 1 }, away_source: { kind: 'group_place', group: 1, place: 2 }, pitch_id: pitch1, starts_at: at(10), ends_at: at(10, 15) },
  { round: 1, label: 'Semifinal 2', home_source: { kind: 'group_place', group: 1, place: 1 }, away_source: { kind: 'group_place', group: 0, place: 2 }, pitch_id: pitch2, starts_at: at(10), ends_at: at(10, 15) },
  { round: 2, label: 'Final', home_source: { kind: 'winner', match: 0 }, away_source: { kind: 'winner', match: 1 }, pitch_id: pitch1, starts_at: at(11), ends_at: at(11, 15) },
  { round: 2, label: 'Bronsmatch', home_source: { kind: 'loser', match: 0 }, away_source: { kind: 'loser', match: 1 }, pitch_id: pitch2, starts_at: at(11), ends_at: at(11, 15) },
];
await fails(host, "select api.save_tournament_class_schedule($1,'playoff',null,$2)", [p12,
  JSON.stringify([{ ...playoff[2], home_source: { kind: 'winner', match: 0 } }])], /invalid_schedule/);
assert.equal(await call(host, "select api.save_tournament_class_schedule($1,'playoff',null,$2)", [p12, JSON.stringify(playoff)]), 4);
await fails(host, "select api.save_tournament_class_schedule($1,'playoff',null,'[]')", [knatte], /no_playoff_in_pool/);
await call(host, "select api.save_tournament_class_schedule($1,'group',$2,$3)", [knatte,
  JSON.stringify([{ name: 'Pool 1', registration_ids: kids }]),
  JSON.stringify([{ group: 0, round: 1, home: kids[0], away: kids[1], pitch_id: pitch1, starts_at: at(12), ends_at: at(12, 10) }])]);

// Unpublished: the team sees no classes; staff see them all.
const schedule = who => call(who, 'select api.get_tournament_schedule($1)', [cup]);
assert.deepEqual((await schedule(coach)).classes, []);
assert.deepEqual((await schedule(helper)).classes.map(c => c.name), ['P12', 'Knatte']);
await call(host, 'select api.set_tournament_class_schedule_published($1,true)', [p12]);
let view = (await schedule(coach)).classes;
assert.deepEqual(view.map(c => c.name), ['P12']);
const matchNamed = label => view[0].matches.find(m => m.label === label);
assert.deepEqual([matchNamed('Semifinal 1').home_name, matchNamed('Final').away_name, matchNamed('Bronsmatch').home_name],
  ['1:a grupp A', 'Vinnare Semifinal 2', 'Förlorare Semifinal 1']);
assert.deepEqual((await schedule(coach)).pitches.map(p => p.name), ['Plan 1', 'Plan 2']);

// Results: staff report; teams cannot; pools and unknown teams have none.
const groupMatch = (await schedule(host)).classes[0].matches.filter(m => m.stage === 'group');
const [aMatch, bMatch] = groupMatch;
const report = (who, matchId, h, a, hp = null, ap = null) => call(who, 'select api.report_tournament_match_result($1,$2,$3,$4,$5)', [matchId, h, a, hp, ap]);
await fails(coach, 'select api.report_tournament_match_result($1,1,0,null,null)', [aMatch.id], /not_found/);
await fails(helper, 'select api.report_tournament_match_result($1,1,0,null,null)', [matchNamed('Final').id], /teams_not_known/);
const poolMatch = (await schedule(host)).classes[1].matches[0];
await fails(helper, 'select api.report_tournament_match_result($1,1,0,null,null)', [poolMatch.id], /no_results_in_pool/);
await fails(helper, 'select api.report_tournament_match_result($1,1,null,null,null)', [aMatch.id], /invalid_result/);
assert.equal((await report(helper, aMatch.id, 2, 0)).status, 'played');
// Group A is done: its places are known, group B's not yet.
view = (await schedule(coach)).classes;
assert.deepEqual([matchNamed('Semifinal 1').home_name, matchNamed('Semifinal 1').away_name, matchNamed('Semifinal 2').away_name],
  ['Alfa', '2:a grupp B', 'Beta']);
await report(host, bMatch.id, 1, 1);
view = (await schedule(coach)).classes;
const tableB = view[0].groups[1].standings;
assert.deepEqual(tableB.map(r => [r.team_name, r.points, r.played]), [['Cobra', 1, 1], ['Delta', 1, 1]], 'level teams by name');
assert.deepEqual(view[0].groups[0].standings.map(r => [r.team_name, r.points, r.goals_for, r.goals_against, r.won, r.lost]),
  [['Alfa', 3, 2, 0, 1, 0], ['Beta', 0, 0, 2, 0, 1]]);
assert.deepEqual([matchNamed('Semifinal 1').away_name, matchNamed('Semifinal 2').home_name], ['Delta', 'Cobra']);

// Play-off: a level score needs penalties; winners and losers go on.
await fails(host, 'select api.report_tournament_match_result($1,1,1,null,null)', [matchNamed('Semifinal 1').id], /needs_winner/);
await report(host, matchNamed('Semifinal 1').id, 1, 1, 4, 3);
await report(host, matchNamed('Semifinal 2').id, 0, 2);
view = (await schedule(coach)).classes;
assert.deepEqual([matchNamed('Final').home_name, matchNamed('Final').away_name, matchNamed('Bronsmatch').home_name, matchNamed('Bronsmatch').away_name],
  ['Alfa', 'Beta', 'Delta', 'Cobra']);
await report(host, matchNamed('Final').id, 3, 1);
// What later matches were built on stays; the schedule with results stays.
await fails(host, 'select api.report_tournament_match_result($1,0,1,null,null)', [matchNamed('Semifinal 1').id], /later_match_played/);
await fails(host, 'select api.report_tournament_match_result($1,0,1,null,null)', [aMatch.id], /later_match_played/);
await fails(host, "select api.save_tournament_class_schedule($1,'group',$2,$3)", [p12, JSON.stringify(groups), JSON.stringify(groupMatches)], /has_results/);
await fails(host, "select api.save_tournament_class_schedule($1,'playoff',null,$2)", [p12, JSON.stringify(playoff)], /has_results/);
await fails(coach, 'select api.withdraw_tournament_registration($1)', [teams.Delta], /team_in_schedule/);
// Clearing the bronze result is fine; it has nothing after it.
await report(host, matchNamed('Bronsmatch').id, 2, 0);
assert.equal((await report(host, matchNamed('Bronsmatch').id, null, null)).status, 'scheduled');

// Moving a match; a pitch with matches stays.
await call(host, 'select api.set_tournament_match_time($1,$2,$3,$4)', [poolMatch.id, pitch2, at(13), at(13, 10)]);
assert.equal((await schedule(host)).classes[1].matches[0].pitch_id, pitch2);
await fails(host, 'select api.set_tournament_match_time($1,null,$2,$3)', [poolMatch.id, at(13), at(12)], /invalid_time/);
await fails(helper, 'select api.set_tournament_match_time($1,null,null,null)', [poolMatch.id], /not_organizer/);
await fails(host, 'select api.delete_tournament_pitch($1)', [pitch1], /pitch_in_use/);
const spare = await call(host, "select api.save_tournament_pitch($1,null,'Plan 3',3)", [cup]);
await call(host, 'select api.delete_tournament_pitch($1)', [spare]);

console.log('tournament schedule: ok');
