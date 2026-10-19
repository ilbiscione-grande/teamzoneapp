// Callup visibility (CAL-10, UX review 2026-10-19): who is called up is
// private by default; the team's default and the event's own choice open
// it to members. Attendance stays private. node supabase/tests/callup_visibility.local.mjs
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
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); try { return await fn(); } finally { await db.exec('reset role'); } };
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
  create table core.events(id uuid primary key,club_id uuid,owning_team_id uuid,starts_at timestamptz);
  insert into core.events values('${event}','${club}','${team}',now()+interval '1 day');
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
  create table internal.notification_outbox(aggregate_id uuid,event_type text,state text,created_at timestamptz default now());
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
  await db.exec('grant execute on all functions in schema api, internal to authenticated');
  const squadOf = who => user(who, 'select api.get_event_squad($1)', [event]);
  const called = s => s.roster.filter(r => r.callup_id).map(r => r.name).sort();

  // Private by default: Anna sees only herself; the leader everyone.
  let s = await squadOf(anna);
  assert.equal(s.show_callups_to_members, false);
  assert.deepEqual(s.callups.map(c => c.name), ['Anna']);
  assert.deepEqual(called(s), ['Anna']);
  assert.deepEqual(s.attendance.map(a => a.name), ['Anna'], 'attendance stays private');
  assert.deepEqual(called(await squadOf(leader)), ['Anna', 'Bo']);
  assert.equal((await squadOf(leader)).attendance.length, 2);

  // The team's default opens it; Anna cannot change it, the leader can.
  assert.equal((await user(anna, 'select api.get_team_callup_visibility($1)', [team])).can_change, false);
  await assert.rejects(() => user(anna, 'select api.set_team_callup_visibility($1,$2)', [team, true]), /not_found/);
  await user(leader, 'select api.set_team_callup_visibility($1,$2)', [team, true]);
  s = await squadOf(anna);
  assert.deepEqual([s.show_callups_to_members, s.callup_visibility_source], [true, 'team']);
  assert.deepEqual(called(s), ['Anna', 'Bo']);
  assert.deepEqual(s.attendance.map(a => a.name), ['Anna'], 'still only her own attendance');

  // The event's own choice wins, and can go back to the team's.
  await db.exec(`insert into core.event_callup_visibility(event_id,club_id,show_to_members) values('${event}','${club}',false)`);
  s = await squadOf(anna);
  assert.deepEqual([s.show_callups_to_members, s.callup_visibility_source, s.team_shows_callups], [false, 'event', true]);
  await assert.rejects(() => user(anna, 'select api.clear_event_callup_visibility($1)', [event]), /not_found/);
  await user(leader, 'select api.clear_event_callup_visibility($1)', [event]);
  assert.equal((await squadOf(anna)).callup_visibility_source, 'team');
  console.log('callup visibility: ok');
} finally {
  await db.close();
}
