// Self-rated effort after a training (PAR-PRIV-04, 2026-11-02): from 13,
// the player answers, guardians see, the player can opt out, answers go
// after 24 months, and the leaders see the average in the load.
// node supabase/tests/session_effort.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), adaLogin = id(2), boLogin = id(3), parentLogin = id(4), club = id(10), team = id(20);
const [ada, bo, cy, parent] = [id(50), id(51), id(52), id(53)];
const [done, old, ahead, ancient] = [id(30), id(31), id(32), id(33)];
const year = new Date().getFullYear();
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${coach}','Anna'),('${adaLogin}',''),('${boLogin}',''),('${parentLogin}','');
create table core.teams(id uuid primary key, club_id uuid); insert into core.teams values ('${team}','${club}');
create table core.club_people(id uuid primary key, club_id uuid, display_name text, status text default 'active',
  birth_date date, birth_year smallint);
insert into core.club_people(id, club_id, display_name, birth_date, birth_year) values
  ('${ada}','${club}','Ada', current_date - interval '14 years', ${year - 14}),
  ('${bo}','${club}','Bo', null, ${year - 12}),
  ('${cy}','${club}','Cy', null, null),
  ('${parent}','${club}','Förälder', null, null);
create table core.person_account_links(profile_id uuid, club_id uuid, club_person_id uuid, state text);
insert into core.person_account_links values ('${coach}','${club}',null,'active'),('${adaLogin}','${club}','${ada}','active'),
  ('${boLogin}','${club}','${bo}','active'),('${parentLogin}','${club}','${parent}','active');
create table core.guardian_relations(club_id uuid, guardian_person_id uuid, child_person_id uuid, state text,
  starts_at timestamptz, ends_at timestamptz);
insert into core.guardian_relations values ('${club}','${parent}','${ada}','active', now() - interval '1 year', null);
create table core.assignments(id uuid primary key default gen_random_uuid(), club_id uuid, team_id uuid, club_person_id uuid,
  role_package text, state text);
insert into core.assignments(club_id, team_id, club_person_id, role_package, state) values
  ('${club}','${team}','${ada}','player','active'),('${club}','${team}','${bo}','player','active'),
  ('${club}','${team}','${cy}','player','active');
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, starts_at timestamptz, ends_at timestamptz,
  event_type text default 'training', archived_at timestamptz, state text default 'scheduled',
  timezone text default 'Europe/Stockholm', title text default 'Träning');
insert into core.events(id, club_id, owning_team_id, starts_at, ends_at) values
  ('${done}','${club}','${team}', now() - interval '26 hours', now() - interval '24 hours'),
  ('${old}','${club}','${team}', now() - interval '10 days', now() - interval '10 days' + interval '90 minutes'),
  ('${ahead}','${club}','${team}', now() + interval '1 day', now() + interval '1 day 90 minutes'),
  ('${ancient}','${club}','${team}', now() - interval '25 months', now() - interval '25 months' + interval '90 minutes');
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
// The actor's own person and the children they are guardian of, as the
// callup migration defines it.
const migration = read('supabase/migrations/20260902104510_cal10_callup_roster_visibility.sql');
const start = migration.indexOf('create function internal.actor_represents_club_person(');
await db.exec(migration.slice(start, migration.indexOf('$$;', start) + 3));
const plans = read('supabase/migrations/20260815092734_s08_development_plan_foundation.sql');
const owns = plans.indexOf('create function internal.actor_owns_club_person(');
await db.exec(plans.slice(owns, plans.indexOf('$$;', owns) + 3));
for (const name of ['20261202090000_module_foundation', '20261209090000_team_development_plan',
  '20261210090000_team_development_principles', '20261211090000_team_development_sharing',
  '20270122090000_team_development_blocks', '20270128090000_team_development_match_kpis',
  '20270131090000_team_development_load', '20270201090000_session_effort']) {
  await db.exec(read(`supabase/migrations/${name}.sql`));
}
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
const get = (who, event) => call(who, 'select api.get_session_effort($1)', [event]);
const rate = (who, event, value) => call(who, 'select api.set_session_effort($1,$2)', [event, value]);

let effort = await get(adaLogin, done);
assert.deepEqual(effort.people.map(p => [p.name, p.self, p.can_answer, p.rating]), [['Ada', true, true, null]]);
effort = await rate(adaLogin, done, 7);
assert.equal(effort.people[0].rating, 7);
effort = await rate(adaLogin, done, 8);
assert.equal(effort.people[0].rating, 8, 'the answer can be changed');
await fails(adaLogin, 'select api.set_session_effort($1,$2)', [done, 11], /invalid_input/);
console.log('PASS: a player from 13 rates the training after it');

assert.deepEqual((await get(boLogin, done)).people, [], 'Bo turns 12 this year: no question');
await fails(boLogin, 'select api.set_session_effort($1,$2)', [done, 5], /not_allowed/);
assert.deepEqual((await get(adaLogin, ahead)).people, [], 'not before the training');
effort = await get(adaLogin, old);
assert.deepEqual([effort.open, effort.people[0].can_answer], [false, false], 'seven days to answer');
await fails(adaLogin, 'select api.set_session_effort($1,$2)', [old, 5], /not_allowed/);
console.log('PASS: no question under 13, before the training or after seven days');

effort = await get(parentLogin, done);
assert.deepEqual(effort.people.map(p => [p.name, p.self, p.can_answer, p.rating]), [['Ada', false, false, 8]],
  'the guardian sees what the player sees');
await fails(parentLogin, 'select api.set_session_effort($1,$2)', [done, 3], /not_allowed/);
assert.deepEqual((await get(coach, done)).people, [], 'the leaders see it in the load, not here');
console.log('PASS: the guardian sees the answer but does not give it');

const plan = await call(coach, "select api.create_team_development_plan($1,'Säsongen',$2,$3,'')",
  [team, new Date(Date.now() - 60 * 864e5).toISOString().slice(0, 10), new Date(Date.now() + 200 * 864e5).toISOString().slice(0, 10)]);
let load = await call(coach, 'select api.get_team_development_load($1,null)', [plan.id]);
const row = name => load.players.find(p => p.name === name);
assert.deepEqual([row('Ada').effort_7, row('Ada').efforts_7], [8, 1]);
assert.deepEqual([row('Bo').effort_7, row('Bo').efforts_7], [null, 0]);
console.log('PASS: the leaders see the average effort of the last 7 days in the load');

effort = await call(adaLogin, 'select api.set_session_effort_opt_out($1,true)', [done]);
assert.deepEqual([effort.people[0].opted_out, effort.people[0].can_answer, effort.people[0].rating], [true, false, null],
  'opting out deletes the answers');
await fails(adaLogin, 'select api.set_session_effort($1,$2)', [done, 5], /not_allowed/);
await fails(parentLogin, 'select api.set_session_effort_opt_out($1,false)', [done], /not_allowed/);
effort = await call(adaLogin, 'select api.set_session_effort_opt_out($1,false)', [done]);
assert.equal(effort.people[0].can_answer, true);
console.log('PASS: the player opts out and in again');

await db.exec(`insert into core.session_effort_ratings(club_id, event_id, club_person_id, rating) values
  ('${club}','${ancient}','${ada}',5),('${club}','${done}','${ada}',6);`);
assert.equal((await db.query('select internal.apply_session_effort_retention() n')).rows[0].n, 1);
assert.deepEqual((await db.query('select event_id from core.session_effort_ratings')).rows.map(r => r.event_id), [done]);
console.log('PASS: answers go 24 months after the training');
