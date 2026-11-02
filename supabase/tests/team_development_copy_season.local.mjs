// Team Development Plan: a new season starts from an earlier one, with the
// game model's principles and the key figures (2026-11-02).
// node supabase/tests/team_development_copy_season.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), player = id(2), club = id(10), team = id(20), otherTeam = id(21);
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
create table core.match_workspaces(event_id uuid primary key, state text);
create table core.match_projections(event_id uuid primary key, score_us integer, score_opponent integer);
create table core.match_facts(id uuid primary key default gen_random_uuid(), event_id uuid, fact_type text, side text,
  detail jsonb default '{}', state text default 'active');
create table core.team_match_buttons(team_id uuid primary key, buttons jsonb);
grant usage on schema api, internal, core, auth to authenticated;`);
for (const name of ['20261202090000_module_foundation', '20261209090000_team_development_plan',
  '20261210090000_team_development_principles', '20261211090000_team_development_sharing',
  '20270122090000_team_development_blocks', '20270128090000_team_development_match_kpis',
  '20270129090000_team_development_copy_season']) {
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

let last = await call(coach, "select api.create_team_development_plan($1,'Säsong 2026','2026-01-01','2026-12-31','Modigt')", [team]);
last = await call(coach, "select api.save_team_development_principle($1,1,null,'build_up','Spelbarhet','Alltid två val')", [last.id]);
last = await call(coach, "select api.save_team_development_principle($1,2,null,'regaining','Fem sekunder','')", [last.id]);
last = await call(coach, "select api.save_team_development_kpi($1,3,null,'Avslut','st',8,true,'shots')", [last.id]);
last = await call(coach, "select api.add_team_development_checkin($1,null,$2,'2026-03-01',null,7,'')", [last.id, last.kpis[0].id]);

let next = await call(coach, "select api.create_team_development_plan($1,'Säsong 2027','2027-01-01','2027-12-31','')", [team]);
next = await call(coach, "select api.save_team_development_principle($1,1,null,'build_up','spelbarhet','Redan här')", [next.id]);
next = await call(coach, 'select api.copy_team_development_season($1,2,$2,true,true)', [next.id, last.id]);
assert.deepEqual(next.principles.map(p => [p.area, p.title, p.description]),
  [['build_up', 'spelbarhet', 'Redan här'], ['regaining', 'Fem sekunder', '']], 'kept, and the same principle not twice');
assert.deepEqual(next.kpis.map(k => [k.title, Number(k.target), k.source]), [['Avslut', 8, 'shots']]);
assert.equal(next.checkins.length, 0, 'the values stay in their season');
assert.equal(last.principles.length, 2);
console.log('PASS: a new season takes the principles and key figures of the earlier one, without their values');

next = await call(coach, 'select api.copy_team_development_season($1,3,$2,false,false)', [next.id, last.id]);
assert.equal(next.revision, 4);
await fails(coach, 'select api.copy_team_development_season($1,3,$2,true,true)', [next.id, last.id], /stale_revision/);
await fails(coach, 'select api.copy_team_development_season($1,4,$1,true,true)', [next.id], /invalid_input/);
const other = await call(coach, "select api.create_team_development_plan($1,'Annat lag','2027-01-01','2027-12-31','')", [otherTeam]);
await fails(coach, 'select api.copy_team_development_season($1,4,$2,true,true)', [next.id, other.id], /invalid_input/);
await fails(player, 'select api.copy_team_development_season($1,4,$2,true,true)', [next.id, last.id], /not_allowed|not_found/);
console.log('PASS: only from a season of the same team, by those who plan it');
