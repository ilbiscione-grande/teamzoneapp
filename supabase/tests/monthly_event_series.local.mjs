// The real monthly-series migration in isolated Postgres, with loose stub
// tables for everything create_event_for_actor writes besides events.
// node supabase/tests/monthly_event_series.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const leader = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const club = '10000000-0000-4000-8000-000000000001', team = '20000000-0000-4000-8000-000000000001';
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const create = (frequency, interval, count, startsAt, key) => one(
  `select internal.create_event_for_actor($1,$2,'Träning',null,'training','scheduled',$3::timestamptz,
    $3::timestamptz+interval '90 minutes',false,'Europe/Stockholm',array['players'],null,$4,$5,$6,$7)`,
  [club, team, startsAt, frequency, interval, count, key]);
const localStarts = async first => (await db.query(
  `select to_char(starts_at at time zone 'Europe/Stockholm','YYYY-MM-DD HH24:MI') s from core.events
   where recurrence_id=(select recurrence_id from core.events where id=$1) order by occurrence_number`, [first])).rows.map(r => r.s);
try {
  await db.exec(`create role anon;create role authenticated;
  create schema internal;create schema core;create schema auth;create schema audit;
  create function auth.uid() returns uuid language sql stable as $$select '${leader}'::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table internal.command_deduplication(actor_profile_id uuid,idempotency_key uuid,command_type text,result jsonb);
  create table internal.domain_outbox(club_id uuid,event_type text,aggregate_type text,aggregate_id uuid,aggregate_revision bigint,payload jsonb);
  create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,aggregate_id uuid,aggregate_revision bigint,metadata jsonb);
  create table core.teams(id uuid primary key,club_id uuid,status text);
  insert into core.teams values('${team}','${club}','active');
  create table core.event_locations(id uuid primary key default gen_random_uuid(),club_id uuid,name text,created_by uuid);
  create table core.recurrence_rules(id uuid primary key default gen_random_uuid(),club_id uuid,timezone text,
   frequency text not null constraint recurrence_rules_frequency_check check (frequency in ('daily','weekly')),
   interval_value integer,local_start timestamp,occurrence_count integer,created_by uuid);
  create table core.events(id uuid primary key default gen_random_uuid(),club_id uuid,owning_team_id uuid,recurrence_id uuid,
   occurrence_number integer,occurrence_key text,event_type text,title text,description text,state text,
   starts_at timestamptz,ends_at timestamptz,all_day boolean,timezone text,location_id uuid,created_by uuid);
  create table core.event_teams(club_id uuid,event_id uuid,team_id uuid,relation text,capabilities text[],created_by uuid);
  create table core.event_audiences(club_id uuid,event_id uuid,audience_type text,team_id uuid,created_by uuid);
  create table core.event_revisions(club_id uuid,event_id uuid,event_revision bigint,action text,scope text,snapshot jsonb,actor_profile_id uuid);
  create function internal.event_snapshot(core.events) returns jsonb language sql as $$select '{}'::jsonb$$;
  create function internal.actor_has_capability(uuid,uuid,text) returns boolean language sql stable as $$select true$$;`);
  await db.exec(read('supabase/migrations/20261019090000_monthly_event_series.sql').replace(/notify pgrst[^;]*;/, ''));

  // Monthly: same day each month, clamped at month end, local time kept over DST.
  const monthly = await create('monthly', 1, 4, '2026-01-31 18:00+01', '70000000-0000-4000-8000-000000000001');
  assert.deepEqual(await localStarts(monthly),
    ['2026-01-31 18:00', '2026-02-28 18:00', '2026-03-31 18:00', '2026-04-30 18:00']);
  // Biweekly is weekly with interval 2.
  const biweekly = await create('weekly', 2, 3, '2026-10-03 10:00+02', '70000000-0000-4000-8000-000000000002');
  assert.deepEqual(await localStarts(biweekly), ['2026-10-03 10:00', '2026-10-17 10:00', '2026-10-31 10:00']);
  assert.equal(await one("select count(*)::int from core.recurrence_rules where frequency='monthly'"), 1);
  // Anything else is still refused.
  await assert.rejects(() => create('yearly', 1, 2, '2026-10-03 10:00+02', '70000000-0000-4000-8000-000000000003'), /invalid_input/);
  console.log('monthly event series: ok');
} finally {
  await db.close();
}
