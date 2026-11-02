// Team Development Plan, new design step 7 (2026-11-02): a block's exercise
// suggestions from the club's and TeamZone's libraries, the ones the leaders
// choose, and the day's block's exercises in the suggestion for a session.
// node supabase/tests/team_development_block_exercises.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
// One function as a migration defines it, taken from the file.
const fn = (file, name) => {
  const text = read(file);
  const start = text.indexOf(`create or replace function ${name}(`);
  return text.slice(start, text.indexOf('$$;', start) + 3);
};
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), player = id(2), club = id(10), otherClub = id(11), team = id(20), training = id(30);
const [zoneBuild, zoneDefend, clubBuild, otherClubBuild, hidden, clubPass] = [id(40), id(41), id(42), id(43), id(44), id(45)];
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}'),('${otherClub}');
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${coach}','Anna Tränare'),('${player}','');
create table core.teams(id uuid primary key, club_id uuid); insert into core.teams values ('${team}','${club}');
create table core.person_account_links(profile_id uuid, club_id uuid, state text);
insert into core.person_account_links values ('${coach}','${club}','active');
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, starts_at timestamptz,
  event_type text default 'training', archived_at timestamptz, state text default 'scheduled',
  timezone text default 'Europe/Stockholm', title text default 'Träning');
insert into core.events(id, club_id, owning_team_id, starts_at) values ('${training}','${club}','${team}', now() + interval '1 day');
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
-- Tacticsboard's shared library as its migrations make it.
create table core.tactics_shared_items(id uuid primary key, owner_id uuid, club_id uuid, kind text, title text,
  details jsonb default '{}', document jsonb default '{"boards":[]}', hidden boolean default false,
  version integer default 1, updated_at timestamptz default now());
create table core.tactics_club_picks(club_id uuid, shared_item_id uuid, primary key (club_id, shared_item_id));
-- The coach leads in the club only.
create function internal.tactics_shared_visible(item core.tactics_shared_items) returns boolean language sql stable as $$
  select not item.hidden and (item.club_id is null or (auth.uid() = '${coach}'::uuid and item.club_id = '${club}'::uuid)) $$;
grant usage on schema api, internal, core, auth to authenticated;`);
await db.exec(fn('supabase/migrations/20261221090000_training_pass_library.sql', 'internal.training_pass_json'));
await db.exec(fn('supabase/migrations/20261221090000_training_pass_library.sql', 'internal.training_pass_from_shared'));
for (const name of ['20261202090000_module_foundation', '20261209090000_team_development_plan',
  '20261210090000_team_development_principles', '20261211090000_team_development_sharing',
  '20270122090000_team_development_blocks', '20270128090000_team_development_match_kpis',
  '20270130090000_team_development_block_exercises']) {
  await db.exec(read(`supabase/migrations/${name}.sql`));
}
await db.exec(`insert into core.tactics_shared_items(id, owner_id, club_id, kind, title, details, updated_at) values
  ('${zoneBuild}', null, null, 'exercise', 'Rondo 4 mot 2', '{"phase":"build_up","minutes":12,"part":"main"}', now() - interval '3 days'),
  ('${zoneDefend}', null, null, 'exercise', 'Försvar i linje', '{"phase":"defending"}', now() - interval '2 days'),
  ('${clubBuild}', '${coach}', '${club}', 'exercise', 'Klubbens uppbyggnad', '{"phase":"build_up"}', now() - interval '1 day'),
  ('${otherClubBuild}', null, '${otherClub}', 'exercise', 'Annan klubbs övning', '{"phase":"build_up"}', now()),
  ('${hidden}', null, null, 'exercise', 'Dold', '{"phase":"build_up"}', now()),
  ('${clubPass}', '${coach}', '${club}', 'plan', 'Klubbens pass', '{"theme":"Spelbarhet"}', now());
update core.tactics_shared_items set hidden = true where id = '${hidden}';`);
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

let plan = await call(coach, "select api.create_team_development_plan($1,'Säsongen',$2,$3,'')", [team, day(-60), day(200)]);
const season = plan.id;
plan = await call(coach, "select api.save_team_development_period($1,1,null,'Försäsong','preseason',$2,$3,'')", [season, day(-60), day(60)]);
plan = await call(coach, "select api.save_team_development_principle($1,2,null,'build_up','Spelbarhet','')", [season]);
const playable = plan.principles[0].id;
plan = await call(coach, 'select api.save_team_development_block($1,3,null,$2,$3,$4,$5,$6,$7)',
  [season, plan.periods[0].id, 'Speluppbyggnad', day(-5), day(10), '', [playable]]);
const block = plan.blocks[0].id;

let exercises = await call(coach, 'select api.get_team_development_block_exercises($1,$2)', [season, block]);
assert.deepEqual(exercises.chosen, []);
assert.deepEqual(exercises.matched.map(p => [p.title, p.source]), [['Klubbens uppbyggnad', 'club'], ['Rondo 4 mot 2', 'teamzone']],
  'the club first, then TeamZone; only the phases of the principles, what the reader sees');
assert.deepEqual(exercises.matched[1].exercises[0], { phase: 'build_up', minutes: 12, part: 'main', title: 'Rondo 4 mot 2' });
console.log('PASS: a block suggests the library exercises that train its principles');

exercises = await call(coach, 'select api.add_team_development_block_exercise($1,$2,$3,null,null)', [season, block, zoneBuild]);
exercises = await call(coach, 'select api.add_team_development_block_exercise($1,$2,$3,null,null)', [season, block, clubPass]);
exercises = await call(coach, "select api.add_team_development_block_exercise($1,$2,null,'Egen press','Fyra mot fyra med press')", [season, block]);
exercises = await call(coach, 'select api.add_team_development_block_exercise($1,$2,$3,null,null)', [season, block, zoneBuild]);
assert.deepEqual(exercises.chosen.map(c => [c.pass.title, c.pass.source, c.pass.kind]),
  [['Rondo 4 mot 2', 'teamzone', 'exercise'], ['Klubbens pass', 'club', 'plan'], ['Egen press', 'own', 'exercise']], 'chosen once each, in order');
assert.equal(exercises.chosen[2].pass.exercises[0].organisation, 'Fyra mot fyra med press');
assert.deepEqual(exercises.matched.map(p => p.title), ['Klubbens uppbyggnad'], 'a chosen one is not suggested again');
await fails(coach, 'select api.add_team_development_block_exercise($1,$2,$3,null,null)', [season, block, hidden], /not_found/);
await fails(coach, 'select api.add_team_development_block_exercise($1,$2,$3,null,null)', [season, block, otherClubBuild], /not_found/);
await fails(coach, "select api.add_team_development_block_exercise($1,$2,null,'x','')", [season, block], /invalid_input/);
await fails(player, "select api.add_team_development_block_exercise($1,$2,null,'Spelarens','')", [season, block], /not_allowed|not_found/);
console.log('PASS: the leaders choose exercises from the library they see, or write their own');

const suggestion = await call(coach, 'select api.get_team_plan_suggestion($1)', [training]);
assert.deepEqual(suggestion.exercises.chosen.map(c => c.pass.title), ['Rondo 4 mot 2', 'Klubbens pass', 'Egen press']);
assert.deepEqual(suggestion.exercises.matched.map(p => p.title), ['Klubbens uppbyggnad']);
console.log('PASS: the suggestion for a session carries the block\'s exercises');

exercises = await call(coach, 'select api.delete_team_development_block_exercise($1,$2)', [season, exercises.chosen[0].id]);
assert.deepEqual(exercises.chosen.map(c => c.pass.title), ['Klubbens pass', 'Egen press']);
assert.deepEqual(exercises.matched.map(p => p.title), ['Klubbens uppbyggnad', 'Rondo 4 mot 2']);
await fails(coach, 'select api.delete_team_development_block_exercise($1,$2)', [season, id(99)], /not_found/);
console.log('PASS: a chosen exercise is taken away, and suggested again when it matches');
