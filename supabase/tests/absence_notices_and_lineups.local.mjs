// Absence notices and the starting line-up (UX review 2026-10-19), in
// isolated Postgres with the reduced team of callup_visibility.local.mjs.
// node supabase/tests/absence_notices_and_lineups.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const leader = id(1), anna = id(2), bo = id(3);
const club = id(10), team = id(20), event = id(30), squad = id(40);
const pLeader = id(51), pAnna = id(52), pBo = id(53);
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
const user = (who, sql, params) => as(who).then(() => asRole('authenticated', () => one(sql, params)));
try {
  await db.exec(`create role anon;create role authenticated;
  create schema internal;create schema api;create schema core;create schema auth;create schema audit;
  set check_function_bodies = off;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table core.profiles(id uuid primary key);
  insert into core.profiles values('${leader}'),('${anna}'),('${bo}');
  create table core.clubs(id uuid primary key);insert into core.clubs values('${club}');
  create table core.teams(id uuid primary key,club_id uuid,name text,created_at timestamptz default now());
  insert into core.teams values('${team}','${club}','P2012');
  create table core.club_people(id uuid primary key,club_id uuid,display_name text,status text default 'active');
  insert into core.club_people(id,club_id,display_name) values('${pLeader}','${club}','Lena'),('${pAnna}','${club}','Anna'),('${pBo}','${club}','Bo');
  create table core.person_account_links(profile_id uuid,club_id uuid,club_person_id uuid,state text);
  insert into core.person_account_links values('${leader}','${club}','${pLeader}','active'),('${anna}','${club}','${pAnna}','active'),('${bo}','${club}','${pBo}','active');
  create table core.guardian_relations(club_id uuid,guardian_person_id uuid,child_person_id uuid,state text,starts_at timestamptz,ends_at timestamptz);
  create table core.assignments(club_id uuid,team_id uuid,club_person_id uuid,role_package text,state text default 'active',
   starts_at timestamptz default now()-interval '1 year',ends_at timestamptz);
  insert into core.assignments(club_id,team_id,club_person_id,role_package) values('${club}','${team}','${pLeader}','leader'),
   ('${club}','${team}','${pAnna}','player'),('${club}','${team}','${pBo}','player');
  create table core.events(id uuid primary key,club_id uuid,owning_team_id uuid,starts_at timestamptz,ends_at timestamptz,
   event_type text default 'training',state text default 'scheduled',callups_required boolean not null default true,
   revision bigint not null default 1,timezone text default 'Europe/Stockholm');
  insert into core.events(id,club_id,owning_team_id,starts_at,ends_at) values('${event}','${club}','${team}',now()+interval '1 day',now()+interval '1 day 90 minutes');
  create table core.event_teams(event_id uuid,club_id uuid,team_id uuid);insert into core.event_teams values('${event}','${club}','${team}');
  create table core.squad_revisions(id uuid primary key,event_id uuid,revision bigint,state text,selection_source text,
   selection_context jsonb,dispatch_kind text);
  insert into core.squad_revisions values('${squad}','${event}',1,'sent','manual','{}','initial');
  create table core.squad_members(squad_revision_id uuid,club_person_id uuid,selection_state text,source text);
  insert into core.squad_members values('${squad}','${pAnna}','selected','manual'),('${squad}','${pBo}','selected','manual');
  create table core.callups(id uuid primary key default gen_random_uuid(),event_id uuid,club_id uuid,club_person_id uuid,state text,
   revision bigint default 1,expires_at timestamptz,last_reminded_at timestamptz,reminder_count int default 0);
  insert into core.callups(event_id,club_id,club_person_id,state) values('${event}','${club}','${pAnna}','accepted'),('${event}','${club}','${pBo}','pending');
  create table core.attendance_facts(id uuid primary key default gen_random_uuid(),event_id uuid,club_id uuid,club_person_id uuid,
   status text,minutes int,revision bigint default 1);
  insert into core.attendance_facts(event_id,club_id,club_person_id,status) values('${event}','${club}','${pAnna}','present'),('${event}','${club}','${pBo}','absent');
  create table internal.notification_outbox(id uuid primary key default gen_random_uuid(),club_id uuid,domain_event_id uuid,event_type text,
   aggregate_type text,aggregate_id uuid,recipient_profile_id uuid,recipient_person_id uuid,payload_ref jsonb,state text,
   created_at timestamptz default now(),unique(domain_event_id,recipient_person_id));
  create function internal.match_pool_recipients(c uuid,t uuid) returns table(profile_id uuid,club_person_id uuid) language sql stable as
   $$select '${leader}'::uuid,'${pLeader}'::uuid$$;
  create table core.event_callup_visibility(event_id uuid primary key,club_id uuid,show_to_members boolean not null,
   revision bigint not null default 1,updated_at timestamptz default now(),updated_by uuid);
  create function internal.actor_can_read_event(e uuid) returns boolean language sql stable as $$select auth.uid() is not null$$;
  create function internal.actor_can_manage_squad(e uuid) returns boolean language sql stable as $$select auth.uid()='${leader}'::uuid$$;
  create function internal.actor_can_manage_attendance(e uuid) returns boolean language sql stable as $$select auth.uid()='${leader}'::uuid$$;
  create function internal.actor_has_capability(c uuid,t uuid,cap text) returns boolean language sql stable as $$select auth.uid()='${leader}'::uuid$$;
  create function internal.actor_manages_club(c uuid) returns boolean language sql stable as $$select false$$;
  create function internal.actor_callup_response_context(c uuid) returns jsonb language sql stable as $$select '{}'::jsonb$$;
  create function internal.get_visible_decline_reasons_for_actor(e uuid) returns jsonb language sql stable as $$select '[]'::jsonb$$;
  grant usage on schema api, internal, core to authenticated;`);
  // CAL-10's helper and the api wrapper, as they exist in production.
  const cal10 = read('supabase/migrations/20260902104510_cal10_callup_roster_visibility.sql');
  await db.exec(cal10.slice(cal10.indexOf('create function internal.actor_represents_club_person('),
    cal10.indexOf('create function internal.set_event_callup_visibility_for_actor(')));
  const walkIn = read('supabase/migrations/20260928104134_event_participants_walk_in_attendance.sql');
  const wrapStart = walkIn.indexOf('create or replace function api.get_event_squad(');
  await db.exec(walkIn.slice(wrapStart, walkIn.indexOf('$$;', wrapStart) + 3));
  await db.exec(read('supabase/migrations/20261112090000_callup_visibility_by_team.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec(read('supabase/migrations/20261112090000_callup_visibility_by_team.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec(read('supabase/migrations/20261113090000_absence_notices_and_lineups.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec('grant execute on all functions in schema api, internal to authenticated');
  const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
  await db.exec('begin');

  // With callups required, no notices.
  await reject(() => user(anna, 'select api.report_event_absence($1,$2,$3)', [event, pAnna, 'illness']), /not_open/);

  // The team chooses absence notices: coming events follow, new ones too.
  assert.equal((await user(anna, 'select api.get_team_event_settings($1)', [team])).can_change, false);
  await reject(() => user(anna, 'select api.set_team_event_settings($1,$2)', [team, false]), /not_found/);
  // Events with sent callups keep them; this one has a draft squad.
  await db.exec("update core.squad_revisions set state='draft'");
  assert.equal(await user(leader, 'select api.set_team_event_settings($1,$2)', [team, false]), 1);
  assert.equal(await one(`select callups_required from core.events where id='${event}'`), false);
  await db.exec(`insert into core.events(id,club_id,owning_team_id,starts_at,ends_at) values('${id(31)}','${club}','${team}',now()+interval '3 days',now()+interval '3 days 1 hour')`);
  assert.equal(await one(`select callups_required from core.events where id='${id(31)}'`), false);

  // Anna reports herself; not Bo; the leader hears; the reason stays private.
  await user(anna, 'select api.report_event_absence($1,$2,$3)', [event, pAnna, 'illness']);
  await reject(() => user(anna, 'select api.report_event_absence($1,$2,$3)', [event, pBo, 'illness']), /not_found/);
  await reject(() => user(bo, 'select api.report_event_absence($1,$2,$3)', [event, pBo, 'other']), /invalid_decline_reason/);
  assert.deepEqual((await db.query(`select recipient_profile_id who from internal.notification_outbox where event_type='absence.reported.v1'`)).rows.map(r => r.who), [leader]);
  let s = await user(leader, 'select api.get_event_squad($1)', [event]);
  assert.deepEqual(s.absence_notices.map(n => [n.name, n.reason_code]), [['Anna', 'illness']]);
  assert.deepEqual((await user(bo, 'select api.get_event_squad($1)', [event])).absence_notices, []);
  assert.deepEqual((await user(bo, 'select api.get_event_squad($1)', [event])).represented_people.map(p => p.name), ['Bo']);
  // Reporting again replaces; withdrawing removes.
  await user(anna, 'select api.report_event_absence($1,$2,$3,$4)', [event, pAnna, 'other', 'Bortrest']);
  s = await user(anna, 'select api.get_event_squad($1)', [event]);
  assert.deepEqual(s.absence_notices.map(n => [n.reason_code, n.reason_text]), [['other', 'Bortrest']]);
  await user(anna, 'select api.withdraw_event_absence($1,$2)', [event, pAnna]);
  assert.deepEqual((await user(anna, 'select api.get_event_squad($1)', [event])).absence_notices, []);
  await user(anna, 'select api.report_event_absence($1,$2,$3)', [event, pAnna, 'injury']);
  await db.exec(`delete from core.callups; delete from core.attendance_facts; insert into core.attendance_facts(event_id,club_id,club_person_id,status)
    values('${event}','${club}','${pAnna}','absent'),('${event}','${club}','${pBo}','absent')`);
  const summary = await one(`select internal.event_attendance_summary('${event}')`);
  assert.deepEqual([summary.absence_notices, summary.absent_reported, summary.absent], [1, 1, 2]);

  // The line-up: a match; hidden from players until shown.
  await db.exec(`update core.events set event_type='match' where id='${event}'`);
  assert.equal(await user(anna, 'select api.get_event_lineup($1)', [event]), null);
  await reject(() => user(anna, 'select api.save_event_lineup($1,$2,$3,$4,$5,$6)',
    [event, '4-4-2', JSON.stringify([{ person_id: pAnna }]), '[]', true, 0]), /not_found/);
  await reject(() => user(leader, 'select api.save_event_lineup($1,$2,$3,$4,$5,$6)',
    [event, '4-4-2', JSON.stringify([{ person_id: pAnna }, { person_id: pAnna }]), '[]', false, 0]), /invalid_input/);
  const r1 = await user(leader, 'select api.save_event_lineup($1,$2,$3,$4,$5,$6)',
    [event, '4-4-2', JSON.stringify([{ person_id: pAnna, position: 'MV' }]), JSON.stringify([{ person_id: pBo }]), false, 0]);
  assert.equal((await user(leader, 'select api.get_event_lineup($1)', [event])).can_edit, true);
  assert.equal(await user(anna, 'select api.get_event_lineup($1)', [event]), null);
  await user(leader, 'select api.save_event_lineup($1,$2,$3,$4,$5,$6)',
    [event, '4-4-2', JSON.stringify([{ person_id: pAnna, position: 'MV' }]), JSON.stringify([{ person_id: pBo }]), true, r1]);
  const lineup = await user(anna, 'select api.get_event_lineup($1)', [event]);
  assert.deepEqual([lineup.can_edit, lineup.starters.map(x => [x.name, x.position]), lineup.substitutes.map(x => x.name)],
    [false, [['Anna', 'MV']], ['Bo']]);
  await reject(() => user(leader, 'select api.save_event_lineup($1,$2,$3,$4,$5,$6)',
    [event, null, '[]', '[]', true, r1]), /stale_revision/);
  console.log('absence notices and line-ups: ok');
} finally {
  await db.close();
}
