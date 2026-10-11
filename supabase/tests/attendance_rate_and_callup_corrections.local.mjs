// The real attendance-rate and callup-correction migration in isolated
// Postgres, on top of the team statistics migration. Minimal fixtures.
// node supabase/tests/attendance_rate_and_callup_corrections.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const leader = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', player = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const club = '10000000-0000-4000-8000-000000000001', team = '20000000-0000-4000-8000-000000000001';
const ev = n => `30000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const person = n => `40000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const rev = n => `50000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
const correct = (event, p, state, code = null, text = null, revision = 0) =>
  one('select api.correct_callup($1,$2,$3,$4,$5,$6)', [event, p, state, code, text, revision]);
try {
  await db.exec(`create role anon;create role authenticated;
  create schema internal;create schema api;create schema core;create schema auth;create schema audit;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table audit.command_events(club_id uuid,actor_profile_id uuid,acting_as_person_id uuid,command_type text,
   aggregate_type text,aggregate_id uuid,aggregate_revision bigint,metadata jsonb);
  create table core.clubs(id uuid primary key,default_timezone text);
  insert into core.clubs values('${club}','Europe/Stockholm');
  create table core.teams(id uuid primary key,club_id uuid);
  insert into core.teams values('${team}','${club}');
  create table core.club_people(id uuid primary key,club_id uuid,display_name text,status text);
  create table core.assignments(club_id uuid,team_id uuid,club_person_id uuid,role_package text,state text);
  create table core.events(id uuid primary key,club_id uuid,owning_team_id uuid,event_type text,state text,
   starts_at timestamptz,ends_at timestamptz,archived_at timestamptz);
  create table core.event_teams(event_id uuid,club_id uuid,team_id uuid);
  create table core.squad_revisions(id uuid primary key,event_id uuid,state text,revision bigint);
  create table core.squad_members(club_id uuid,event_id uuid,squad_revision_id uuid,club_person_id uuid,
   selection_state text,source text,eligibility_snapshot jsonb not null,created_by uuid,unique(squad_revision_id,club_person_id));
  create table core.callups(id uuid primary key default gen_random_uuid(),club_id uuid,event_id uuid,squad_revision_id uuid,
   club_person_id uuid,state text,sent_at timestamptz,cancelled_at timestamptz,created_by uuid,revision bigint not null default 1);
  create table core.callup_responses(club_id uuid,callup_id uuid,response text,decline_reason_code text,decline_reason_text text,
   actor_profile_id uuid,acting_as_person_id uuid,revision bigint,unique(callup_id,revision));
  create table core.attendance_facts(event_id uuid,club_person_id uuid,club_id uuid,status text,minutes integer);
  create function internal.actor_has_capability(uuid,uuid,cap text) returns boolean language sql stable as $$select auth.uid()='${leader}'$$;
  create function internal.actor_can_manage_squad(uuid) returns boolean language sql stable as $$select auth.uid()='${leader}'$$;
  create function internal.person_eligibility_at_event(uuid,uuid) returns jsonb language sql stable as $$select jsonb_build_object('kind','team_assignment')$$;
  create function internal.attendance_is_expected(target_event_id uuid,target_person_id uuid) returns boolean language sql stable as $$
   select exists(select 1 from core.callups c where c.event_id=target_event_id and c.club_person_id=target_person_id and c.state<>'cancelled')
    or not exists(select 1 from core.callups c where c.event_id=target_event_id and c.state<>'cancelled')$$;`);
  await db.exec(read('supabase/migrations/20261016090000_team_statistics.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec(read('supabase/migrations/20261017090000_attendance_rate_expected_and_callup_corrections.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec('begin');

  for (const [n, name] of [[1, 'Anna'], [2, 'Bo'], [3, 'Cia']]) {
    await db.query("insert into core.club_people values($1,$2,$3,'active')", [person(n), club, name]);
    await db.query("insert into core.assignments values($1,$2,$3,'player','active')", [club, team, person(n)]);
  }
  const event = async (n, type, daysAgo) => {
    await db.query(`insert into core.events values($1,$2,$3,$4,'completed',now()-($5||' days')::interval,now()-($5||' days')::interval+interval '1 hour',null)`,
      [ev(n), club, team, type, String(daysAgo)]);
    await db.query('insert into core.event_teams values($1,$2,$3)', [ev(n), club, team]);
  };
  const fact = (n, p, status) => db.query('insert into core.attendance_facts values($1,$2,$3,$4,null)', [ev(n), person(p), club, status]);

  // Match 1 with callups: Anna called + present, Bo called + absent, Cia NOT called but present (walk-in).
  await event(1, 'match', 5);
  await db.query("insert into core.squad_revisions values($1,$2,'sent',1)", [rev(1), ev(1)]);
  for (const [p, state] of [[1, 'accepted'], [2, 'pending']]) {
    await db.query("insert into core.callups(club_id,event_id,squad_revision_id,club_person_id,state,sent_at) values($1,$2,$3,$4,$5,now())",
      [club, ev(1), rev(1), person(p), state]);
  }
  await fact(1, 1, 'present'); await fact(1, 2, 'absent'); await fact(1, 3, 'present');
  // Training 2 without callups: everyone expected.
  await event(2, 'training', 3);
  await fact(2, 1, 'present'); await fact(2, 2, 'present'); await fact(2, 3, 'absent');

  // 1. Event summary: the walk-in no longer inflates the rate.
  const summary = await one('select internal.event_attendance_summary($1)', [ev(1)]);
  assert.equal(summary.present, 1, 'only expected people in the present count');
  assert.equal(summary.extra, 1, 'walk-in reported separately');
  assert.equal(summary.registered, 2);
  assert.equal(Number(summary.attendance_rate), 50, 'Anna 1 of 2 expected, not 2 of 3');
  const trainingSummary = await one('select internal.event_attendance_summary($1)', [ev(2)]);
  assert.equal(trainingSummary.extra, 0);
  assert.equal(Number(trainingSummary.attendance_rate), 66.7);

  // 2. Team statistics with the same rule.
  await as(leader);
  const stats = await one("select api.get_team_statistics($1,now()-interval '30 days',now())", [team]);
  // Expected: match Anna ✓ Bo ✗; training Anna ✓ Bo ✓ Cia ✗ -> 3 of 5.
  assert.equal(Number(stats.attendance_rate), 60);
  assert.equal(stats.extra, 1);
  const cia = stats.people.find(p => p.name === 'Cia');
  assert.equal(cia.counted, 1); assert.equal(cia.attended, 0); assert.equal(cia.extra, 1);

  // 3. Callup corrections.
  await as(player);
  await reject(() => correct(ev(1), person(3), 'accepted'), /not_found/);
  await as(leader);
  await reject(() => correct(ev(1), person(3), 'maybe'), /invalid_state/);
  await reject(() => correct(ev(1), person(3), 'declined', 'weather'), /invalid_decline_reason/);
  await reject(() => correct(ev(1), person(3), 'accepted', null, null, 5), /stale_revision/);
  // Training 2 used no callups: a single late callup would make everyone else "not called".
  await reject(() => correct(ev(2), person(1), 'accepted'), /event_without_callups/);

  // Cia was forgotten: add her callup after the fact.
  const added = await correct(ev(1), person(3), 'accepted');
  assert.deepEqual(added, { revision: 1, state: 'accepted' });
  assert.equal(await one('select count(*)::int from core.squad_members where club_person_id=$1', [person(3)]), 1);
  assert.equal(await one("select response from core.callup_responses r join core.callups c on c.id=r.callup_id where c.club_person_id=$1", [person(3)]), 'accepted');
  const afterAdd = await one('select internal.event_attendance_summary($1)', [ev(1)]);
  assert.equal(afterAdd.extra, 0);
  assert.equal(Number(afterAdd.attendance_rate), 66.7, 'Cia now counts: 2 of 3');

  // Bo's answer corrected to declined with a reason.
  const declined = await correct(ev(1), person(2), 'declined', 'illness', null, 1);
  assert.equal(declined.revision, 2);
  assert.equal(await one("select state from core.callups where club_person_id=$1 and event_id=$2", [person(2), ev(1)]), 'declined');
  await correct(ev(1), person(2), 'pending', null, null, 2);
  assert.equal(await one("select response from core.callup_responses where revision=3"), 'tentative');

  // Remove Cia's callup again: she is a walk-in once more.
  assert.deepEqual(await correct(ev(1), person(3), 'none', null, null, 1), { revision: 0, state: 'none' });
  assert.equal(await one("select state from core.callups where club_person_id=$1", [person(3)]), 'cancelled');
  assert.equal((await one('select internal.event_attendance_summary($1)', [ev(1)])).extra, 1);
  assert.ok(await one("select count(*)::int from audit.command_events where command_type='callup.corrected'") >= 4);

  await db.exec('rollback');
  console.log('attendance rate and callup corrections: ok');
} finally {
  await db.close();
}
