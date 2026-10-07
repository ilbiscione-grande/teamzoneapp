// The real KPI counter migration in isolated Postgres, on top of the real
// KPI migration. The Match Space helpers (workspace guard, command registry,
// finish) are minimal stand-ins with the same contract.
// node supabase/tests/match_kpi_counters.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const leader = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', player = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const club = '10000000-0000-4000-8000-000000000001', team = '20000000-0000-4000-8000-000000000001';
const match = '30000000-0000-4000-8000-000000000001';
const cmd = n => `50000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
try {
  await db.exec(`create role anon;create role authenticated;
  create schema internal;create schema api;create schema core;create schema auth;create schema audit;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table core.profiles(id uuid primary key);
  insert into core.profiles values('${leader}'),('${player}');
  create table core.teams(id uuid primary key,club_id uuid,sport text);
  insert into core.teams values('${team}','${club}','football');
  create table core.events(id uuid primary key,club_id uuid,owning_team_id uuid,event_type text,state text,
   starts_at timestamptz,ends_at timestamptz,archived_at timestamptz,unique(id,club_id));
  create table core.callups(id uuid primary key default gen_random_uuid(),event_id uuid,club_person_id uuid,state text);
  create table core.callup_responses(callup_id uuid,revision bigint,decline_reason_code text);
  create table core.attendance_facts(event_id uuid,club_person_id uuid,status text,minutes integer);
  create table core.match_workspaces(event_id uuid primary key,club_id uuid,state text,revision bigint default 0);
  create table core.match_projections(event_id uuid primary key,score_us integer,score_opponent integer);
  create table core.match_reports(event_id uuid primary key,body text);
  create table core.match_facts(id uuid primary key,event_id uuid,minute integer,fact_type text,side text,club_id uuid,detail jsonb,
   state text default 'active',voided_at timestamptz,voided_by uuid,void_reason text,fact_revision integer default 1,
   source_command_id uuid,created_by uuid,updated_by uuid,created_at timestamptz default clock_timestamp(),updated_at timestamptz);
  create table audit.match_fact_versions(fact_id uuid,event_id uuid,fact_revision integer,snapshot jsonb,action text,actor_profile_id uuid,reason text);
  create table audit.match_commands(command_id uuid primary key,event_id uuid,command_type text,payload jsonb,actor_profile_id uuid,result jsonb);
  create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,aggregate_id uuid,aggregate_revision bigint,metadata jsonb);
  create function internal.actor_can_read_event(uuid) returns boolean language sql stable as $$select auth.uid() is not null$$;
  create function internal.actor_is_event_leader(uuid) returns boolean language sql stable as $$select auth.uid()='${leader}'$$;
  create function internal.actor_has_event_capability(uuid,text) returns boolean language sql stable as $$select auth.uid()='${leader}'$$;
  create function internal.ensure_match_workspace(p uuid) returns void language plpgsql as $$begin
   if auth.uid() is distinct from '${leader}'::uuid then raise insufficient_privilege using message='not_found'; end if;end$$;
  create function internal.register_match_command(p_command_id uuid,p_event_id uuid,p_expected bigint,p_type text,p_payload jsonb)
   returns boolean language plpgsql as $$declare n integer; existing audit.match_commands%rowtype;begin
   perform internal.ensure_match_workspace(p_event_id);
   insert into audit.match_commands values(p_command_id,p_event_id,p_type,p_payload,auth.uid(),null) on conflict do nothing;
   get diagnostics n=row_count; if n=1 then return true; end if;
   select * into existing from audit.match_commands where command_id=p_command_id;
   if existing.payload is distinct from p_payload then raise unique_violation using message='command_id_reused'; end if;
   return false;end$$;
  create function internal.finish_match_command(p_command_id uuid,p_event_id uuid,p_result jsonb) returns jsonb language plpgsql as $$begin
   update core.match_workspaces set revision=revision+1 where event_id=p_event_id;
   update audit.match_commands set result=p_result where command_id=p_command_id; return p_result;end$$;`);
  await db.exec(read('supabase/migrations/20261008090000_event_kpis_followup.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec(read('supabase/migrations/20261009090000_match_kpi_counters.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec('begin');
  await db.query(`insert into core.events values($1,$2,$3,'match','scheduled',now()-interval '30 minutes',now()+interval '90 minutes',null)`, [match, club, team]);
  await db.query("insert into core.match_workspaces values($1,$2,'planning')", [match, club]);

  await as(leader);
  const save = (key, comparator, target, extra = {}) => one('select api.save_event_kpi_target($1,null,$2,$3,$4,$5,$6,false,0)',
    [match, key, extra.label ?? null, extra.type ?? null, comparator, target]);
  const shots = await save('shots_on_target', 'gte', 3);
  const corners = await save('corners', 'gte', 4);
  const faults = await save('custom', 'lte', 2, { label: 'Tappade bollar egen planhalva', type: 'count' });
  const half = await save('everyone_played_half', 'eq', 1);
  const goalsFor = await save('goals_for', 'gte', 2);
  const tick = (n, target, delta = 1, minute = 10) => one('select api.record_match_kpi_v2($1,$2,$3,$4,$5)', [cmd(n), match, target, delta, minute]);

  await reject(() => tick(1, shots.id), /match_not_live/);
  await db.query("update core.match_workspaces set state='live'");
  await reject(() => tick(1, half.id), /invalid_kpi/);
  await reject(() => tick(1, goalsFor.id), /invalid_kpi/);
  await reject(() => tick(1, shots.id, 2), /invalid_fact/);
  await reject(() => tick(1, shots.id, -1), /invalid_fact/);
  console.log('PASS: only counted manual goals in a live match can be ticked');

  let result = await tick(1, shots.id);
  assert.equal(result.value, 1);
  // A retried command returns the same receipt and does not tick twice.
  assert.deepEqual(await tick(1, shots.id), result);
  await reject(() => tick(1, corners.id), /command_id_reused/);
  await tick(2, shots.id, 1, 20);
  await tick(3, shots.id, 1, 30);
  result = await tick(4, shots.id, -1, 31);
  assert.equal(result.value, 2);
  assert.equal(await one("select count(*)::int from core.match_facts where fact_type='kpi' and state='active'"), 2);
  assert.equal(await one("select minute from core.match_facts where fact_type='kpi' and state='voided'"), 30, 'minus voids the latest tick');
  // Untouched counters became zero once counters were in use; other types did not.
  const values = Object.fromEntries((await db.query('select kpi_key,actual_value from core.event_kpi_targets')).rows.map(r => [r.kpi_key, r.actual_value === null ? null : Number(r.actual_value)]));
  assert.deepEqual(values, { shots_on_target: 2, corners: 0, custom: 0, everyone_played_half: null, goals_for: null });
  assert.equal(await one('select count(*)::int from audit.match_fact_versions'), 4);
  console.log('PASS: ticks are idempotent, minus voids the latest, untouched counters become zero');

  await db.query("update core.events set ends_at=now()-interval '1 minute'");
  const followup = await one('select api.get_event_followup($1)', [match]);
  const byKey = Object.fromEntries(followup.kpis.map(k => [k.kpi_key, k]));
  assert.equal(byKey.shots_on_target.status, 'missed');
  assert.equal(byKey.custom.status, 'achieved', 'zero lost balls meets "at most 2"');
  // A counted value can still be corrected afterwards.
  const corrected = await one('select api.record_event_kpi_value($1,$2,$3)', [shots.id, 3, byKey.shots_on_target.revision]);
  assert.equal(corrected.status, 'achieved');
  console.log('PASS: counted values feed the follow-up and can be corrected afterwards');

  await as(player);
  await reject(() => tick(9, corners.id), /not_found/);
  void faults;
  console.log('PASS: only match managers can tick');
  await db.exec('rollback');
} finally {
  await db.close();
}
