// Säsongsplanering (2026-11-22): holidays, school breaks and vacations on
// a row of their own in the season. Added one by one or several at once
// (the suggestions, the same one twice is kept once), changed, removed,
// only by those who edit the plan and only touching the season.
// node supabase/tests/season_plan_calendar_periods.local.mjs
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
  '20270122090000_team_development_blocks', '20270128090000_team_development_match_kpis',
  '20270416090000_season_plan_calendar_periods']) {
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

let plan = await call(coach, "select api.create_team_development_plan($1,'Säsongen 2027','2027-01-01','2027-12-31','')", [team]);
const season = plan.id;
assert.deepEqual(plan.calendar_periods, []);
const save = (who, rev, itemId, kind, name, starts, ends) => call(who,
  'select api.save_team_development_calendar_period($1,$2,$3,$4,$5,$6,$7)', [season, rev, itemId, kind, name, starts, ends]);
const add = (who, rev, items) => call(who,
  'select api.add_team_development_calendar_periods($1,$2,$3::jsonb)', [season, rev, JSON.stringify(items)]);

// One by one; overlapping each other is fine.
plan = await save(coach, plan.revision, null, 'school_break', 'Sportlov', '2027-02-22', '2027-02-28');
plan = await save(coach, plan.revision, null, 'vacation', 'Uppehåll', '2027-02-20', '2027-03-07');
assert.deepEqual(plan.calendar_periods.map(p => [p.kind, p.name, p.starts_on]),
  [['vacation', 'Uppehåll', '2027-02-20'], ['school_break', 'Sportlov', '2027-02-22']]);

// The suggestions: the same one twice is kept once.
const suggested = [
  { kind: 'holiday', name: 'Påskhelgen', starts_on: '2027-03-26', ends_on: '2027-03-29' },
  { kind: 'holiday', name: 'Eid al-fitr', starts_on: '2027-03-10', ends_on: '2027-03-10' },
  { kind: 'school_break', name: 'Sportlov', starts_on: '2027-02-22', ends_on: '2027-02-28' },
];
plan = await add(coach, plan.revision, suggested);
plan = await add(coach, plan.revision, suggested);
assert.equal(plan.calendar_periods.length, 4);
assert.deepEqual(plan.calendar_periods.map(p => p.name), ['Uppehåll', 'Sportlov', 'Eid al-fitr', 'Påskhelgen']);

// Changed and removed; the revision guards each change.
const pause = plan.calendar_periods[0].id;
plan = await save(coach, plan.revision, pause, 'vacation', 'Lagets uppehåll', '2027-02-27', '2027-03-07');
assert.equal(plan.calendar_periods.find(p => p.id === pause).name, 'Lagets uppehåll');
await fails(coach, 'select api.delete_team_development_calendar_period($1,$2,$3)', [season, plan.revision - 1, pause], /stale_revision/);
plan = await call(coach, 'select api.delete_team_development_calendar_period($1,$2,$3)', [season, plan.revision, pause]);
assert.equal(plan.calendar_periods.length, 3);

// Checked: a known kind, a name, at most 121 days, touching the season.
await fails(coach, 'select api.save_team_development_calendar_period($1,$2,null,$3,$4,$5,$6)',
  [season, plan.revision, 'party', 'Fest', '2027-05-01', '2027-05-01'], /invalid_input/);
await fails(coach, 'select api.save_team_development_calendar_period($1,$2,null,$3,$4,$5,$6)',
  [season, plan.revision, 'other', ' ', '2027-05-01', '2027-05-01'], /invalid_input/);
await fails(coach, 'select api.save_team_development_calendar_period($1,$2,null,$3,$4,$5,$6)',
  [season, plan.revision, 'vacation', 'Lång', '2027-01-01', '2027-06-01'], /invalid_input/);
await fails(coach, 'select api.save_team_development_calendar_period($1,$2,null,$3,$4,$5,$6)',
  [season, plan.revision, 'holiday', 'Nyår', '2028-01-01', '2028-01-01'], /outside_season/);
await fails(coach, 'select api.add_team_development_calendar_periods($1,$2,$3::jsonb)',
  [season, plan.revision, '[{"kind":"holiday","name":"Fel","starts_on":"inte","ends_on":"2027-01-01"}]'], /invalid_input/);
await fails(coach, 'select api.add_team_development_calendar_periods($1,$2,$3::jsonb)',
  [season, plan.revision, '[]'], /invalid_input/);

// A stretch reaching into the season is kept; the season moved later only hides it.
plan = await save(coach, plan.revision, null, 'school_break', 'Jullov', '2027-12-20', '2028-01-07');
assert.ok(plan.calendar_periods.some(p => p.name === 'Jullov'));
plan = await call(coach, "select api.save_team_development_plan($1,$2,'Säsongen 2027','2027-01-01','2027-11-30','',null)", [season, plan.revision]);
assert.ok(!plan.calendar_periods.some(p => p.name === 'Jullov'));

// Only those who edit the plan.
await fails(player, 'select api.save_team_development_calendar_period($1,$2,null,$3,$4,$5,$6)',
  [season, plan.revision, 'holiday', 'Nyår', '2027-01-01', '2027-01-01'], /not_found|not_allowed/);
await fails(player, 'select api.delete_team_development_calendar_period($1,$2,$3)',
  [season, plan.revision, plan.calendar_periods[0].id], /not_found|not_allowed/);
await fails(player, 'select * from core.team_development_calendar_periods', [], /permission denied/);

console.log('season plan calendar periods: ok');
