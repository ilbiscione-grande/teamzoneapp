// Team Development Plan, step 3 (2026-10-24): what the leaders share with
// the players, links on goals, the suggestion for an event's preparation,
// and the principles' areas as the Swedish FA's phases.
// node supabase/tests/team_development_sharing.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), player = id(2), outsider = id(3), club = id(10), team = id(20), training = id(30), farTraining = id(31);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${coach}','Anna Tränare'),('${player}',''),('${outsider}','');
create table core.teams(id uuid primary key, club_id uuid); insert into core.teams values ('${team}','${club}');
create table core.person_account_links(profile_id uuid, club_id uuid, state text);
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, starts_at timestamptz);
insert into core.events values ('${training}','${club}','${team}', now() + interval '2 days'),
  ('${farTraining}','${club}','${team}', now() + interval '400 days');
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
-- As the match module made it (20261203090000).
create table core.module_attachments (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references core.clubs(id),
  owner_kind text not null check (owner_kind in ('match_plan')), owner_id uuid not null,
  kind text not null check (kind in ('link')), title text not null, url text,
  visible_to_players boolean not null default false, position integer not null default 0,
  created_by uuid, created_at timestamptz not null default now());
grant usage on schema api, internal, core, auth to authenticated;`);
for (const name of ['20261202090000_module_foundation', '20261209090000_team_development_plan',
  '20261210090000_team_development_principles', '20261211090000_team_development_sharing']) {
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

let plan = await call(coach, "select api.create_team_development_plan($1,'Säsongen',$2,$3,'Ett modigt lag')", [team, day(-30), day(200)]);
const season = plan.id;
plan = await call(coach, "select api.save_team_development_period($1,1,null,'Vår','competition',$2,$3,'Press högt')", [season, day(-30), day(30)]);
const spring = plan.periods[0].id;
plan = await call(coach, "select api.save_team_development_goal($1,2,null,'season',null,'Alla spelar mycket','',null,'open')", [season]);
plan = await call(coach, "select api.save_team_development_goal($1,3,null,'period',$2,'Vinn bollen högt','',null,'open')", [season, spring]);
plan = await call(coach, "select api.save_team_development_goal($1,4,null,'short',null,'Hörnor till derbyt','',$2,'open')", [season, day(10)]);

// The principles' areas are the FA's phases, with the ball and without.
await fails(coach, "select api.save_team_development_principle($1,5,null,'attack','Gammalt område','')", [season], /invalid_input/);
plan = await call(coach, "select api.save_team_development_principle($1,5,null,'regaining','Fem sekunder','')", [season]);
plan = await call(coach, "select api.save_team_development_principle($1,6,null,'build_up','Spela via backlinjen','')", [season]);
assert.deepEqual(plan.principles.map(p => p.area), ['regaining', 'build_up']);

// Nothing is shared at first: the players see nothing.
assert.deepEqual(plan.sharing, { vision: false, periods: false, principles: false, goals: false });
assert.equal(await call(player, 'select api.get_shared_team_development($1)', [team]), null);
await fails(outsider, 'select api.get_shared_team_development($1)', [team], /not_found/);

// Links on goals: https only, at most ten, the shown ones for the players.
const goalId = plan.goals.find(g => g.horizon === 'season').id;
plan = await call(coach, "select api.add_team_development_goal_link($1,$2,'Film','https://example.com/film',true)", [season, goalId]);
plan = await call(coach, "select api.add_team_development_goal_link($1,$2,'Ledarnas','https://example.com/intern',false)", [season, goalId]);
assert.equal(plan.revision, 7, 'links are beside the plan');
assert.deepEqual(plan.goals.find(g => g.id === goalId).links.map(l => [l.title, l.visible]), [['Film', true], ['Ledarnas', false]]);
await fails(coach, "select api.add_team_development_goal_link($1,$2,'Fel','http://example.com',true)", [season, goalId], /invalid_input/);
await fails(player, "select api.add_team_development_goal_link($1,$2,'Spelarens','https://example.com',true)", [season, goalId], /not_found/);

// Sharing per part, on the plan's revision.
plan = await call(coach, 'select api.set_team_development_sharing($1,7,true,true,false,true)', [season]);
assert.deepEqual([plan.sharing.vision, plan.sharing.principles, plan.revision], [true, false, 8]);
await fails(coach, 'select api.set_team_development_sharing($1,7,true,true,true,true)', [season], /stale_revision/);
const shared = await call(player, 'select api.get_shared_team_development($1)', [team]);
assert.equal(shared.vision, 'Ett modigt lag');
assert.deepEqual(shared.periods.map(p => [p.name, p.focus]), [['Vår', 'Press högt']]);
assert.equal(shared.principles, null, 'not shared');
assert.deepEqual(shared.goals.map(g => g.horizon), ['season', 'period'], 'short-term goals stay the leaders\'');
assert.deepEqual(shared.goals[0].links.map(l => l.title), ['Film'], 'only the shown links');
assert.equal(JSON.stringify(shared).includes('checkin'), false, 'no check-ins');

// The suggestion for a training in the period: its focus, principles and goals ahead.
const suggestion = await call(coach, 'select api.get_team_plan_suggestion($1)', [training]);
assert.deepEqual([suggestion.period.name, suggestion.period.focus], ['Vår', 'Press högt']);
assert.deepEqual(suggestion.principles.map(p => p.title), ['Fem sekunder', 'Spela via backlinjen']);
assert.deepEqual(suggestion.goals.map(g => g.title), ['Vinn bollen högt', 'Hörnor till derbyt']);
assert.equal(await call(player, 'select api.get_team_plan_suggestion($1)', [training]), null, 'for those who prepare it');
assert.equal(await call(coach, 'select api.get_team_plan_suggestion($1)', [farTraining]), null, 'outside the season');

// Removing a link; the shown one is gone for the players too.
const film = plan.goals.find(g => g.id === goalId).links.find(l => l.title === 'Film');
plan = await call(coach, 'select api.change_team_development_goal_link($1,$2,null)', [season, film.id]);
assert.deepEqual((await call(player, 'select api.get_shared_team_development($1)', [team])).goals[0].links, []);

console.log('team_development_sharing: ok');
