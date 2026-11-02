// Team Development Plan, new design step 8 (2026-11-02): the players' load
// over 7 days and 4 weeks (trainings, training minutes, match minutes) and
// the signals the leaders set per team (PAR-METHOD-01).
// node supabase/tests/team_development_load.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), outsider = id(2), club = id(10), team = id(20);
const [ada, bo, cy, gone] = [id(50), id(51), id(52), id(53)];
const [t1, t2, t3, t4, t5, m1, m2] = [id(30), id(31), id(32), id(33), id(34), id(35), id(36)];
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${coach}','Anna Tränare'),('${outsider}','');
create table core.teams(id uuid primary key, club_id uuid); insert into core.teams values ('${team}','${club}');
create table core.person_account_links(profile_id uuid, club_id uuid, state text);
insert into core.person_account_links values ('${coach}','${club}','active');
create table core.club_people(id uuid primary key, club_id uuid, display_name text, status text default 'active');
insert into core.club_people(id, club_id, display_name, status) values
  ('${ada}','${club}','Ada','active'),('${bo}','${club}','Bo','active'),('${cy}','${club}','Cy','active'),('${gone}','${club}','Ex','ended');
create table core.assignments(id uuid primary key default gen_random_uuid(), club_id uuid, team_id uuid, club_person_id uuid,
  role_package text, state text);
insert into core.assignments(club_id, team_id, club_person_id, role_package, state) values
  ('${club}','${team}','${ada}','player','active'),('${club}','${team}','${bo}','player','active'),
  ('${club}','${team}','${cy}','player','active'),('${club}','${team}','${gone}','player','active');
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, starts_at timestamptz, ends_at timestamptz,
  event_type text default 'training', archived_at timestamptz, state text default 'scheduled',
  timezone text default 'Europe/Stockholm', title text default 'Träning');
create table core.attendance_facts(event_id uuid, club_person_id uuid, status text, minutes integer);
create table core.event_lineups(event_id uuid primary key, starters jsonb not null default '[]');
create table core.development_plans (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references core.clubs(id), team_id uuid not null,
  subject_club_person_id uuid, plan_type text not null check (plan_type in ('team', 'player')),
  title text not null check (length(btrim(title)) between 2 and 120),
  focus text not null default '' check (length(focus) <= 4000),
  state text not null default 'draft' check (state in ('draft', 'active', 'completed', 'archived')),
  created_at timestamptz not null default now(), created_by uuid not null references core.profiles(id),
  updated_at timestamptz not null default now(), updated_by uuid not null references core.profiles(id),
  revision bigint not null default 1 check (revision > 0), unique (id, club_id));
create table core.club_entitlements(club_id uuid, entitlement_key text, access_mode text, expires_at timestamptz);
create function internal.actor_has_club_access(target uuid) returns boolean language sql stable as $$ select true $$;
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$
  select (auth.uid() = '${coach}'::uuid and cap in ('development.manage', 'team.roster.view')) $$;
create function internal.actor_has_event_capability(e uuid, cap text) returns boolean language sql stable as $$
  select auth.uid() = '${coach}'::uuid and cap = 'training.plan' $$;
create table core.module_attachments (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references core.clubs(id),
  owner_kind text not null check (owner_kind in ('match_plan')), owner_id uuid not null,
  kind text not null check (kind in ('link')), title text not null, url text,
  visible_to_players boolean not null default false, position integer not null default 0,
  created_by uuid, created_at timestamptz not null default now());
create table core.match_workspaces(event_id uuid primary key, state text, period_minutes integer[] default array[45,45]);
create table core.match_projections(event_id uuid primary key, score_us integer, score_opponent integer);
create table core.match_facts(id uuid primary key default gen_random_uuid(), event_id uuid, fact_type text, side text,
  minute integer default 0, club_person_id uuid, secondary_club_person_id uuid,
  detail jsonb default '{}', state text default 'active', created_at timestamptz default now());
create table core.team_match_buttons(team_id uuid primary key, buttons jsonb);
grant usage on schema api, internal, core, auth to authenticated;`);
for (const name of ['20261202090000_module_foundation', '20261209090000_team_development_plan',
  '20261210090000_team_development_principles', '20261211090000_team_development_sharing',
  '20270122090000_team_development_blocks', '20270128090000_team_development_match_kpis',
  '20270131090000_team_development_load']) {
  await db.exec(read(`supabase/migrations/${name}.sql`));
}
// Sessions of 90 minutes, [days] ago at 18:00.
const at = days => `(date_trunc('day', now() at time zone 'Europe/Stockholm') - interval '${days} days' + interval '18 hours') at time zone 'Europe/Stockholm'`;
const held = (event, days, type = 'training') => `insert into core.events(id, club_id, owning_team_id, starts_at, ends_at, event_type)
  values ('${event}','${club}','${team}',${at(days)},${at(days)} + interval '90 minutes','${type}');`;
await db.exec([held(t1, 20), held(t2, 10), held(t3, 3), held(t4, 1), held(t5, 2), held(m1, 2, 'match'), held(m2, 5, 'match')].join('\n'));
await db.exec(`insert into core.attendance_facts values
  ('${t1}','${ada}','present',null),('${t2}','${ada}','present',null),('${t3}','${ada}','present',null),('${t4}','${ada}','present',null),
  ('${t1}','${bo}','present',null),('${t2}','${bo}','absent',null),('${t3}','${bo}','absent',null),('${t4}','${bo}','late',30),
  ('${t1}','${cy}','absent',null),('${t2}','${cy}','absent',null),('${t3}','${cy}','absent',null),('${t4}','${cy}','partial',45),
  ('${t5}','${ada}','unknown',null);
insert into core.match_workspaces(event_id, state) values ('${m1}','completed'),('${m2}','completed');
insert into core.event_lineups values ('${m1}','[{"person_id":"${ada}"},{"person_id":"${bo}"}]'),('${m2}','[{"person_id":"${ada}"}]');
insert into core.match_facts(event_id, fact_type, side, minute, club_person_id, secondary_club_person_id, detail, state) values
  ('${m1}','substitution','us',60,'${bo}','${cy}','{}','active'),
  ('${m1}','substitution','us',30,'${ada}','${bo}','{}','voided'),
  ('${m1}','card','us',80,'${ada}',null,'{"color":"red"}','active'),
  ('${m1}','card','us',20,'${bo}',null,'{"color":"yellow"}','active'),
  ('${m1}','full_time','us',90,null,null,'{}','active'),
  ('${m2}','substitution','opponent',50,null,null,'{}','active');`);
const call = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  await db.exec('set role authenticated');
  try {
    return Object.values((await db.query(sql, params)).rows[0] ?? {})[0];
  } finally {
    await db.exec('reset role');
  }
};
const fails = async (who, sql, params, pattern) => assert.rejects(call(who, sql, params), pattern);
const day = offset => new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);
const plan = await call(coach, "select api.create_team_development_plan($1,'Säsongen',$2,$3,'')", [team, day(-60), day(200)]);
const rows = load => Object.fromEntries(load.players.map(p => [p.name, p]));

let load = await call(coach, 'select api.get_team_development_load($1,null)', [plan.id]);
assert.deepEqual(load.settings, { load_increase_percent: 130, attendance_min_percent: 50, match_minutes_max: 180 });
assert.deepEqual(load.players.map(p => p.name), ['Ada', 'Bo', 'Cy'], 'the active players, by name');
let by = rows(load);
assert.deepEqual([by.Ada.match_minutes_7, by.Bo.match_minutes_7, by.Cy.match_minutes_7], [170, 60, 30],
  'starters from 0, a substitution and a red card end a spell, the voided one and the opponent\'s do not count');
console.log('PASS: match minutes are counted from the line-up, the substitutions and red cards');

assert.deepEqual([by.Ada.sessions_7, by.Ada.sessions_28, by.Ada.training_minutes_7, by.Ada.training_minutes_28], [2, 4, 180, 360]);
assert.deepEqual([by.Bo.sessions_28, by.Bo.training_minutes_28, by.Bo.attendance_percent], [2, 150, 50], 'late: the session less the minutes late');
assert.deepEqual([by.Cy.sessions_28, by.Cy.training_minutes_28, by.Cy.attendance_percent], [1, 45, 25], 'partial: the minutes present');
assert.equal(by.Ada.trainings_28, 4, 'a training without attendance taken does not count');
assert.equal(by.Ada.load_percent, 264, 'the 7 days against the weekly average of the 4 weeks');
console.log('PASS: trainings and training minutes come from the attendance, over 7 days and 4 weeks');

assert.deepEqual([by.Ada.signals, by.Bo.signals, by.Cy.signals], [['load_increase'], ['load_increase'], ['low_attendance']],
  'Cy has nothing before the last 7 days, so no increase; Bo at 50 % is not under 50 %');
await fails(outsider, 'select api.get_team_development_load($1,null)', [plan.id], /not_found/);
console.log('PASS: the default signals, for the leaders only');

load = await call(coach, 'select api.set_team_development_load_settings($1,300,30,150)', [plan.id]);
by = rows(load);
assert.deepEqual([by.Ada.signals, by.Bo.signals, by.Cy.signals], [['match_minutes'], [], ['low_attendance']]);
load = await call(coach, 'select api.set_team_development_load_settings($1,300,null,null)', [plan.id]);
assert.deepEqual(load.settings, { load_increase_percent: 300, attendance_min_percent: null, match_minutes_max: null });
assert.deepEqual(load.players.map(p => p.signals), [[], [], []], 'an empty value turns the signal off');
await fails(coach, 'select api.set_team_development_load_settings($1,50,null,null)', [plan.id], /invalid_input/);
await fails(outsider, 'select api.set_team_development_load_settings($1,200,null,null)', [plan.id], /not_found/);
console.log('PASS: the leaders set the team\'s values, and an empty one turns the signal off');
