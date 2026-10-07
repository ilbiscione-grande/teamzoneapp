// The real KPI and follow-up migration in isolated Postgres. Events,
// callups, attendance and match tables are minimal fixtures; capabilities
// are controlled per actor.
// node supabase/tests/event_kpis_followup.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const leader = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', player = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', recorder = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const club = '10000000-0000-4000-8000-000000000001', team = '20000000-0000-4000-8000-000000000001';
const id = n => `30000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const person = n => `40000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
try {
  await db.exec(`create role anon;create role authenticated;
  create schema internal;create schema api;create schema core;create schema auth;create schema audit;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table core.profiles(id uuid primary key);
  insert into core.profiles values('${leader}'),('${player}'),('${recorder}');
  create table core.teams(id uuid primary key,club_id uuid,sport text);
  insert into core.teams values('${team}','${club}','football');
  create table core.events(id uuid primary key,club_id uuid,owning_team_id uuid,event_type text,state text,
   starts_at timestamptz,ends_at timestamptz,archived_at timestamptz,unique(id,club_id));
  create table core.callups(id uuid primary key default gen_random_uuid(),event_id uuid,club_person_id uuid,state text);
  create table core.callup_responses(callup_id uuid,revision bigint,decline_reason_code text);
  create table core.attendance_facts(event_id uuid,club_person_id uuid,status text,minutes integer);
  create table core.match_workspaces(event_id uuid primary key,state text);
  create table core.match_projections(event_id uuid primary key,score_us integer,score_opponent integer);
  create table core.match_reports(event_id uuid primary key,body text);
  create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,aggregate_id uuid,aggregate_revision bigint,metadata jsonb);
  -- Leader plans and records, the recorder only registers attendance, the player only reads.
  create function internal.actor_can_read_event(uuid) returns boolean language sql stable as $$select auth.uid() is not null$$;
  create function internal.actor_is_event_leader(uuid) returns boolean language sql stable as $$select auth.uid() in('${leader}','${recorder}')$$;
  create function internal.actor_has_event_capability(uuid,cap text) returns boolean language sql stable as $$
   select case when auth.uid()='${leader}' then true when auth.uid()='${recorder}' then cap='event.attendance.manage' else false end$$;`);
  await db.exec(read('supabase/migrations/20261008090000_event_kpis_followup.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec('begin');

  // Five past matches and the current one, a week apart, plus a future training.
  for (let n = 1; n <= 6; n++) {
    await db.query(`insert into core.events values($1,$2,$3,'match','completed',now()-($4||' days')::interval,now()-($4||' days')::interval+interval '2 hours',null)`,
      [id(n), club, team, String((7 - n) * 7)]);
  }
  await db.query(`insert into core.events values($1,$2,$3,'training','scheduled',now()+interval '2 days',now()+interval '2 days 90 minutes',null)`, [id(9), club, team]);
  // Current match (6): 10 called, 7 accepted, 2 declined, 1 unanswered.
  for (let p = 1; p <= 10; p++) {
    const state = p <= 7 ? 'accepted' : p <= 9 ? 'declined' : 'pending';
    const callup = await one('insert into core.callups(event_id,club_person_id,state) values($1,$2,$3) returning id', [id(6), person(p), state]);
    if (state === 'declined') await db.query('insert into core.callup_responses values($1,1,$2)', [callup, p === 8 ? 'illness' : 'injury']);
    if (p <= 5) await db.query("insert into core.attendance_facts values($1,$2,'present',null)", [id(6), person(p)]);
    if (p === 6) await db.query("insert into core.attendance_facts values($1,$2,'late',10)", [id(6), person(p)]);
    if (p >= 8 && p <= 9) await db.query("insert into core.attendance_facts values($1,$2,'absent',null)", [id(6), person(p)]);
  }
  // Earlier matches: everyone of 5 called present, so a trend exists.
  for (let n = 1; n <= 5; n++) for (let p = 1; p <= 5; p++) {
    await db.query("insert into core.callups(event_id,club_person_id,state) values($1,$2,'accepted')", [id(n), person(p)]);
    await db.query(`insert into core.attendance_facts values($1,$2,$3,null)`, [id(n), person(p), p <= 3 + (n % 2) ? 'present' : 'absent']);
  }

  await as(leader);
  const catalog = await one('select api.get_event_kpi_catalog($1)', [id(6)]);
  const keys = catalog.map(item => item.key);
  assert.ok(keys.includes('corners') && keys.includes('clean_sheet'), 'football match KPIs');
  assert.ok(!keys.includes('save_rate') && !keys.includes('intensity'), 'no handball or training KPIs');
  assert.ok((await one('select api.get_event_kpi_catalog($1)', [id(9)])).some(item => item.key === 'intensity'));
  console.log('PASS: the catalog follows event type and team sport');

  const save = (key, comparator, target, extra = {}) => one('select api.save_event_kpi_target($1,$2,$3,$4,$5,$6,$7,$8,$9)',
    [id(6), extra.targetId ?? null, key, extra.label ?? null, extra.type ?? null, comparator, target, extra.visible ?? false, extra.revision ?? 0]);
  const attendance = await save('attendance_rate', 'gte', 90, { visible: true });
  assert.equal(attendance.label, 'Närvaro');
  assert.equal(attendance.source, 'auto');
  const goals = await save('goals_against', 'lte', 1);
  const shots = await save('shots_on_target', 'gte', 6, { visible: true });
  const custom = await save('custom', 'gte', 3, { label: 'Fasta situationer till avslut', type: 'count' });
  assert.equal(custom.direction, 'higher');
  assert.equal(custom.source, 'manual');
  await reject(() => save('custom', 'gte', 3, { label: 'fasta situationer till avslut', type: 'count' }), /duplicate key|unique/);
  await reject(() => save('save_rate', 'gte', 50), /invalid_kpi/);
  await reject(() => save('attendance_rate', 'gte', 150), /check constraint/);
  const edited = await save('shots_on_target', 'gte', 5, { targetId: shots.id, revision: shots.revision, visible: true });
  assert.equal(Number(edited.target), 5);
  await reject(() => save('shots_on_target', 'gte', 4, { targetId: shots.id, revision: shots.revision }), /stale_revision/);
  console.log('PASS: goals from the catalog and custom goals, validation, uniqueness and revisions');

  // Manual values: the recorder may enter them, the player may not; automatic ones are computed.
  await reject(() => one('select api.record_event_kpi_value($1,$2,$3)', [attendance.id, 50, attendance.revision]), /kpi_is_automatic/);
  await as(recorder);
  const recorded = await one('select api.record_event_kpi_value($1,$2,$3)', [shots.id, 7, edited.revision]);
  assert.equal(Number(recorded.actual), 7);
  assert.equal(recorded.status, 'achieved');
  await reject(() => save('corners', 'gte', 4), /not_found/);
  await as(player);
  await reject(() => one('select api.record_event_kpi_value($1,$2,$3)', [custom.id, 4, custom.revision]), /not_found/);
  console.log('PASS: manual values by leaders and attendance registrars only; automatic values cannot be overwritten');

  await as(leader);
  let followup = await one('select api.get_event_followup($1)', [id(6)]);
  assert.deepEqual([followup.summary.called, followup.summary.accepted, followup.summary.declined, followup.summary.pending], [10, 7, 2, 1]);
  assert.deepEqual([followup.summary.present, followup.summary.late, followup.summary.absent, followup.summary.unregistered], [5, 1, 2, 2]);
  assert.equal(Number(followup.summary.attendance_rate), 60);
  assert.equal(Number(followup.summary.response_rate), 90);
  assert.equal(followup.summary.late_minutes_avg, 10);
  assert.deepEqual(followup.decline_reasons.map(r => r.code).sort(), ['illness', 'injury']);
  assert.equal(followup.attendance_trend.length, 6);
  assert.equal(followup.attendance_trend.at(-1).current, true);
  assert.ok(Number(followup.team_average_attendance) > 60);
  const byKey = Object.fromEntries(followup.kpis.map(k => [k.kpi_key, k]));
  assert.equal(byKey.attendance_rate.status, 'missed');
  assert.equal(byKey.goals_against.status, 'missing', 'no result yet');
  assert.equal(byKey.custom.status, 'missing');
  assert.deepEqual(followup.todos.map(t => t.kind), ['attendance', 'kpi_values', 'match_result', 'match_report']);
  assert.equal(followup.todos[0].count, 2);
  console.log('PASS: summary, decline reasons, trend, team average, KPI status and to-dos');

  // A completed match result fills goals; a report removes that to-do.
  await db.query("insert into core.match_workspaces values($1,'completed')", [id(6)]);
  await db.query('insert into core.match_projections values($1,3,1)', [id(6)]);
  await db.query("insert into core.match_reports values($1,'Bra match')", [id(6)]);
  followup = await one('select api.get_event_followup($1)', [id(6)]);
  const goalsKpi = followup.kpis.find(k => k.kpi_key === 'goals_against');
  assert.equal(Number(goalsKpi.actual), 1);
  assert.equal(goalsKpi.status, 'achieved');
  assert.deepEqual(followup.todos.map(t => t.kind), ['attendance', 'kpi_values']);
  // The KPI trend includes earlier matches with the same goal.
  await db.query(`insert into core.event_kpi_targets(club_id,event_id,kpi_key,label,value_type,direction,source,comparator,target,actual_value,created_by)
   values($1,$2,'shots_on_target','Skott på mål','count','higher','manual','gte',6,4,$3)`, [club, id(5), leader]);
  followup = await one('select api.get_event_followup($1)', [id(6)]);
  const shotTrend = followup.kpis.find(k => k.kpi_key === 'shots_on_target').trend;
  assert.deepEqual(shotTrend.map(p => [Number(p.actual), p.current]), [[4, false], [7, true]]);
  console.log('PASS: match result feeds goal KPIs and to-dos; KPI trends span earlier events');

  // Players see the team summary and visible goals only, without to-dos or reasons.
  await as(player);
  followup = await one('select api.get_event_followup($1)', [id(6)]);
  assert.deepEqual(followup.kpis.map(k => k.kpi_key).sort(), ['attendance_rate', 'shots_on_target']);
  assert.deepEqual(followup.todos, []);
  assert.deepEqual(followup.decline_reasons, []);
  assert.equal(followup.can_edit_targets, false);
  // A future event has pending, not missing, values and no to-dos.
  await as(leader);
  await one("select api.save_event_kpi_target($1,null,'intensity',null,null,'gte',4,false,0)", [id(9)]);
  followup = await one('select api.get_event_followup($1)', [id(9)]);
  assert.equal(followup.kpis[0].status, 'pending');
  assert.deepEqual(followup.todos, []);
  await one('select api.delete_event_kpi_target($1,$2)', [id(6), custom.id]);
  assert.equal(await one('select count(*)::int from core.event_kpi_targets where id=$1', [custom.id]), 0);
  await as(player);
  await reject(() => one('select api.delete_event_kpi_target($1,$2)', [id(6), shots.id]), /not_found/);
  assert.ok(await one("select count(*)::int from audit.command_events where command_type like 'event.kpi.%'") >= 6);
  console.log('PASS: player visibility, future events, deletion, refusal and audit');
} catch (error) {
  console.error(error.message, error.code ?? '', error.where ?? '');
  process.exitCode = 1;
} finally { await db.close(); }
