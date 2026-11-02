// Team Development Plan, new design step 6 (2026-11-02): key figures from
// the matches. The plan carries the season's played matches with what they
// add up to; a key figure names its source, and a value set by hand for a
// match replaces the counted one.
// node supabase/tests/team_development_match_kpis.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), player = id(2), club = id(10), team = id(20), otherTeam = id(21);
const live = id(30), resultOnly = id(31), upcoming = id(32), cancelled = id(33), elsewhere = id(34), notPlayed = id(35);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${coach}','Anna Tränare'),('${player}','');
create table core.teams(id uuid primary key, club_id uuid); insert into core.teams values ('${team}','${club}'),('${otherTeam}','${club}');
create table core.person_account_links(profile_id uuid, club_id uuid, state text);
insert into core.person_account_links values ('${coach}','${club}','active');
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, starts_at timestamptz,
  event_type text default 'match', archived_at timestamptz, state text default 'scheduled',
  timezone text default 'Europe/Stockholm', title text default 'Match');
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
      or (auth.uid() = '${player}'::uuid and cap = 'team.roster.view') $$;
create function internal.actor_has_event_capability(e uuid, cap text) returns boolean language sql stable as $$
  select auth.uid() = '${coach}'::uuid and cap = 'training.plan' $$;
create table core.module_attachments (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references core.clubs(id),
  owner_kind text not null check (owner_kind in ('match_plan')), owner_id uuid not null,
  kind text not null check (kind in ('link')), title text not null, url text,
  visible_to_players boolean not null default false, position integer not null default 0,
  created_by uuid, created_at timestamptz not null default now());
-- Match Space as the match module keeps it.
create table core.match_workspaces(event_id uuid primary key, state text);
create table core.match_projections(event_id uuid primary key, score_us integer, score_opponent integer);
create table core.match_facts(id uuid primary key default gen_random_uuid(), event_id uuid, fact_type text, side text,
  detail jsonb default '{}', state text default 'active');
create table core.team_match_buttons(team_id uuid primary key, buttons jsonb);
grant usage on schema api, internal, core, auth to authenticated;`);
for (const name of ['20261202090000_module_foundation', '20261209090000_team_development_plan',
  '20261210090000_team_development_principles', '20261211090000_team_development_sharing',
  '20270122090000_team_development_blocks', '20270128090000_team_development_match_kpis']) {
  await db.exec(read(`supabase/migrations/${name}.sql`));
}
const call = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  await db.exec('set role authenticated');
  try {
    const rows = (await db.query(sql, params)).rows;
    return Object.values(rows[0] ?? {})[0];
  } finally {
    await db.exec('reset role');
  }
};
const fails = async (who, sql, params, pattern) => assert.rejects(call(who, sql, params), pattern);
const day = offset => new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);

// The matches: one registered live 3–1, one with its result only 0–0, and
// others that do not count (not yet played, cancelled, another team's, not
// completed).
await db.exec(`insert into core.events(id, club_id, owning_team_id, starts_at, title, state) values
  ('${live}','${club}','${team}', now() - interval '20 days', 'P2012 – Vetlanda IF', 'completed'),
  ('${resultOnly}','${club}','${team}', now() - interval '6 days', 'Eksjö BK – P2012', 'completed'),
  ('${upcoming}','${club}','${team}', now() + interval '3 days', 'P2012 – Nässjö FF', 'scheduled'),
  ('${cancelled}','${club}','${team}', now() - interval '10 days', 'Inställd', 'cancelled'),
  ('${elsewhere}','${club}','${otherTeam}', now() - interval '4 days', 'Annat lag', 'completed'),
  ('${notPlayed}','${club}','${team}', now() - interval '2 days', 'Ej spelad', 'scheduled');
insert into core.match_workspaces values ('${live}','completed'),('${resultOnly}','completed'),
  ('${cancelled}','completed'),('${elsewhere}','completed'),('${notPlayed}','planning');
insert into core.match_projections values ('${live}',3,1),('${resultOnly}',0,0),('${elsewhere}',5,0);
insert into core.match_facts(event_id, fact_type, side, detail, state) values
  ('${live}','goal','us','{}','active'),
  ('${live}','goal','us','{"own_goal":true}','active'),
  ('${live}','penalty','us','{"result":"scored"}','active'),
  ('${live}','shot','us','{"result":"on_target"}','active'),
  ('${live}','shot','us','{"result":"missed"}','active'),
  ('${live}','shot','us','{"result":"missed"}','voided'),
  ('${live}','goal','opponent','{}','active'),
  ('${live}','shot','opponent','{"result":"missed"}','active'),
  ('${live}','corner','us','{}','active'),
  ('${live}','save','us','{}','active'),
  ('${live}','card','us','{"color":"yellow"}','active'),
  ('${live}','card','us','{"color":"red","second_yellow":true}','active'),
  ('${live}','kpi',null,'{"button_id":"ballwin","label":"Bollvinst"}','active'),
  ('${live}','kpi',null,'{"button_id":"ballwin","label":"Bollvinst"}','active'),
  ('${resultOnly}','score_adjustment','us','{"delta":0}','active'),
  ('${resultOnly}','full_time',null,'{}','active');
insert into core.team_match_buttons values ('${team}','[{"id":"ballwin","label":"Bollvinst"}]');`);

let plan = await call(coach, "select api.create_team_development_plan($1,'Säsongen',$2,$3,'')", [team, day(-60), day(200)]);
const season = plan.id;
assert.deepEqual(plan.matches.map(m => m.title), ['P2012 – Vetlanda IF', 'Eksjö BK – P2012']);
const [first, second] = plan.matches;
assert.deepEqual(first.metrics, {
  goals_for: 3, goals_against: 1, points: 3, clean_sheet: 0,
  shots: 4, shots_on_target: 3, shots_against: 2, corners: 1, saves: 1, yellow_cards: 2,
});
assert.deepEqual(first.buttons, { ballwin: 2 });
assert.equal(first.registered, true);
assert.deepEqual(second.metrics, { goals_for: 0, goals_against: 0, points: 1, clean_sheet: 1 });
assert.equal(second.registered, false);
assert.deepEqual(plan.match_buttons, [{ id: 'ballwin', label: 'Bollvinst' }]);
console.log('PASS: the plan carries its played matches, counted from the events where they were registered');

plan = await call(coach, "select api.save_team_development_kpi($1,1,null,'Avslut per match','st',8,true,'shots')", [season]);
plan = await call(coach, "select api.save_team_development_kpi($1,2,null,'Bollvinster','st',null,true,'button:ballwin')", [season]);
plan = await call(coach, "select api.save_team_development_kpi($1,3,null,'Löpmeter','m',null,true)", [season]);
assert.deepEqual(plan.kpis.map(k => k.source), ['shots', 'button:ballwin', null]);
const [shots, ballWins, manual] = plan.kpis;
plan = await call(coach, "select api.save_team_development_kpi($1,4,$2,'Avslut','st',8,true,'')", [season, shots.id]);
assert.equal(plan.kpis[0].source, null, 'an empty source is by hand');
plan = await call(coach, "select api.save_team_development_kpi($1,5,$2,'Avslut','st',8,true,'shots_on_target')", [season, shots.id]);
assert.equal(plan.kpis[0].source, 'shots_on_target');
await fails(coach, "select api.save_team_development_kpi($1,6,null,'Fel','',null,true,'possession')", [season], /check|violates/);
console.log('PASS: a key figure names its source, a team button included, or none');

plan = await call(coach, "select api.set_team_development_kpi_match_value($1,$2,$3,6,'Räknat på film')", [season, shots.id, resultOnly]);
plan = await call(coach, "select api.set_team_development_kpi_match_value($1,$2,$3,7,'')", [season, shots.id, resultOnly]);
let tied = plan.checkins.filter(c => c.event_id);
assert.equal(tied.length, 1, 'a new value replaces the one set before');
assert.deepEqual([Number(tied[0].value), tied[0].kpi_id, tied[0].checked_on], [7, shots.id, second.played_on]);
plan = await call(coach, "select api.set_team_development_kpi_match_value($1,$2,$3,null,'')", [season, shots.id, resultOnly]);
assert.equal(plan.checkins.filter(c => c.event_id).length, 0, 'no value shows the counted one again');
await fails(coach, "select api.set_team_development_kpi_match_value($1,$2,$3,5,'')", [season, shots.id, upcoming], /not_a_match/);
await fails(coach, "select api.set_team_development_kpi_match_value($1,$2,$3,5,'')", [season, shots.id, elsewhere], /not_a_match/);
await fails(player, "select api.set_team_development_kpi_match_value($1,$2,$3,5,'')", [season, shots.id, live], /not_allowed|not_found/);
// Values by hand without a match, as before.
plan = await call(coach, 'select api.add_team_development_checkin($1,null,$2,$3,null,4200,$4)', [season, manual.id, day(-1), '']);
assert.equal(plan.checkins.find(c => c.kpi_id === manual.id).event_id, null);
void ballWins;
console.log('PASS: a value set by hand for a match replaces the counted one, and can be removed');
