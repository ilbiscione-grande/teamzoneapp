// Team Development Plan step 9 (2026-11-02): injuries. On from 15, under
// 15 with the club's, the player's and a guardian's consent; the leaders or
// the club turn it off; the player and guardians see the injuries without
// the leaders' notes; deleted 24 months after the player was back.
// node supabase/tests/player_injuries.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), adaLogin = id(2), boLogin = id(3), parentLogin = id(4), admin = id(5), club = id(10), team = id(20);
const [ada, bo, parent] = [id(50), id(51), id(53)];
const year = new Date().getFullYear();
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${coach}','Anna'),('${adaLogin}',''),('${boLogin}',''),('${parentLogin}',''),('${admin}','');
create table core.teams(id uuid primary key, club_id uuid); insert into core.teams values ('${team}','${club}');
create table core.club_people(id uuid primary key, club_id uuid, display_name text, status text default 'active',
  birth_date date, birth_year smallint);
insert into core.club_people(id, club_id, display_name, birth_year) values
  ('${ada}','${club}','Ada', ${year - 16}), ('${bo}','${club}','Bo', ${year - 13}), ('${parent}','${club}','Förälder', null);
create table core.person_account_links(profile_id uuid, club_id uuid, club_person_id uuid, state text);
insert into core.person_account_links values ('${coach}','${club}',null,'active'),('${adaLogin}','${club}','${ada}','active'),
  ('${boLogin}','${club}','${bo}','active'),('${parentLogin}','${club}','${parent}','active'),('${admin}','${club}',null,'active');
create table core.guardian_relations(club_id uuid, guardian_person_id uuid, child_person_id uuid, state text,
  starts_at timestamptz, ends_at timestamptz);
insert into core.guardian_relations values ('${club}','${parent}','${bo}','active', now() - interval '1 year', null);
create table core.assignments(id uuid primary key default gen_random_uuid(), club_id uuid, team_id uuid, club_person_id uuid,
  role_package text, state text);
insert into core.assignments(club_id, team_id, club_person_id, role_package, state) values
  ('${club}','${team}','${ada}','player','active'),('${club}','${team}','${bo}','player','active');
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
  select (auth.uid() = '${coach}'::uuid and cap in ('development.manage', 'team.roster.view'))
      or (auth.uid() = '${admin}'::uuid and cap = 'club.memberships.manage') $$;
create function internal.actor_has_event_capability(e uuid, cap text) returns boolean language sql stable as $$ select false $$;
create table core.module_attachments (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references core.clubs(id),
  owner_kind text not null check (owner_kind in ('match_plan')), owner_id uuid not null,
  kind text not null check (kind in ('link')), title text not null, url text,
  visible_to_players boolean not null default false, position integer not null default 0,
  created_by uuid, created_at timestamptz not null default now());
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, starts_at timestamptz, ends_at timestamptz,
  event_type text, archived_at timestamptz, state text, timezone text, title text);
create table core.match_workspaces(event_id uuid primary key, state text, period_minutes integer[]);
create table core.match_projections(event_id uuid primary key, score_us integer, score_opponent integer);
create table core.match_facts(id uuid primary key default gen_random_uuid(), event_id uuid, fact_type text, side text,
  detail jsonb default '{}', state text default 'active');
create table core.team_match_buttons(team_id uuid primary key, buttons jsonb);
grant usage on schema api, internal, core, auth to authenticated;`);
for (const [file, name] of [['20260902104510_cal10_callup_roster_visibility', 'internal.actor_represents_club_person'],
  ['20260815092734_s08_development_plan_foundation', 'internal.actor_owns_club_person']]) {
  const text = read(`supabase/migrations/${file}.sql`);
  const start = text.indexOf(`create function ${name}(`);
  await db.exec(text.slice(start, text.indexOf('$$;', start) + 3));
}
for (const name of ['20261202090000_module_foundation', '20261209090000_team_development_plan',
  '20261210090000_team_development_principles', '20261211090000_team_development_sharing',
  '20270122090000_team_development_blocks', '20270128090000_team_development_match_kpis',
  '20270203090000_player_injuries']) {
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
const day = offset => new Date(Date.now() + offset * 864e5).toISOString().slice(0, 10);
const plan = await call(coach, "select api.create_team_development_plan($1,'Säsongen',$2,$3,'')", [team, day(-60), day(200)]);
const save = (person, what, note, startedOn = day(-3), injury = null, backOn = null) =>
  call(coach, 'select api.save_team_development_injury($1,$2,$3,$4,$5,$6,$7)',
    [plan.id, injury, person, startedOn, what, note, backOn]);
const row = (result, name) => result.players.find(p => p.name === name);

let injuries = await call(coach, 'select api.get_team_development_injuries($1)', [plan.id]);
assert.deepEqual([row(injuries, 'Ada').allowed, row(injuries, 'Bo').allowed], [true, false], 'on from 15 only');
injuries = await save(ada, 'Stukad fot', 'Undvik hopp en vecka');
assert.deepEqual(row(injuries, 'Ada').injuries.map(i => [i.what, i.note, i.back_on]), [['Stukad fot', 'Undvik hopp en vecka', null]]);
await fails(coach, 'select api.save_team_development_injury($1,$2,$3,$4,$5,$6,$7)',
  [plan.id, null, bo, day(-1), 'Knä', '', null], /not_allowed/);
await fails(coach, 'select api.save_team_development_injury($1,$2,$3,$4,$5,$6,$7)',
  [plan.id, null, ada, day(2), 'Knä', '', null], /invalid_input/);
await fails(adaLogin, 'select api.get_team_development_injuries($1)', [plan.id], /not_found/);
console.log('PASS: the leaders register an injury from 15, and only they read the team\'s');

const injuryId = row(injuries, 'Ada').injuries[0].id;
injuries = await save(ada, 'Stukad fot', 'Undvik hopp en vecka', day(-3), injuryId, day(0));
assert.equal(row(injuries, 'Ada').injuries[0].back_on, day(0), 'a leader notes the day back in training');
let mine = await call(adaLogin, 'select api.get_my_injuries($1)', [team]);
assert.deepEqual(mine.people.map(p => [p.name, p.self, p.injuries.map(i => [i.what, i.back_on, 'note' in i])]),
  [['Ada', true, [['Stukad fot', day(0), false]]]], 'the player sees the injury, not the notes');
console.log('PASS: back in training, and the player sees their injury without the notes');

mine = await call(parentLogin, 'select api.get_my_injuries($1)', [team]);
assert.deepEqual(mine.people.map(p => [p.name, p.self, p.allowed, p.consents]),
  [['Bo', false, false, { club: false, player: false, guardian: false }]]);
await call(parentLogin, 'select api.set_injury_consent($1,$2,true)', [team, bo]);
await call(boLogin, 'select api.set_injury_consent($1,$2,true)', [team, bo]);
injuries = await call(coach, 'select api.set_team_development_injury_registration($1,$2,null,true)', [plan.id, bo]);
assert.deepEqual([row(injuries, 'Bo').allowed, row(injuries, 'Bo').consents], [true, { club: true, player: true, guardian: true }]);
injuries = await save(bo, 'Ont i knät', 'Lättare pass');
assert.equal(row(injuries, 'Bo').injuries.length, 1);
mine = await call(parentLogin, 'select api.get_my_injuries($1)', [team]);
assert.deepEqual(mine.people[0].injuries.map(i => [i.what, 'note' in i]), [['Ont i knät', false]], 'the guardian sees what the player sees');
mine = await call(boLogin, 'select api.set_injury_consent($1,$2,false)', [team, bo]);
assert.deepEqual([mine.people[0].allowed, mine.people[0].injuries], [false, []], 'withdrawing a consent under 15 deletes the injuries');
await fails(adaLogin, 'select api.set_injury_consent($1,$2,true)', [team, bo], /not_found/);
console.log('PASS: under 15 with the club\'s, the player\'s and a guardian\'s consent');

injuries = await call(coach, 'select api.set_team_development_injury_registration($1,$2,true,null)', [plan.id, ada]);
assert.deepEqual([row(injuries, 'Ada').allowed, row(injuries, 'Ada').turned_off, row(injuries, 'Ada').injuries], [false, true, []],
  'turning off deletes the injuries');
let status = await call(admin, 'select api.set_club_injury_registration($1,false,null)', [ada]);
assert.equal(status.allowed, true, 'the club turns it on again');
await fails(adaLogin, 'select api.set_club_injury_registration($1,true,null)', [ada], /not_found/);
console.log('PASS: the leaders and the club turn it off and on');

await db.exec(`insert into core.player_injuries(club_id, team_id, club_person_id, started_on, what, back_on) values
  ('${club}','${team}','${ada}', current_date - interval '30 months', 'Gammal', current_date - interval '25 months'),
  ('${club}','${team}','${ada}', current_date - interval '26 months', 'Öppen', null),
  ('${club}','${team}','${ada}', current_date - interval '3 months', 'Ny', current_date - interval '2 months')`);
assert.equal((await db.query('select internal.apply_player_injury_retention() n')).rows[0].n, 2);
assert.deepEqual((await db.query('select what from core.player_injuries')).rows.map(r => r.what), ['Ny']);
console.log('PASS: injuries go 24 months after the player was back');
