// Team Development Plan, step 1 (2026-10-24): the season, its periods and
// the goals of the season, a period and the short term; revisions, limits
// and who may read and change the plan.
// node supabase/tests/team_development_plan.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), player = id(2), outsider = id(3), club = id(10), team = id(20), otherTeam = id(21);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${coach}','Anna Tränare'),('${player}',''),('${outsider}','');
create table core.teams(id uuid primary key, club_id uuid); insert into core.teams values ('${team}','${club}'),('${otherTeam}','${club}');
-- core.development_plans as S08 made it.
create table core.development_plans (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references core.clubs(id), team_id uuid not null,
  subject_club_person_id uuid, plan_type text not null check (plan_type in ('team', 'player')),
  title text not null check (length(btrim(title)) between 2 and 120),
  focus text not null default '' check (length(focus) <= 4000),
  state text not null default 'draft' check (state in ('draft', 'active', 'completed', 'archived')),
  created_at timestamptz not null default now(), created_by uuid not null references core.profiles(id),
  updated_at timestamptz not null default now(), updated_by uuid not null references core.profiles(id),
  revision bigint not null default 1 check (revision > 0), unique (id, club_id));
insert into core.development_plans (club_id, team_id, plan_type, title, created_by, updated_by)
  values ('${club}', '${team}', 'team', 'Enkel plan', '${coach}', '${coach}');
create table core.club_entitlements(club_id uuid, entitlement_key text, access_mode text, expires_at timestamptz);
create function internal.actor_has_club_access(target uuid) returns boolean language sql stable as $$ select auth.uid() <> '${outsider}'::uuid $$;
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable
  as $$ select auth.uid() = '${coach}'::uuid and cap = 'development.manage' $$;
grant usage on schema api, internal, core, auth to authenticated;`);
for (const name of ['20261202090000_module_foundation', '20261209090000_team_development_plan']) await db.exec(read(`supabase/migrations/${name}.sql`));
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
const get = (who, plan = null) => call(who, 'select api.get_team_development($1,$2)', [team, plan]);

// No season yet: the coach may start one; the simple plan of the built-in app is not a season.
const empty = await get(coach);
assert.deepEqual([empty.can_edit, empty.seasons, empty.plan], [true, [], null]);
await fails(player, 'select api.get_team_development($1,null)', [team], /not_found/);
await fails(outsider, 'select api.get_team_development($1,null)', [team], /not_found/);

const create = (who, title, starts, ends) => call(who, "select api.create_team_development_plan($1,$2,$3,$4,'Ett modigt, spelande lag')", [team, title, starts, ends]);
const year = new Date().getFullYear();
const season = await create(coach, `Säsong ${year}`, `${year}-01-01`, `${year}-12-31`);
assert.deepEqual([season.revision, season.vision, season.updated_by, season.periods, season.goals], [1, 'Ett modigt, spelande lag', 'Anna Tränare', [], []]);
await fails(coach, "select api.create_team_development_plan($1,'Krock',$2,$3,'')", [team, `${year}-06-01`, `${year + 1}-05-31`], /overlapping_season/);
await fails(coach, "select api.create_team_development_plan($1,'Kort',$2,$3,'')", [team, `${year + 1}-01-01`, `${year + 1}-01-10`], /invalid_input/);
await fails(player, "select api.create_team_development_plan($1,'Spelarens',$2,$3,'')", [team, `${year + 1}-01-01`, `${year + 1}-12-31`], /not_found/);
const next = await create(coach, `Säsong ${year + 1}`, `${year + 1}-01-01`, `${year + 1}-12-31`);

// Today's season is shown first; another by its id; the seasons newest first.
const shown = await get(coach);
assert.equal(shown.plan.id, season.id);
assert.deepEqual(shown.seasons.map(s => s.title), [`Säsong ${year + 1}`, `Säsong ${year}`]);
assert.equal((await get(coach, next.id)).plan.id, next.id);

// Periods: inside the season, never overlapping, on the revision read.
const period = (rev, periodId, name, phase, starts, ends, focus = '') => call(coach,
  'select api.save_team_development_period($1,$2,$3,$4,$5,$6,$7,$8)', [season.id, rev, periodId, name, phase, starts, ends, focus]);
let plan = await period(1, null, 'Försäsong', 'preseason', `${year}-01-01`, `${year}-03-31`, 'Grundspel och kondition');
assert.deepEqual([plan.revision, plan.periods.length, plan.periods[0].focus], [2, 1, 'Grundspel och kondition']);
await fails(coach, 'select api.save_team_development_period($1,1,null,$2,$3,$4,$5,$6)', [season.id, 'Gammal', 'other', `${year}-04-01`, `${year}-04-30`, ''], /stale_revision/);
await fails(coach, 'select api.save_team_development_period($1,2,null,$2,$3,$4,$5,$6)', [season.id, 'Krock', 'competition', `${year}-03-15`, `${year}-05-31`, ''], /overlapping_period/);
await fails(coach, 'select api.save_team_development_period($1,2,null,$2,$3,$4,$5,$6)', [season.id, 'Utanför', 'competition', `${year}-12-01`, `${year + 1}-01-31`, ''], /outside_season/);
await fails(coach, 'select api.save_team_development_period($1,2,null,$2,$3,$4,$5,$6)', [season.id, 'Fel fas', 'playoffs', `${year}-04-01`, `${year}-04-30`, ''], /invalid_input/);
plan = await period(2, null, 'Tävling del 1', 'competition', `${year}-04-01`, `${year}-06-30`);
const [preseason, spring] = plan.periods;
plan = await period(3, preseason.id, 'Försäsong', 'preseason', `${year}-01-08`, `${year}-03-31`, 'Grundspel');
assert.deepEqual([plan.revision, plan.periods[0].starts_on, plan.periods[0].focus], [4, `${year}-01-08`, 'Grundspel']);

// Goals: the season's, a period's, and short-term ones with a date in the season.
const goal = (rev, goalId, horizon, periodId, title, targetOn = null, state = 'open') => call(coach,
  "select api.save_team_development_goal($1,$2,$3,$4,$5,$6,'',$7,$8)", [season.id, rev, goalId, horizon, periodId, title, targetOn, state]);
plan = await goal(4, null, 'season', null, 'Alla spelar minst 40 procent');
plan = await goal(5, null, 'period', spring.id, 'Vinna bollen inom fem sekunder');
plan = await goal(6, null, 'short', null, 'Fasta situationer inför derbyt', `${year}-05-10`);
assert.deepEqual(plan.goals.map(g => g.horizon), ['season', 'period', 'short']);
assert.equal(plan.goals[0].updated_by, 'Anna Tränare');
await fails(coach, "select api.save_team_development_goal($1,7,null,'period',null,'Utan period','',null,'open')", [season.id], /invalid_input/);
await fails(coach, "select api.save_team_development_goal($1,7,null,'short',null,'Utan datum','',null,'open')", [season.id], /invalid_input/);
await fails(coach, "select api.save_team_development_goal($1,7,null,'short',null,'Nästa år','',$2,'open')", [season.id, `${year + 1}-02-01`], /outside_season/);
await fails(coach, "select api.save_team_development_goal($1,7,null,'period',$2,'Fel plan','',null,'open')", [next.id, spring.id], /stale_revision|not_found/);
plan = await goal(7, plan.goals[0].id, 'season', null, 'Alla spelar minst 40 procent', null, 'achieved');
assert.equal(plan.goals[0].state, 'achieved');

// The season cannot shrink past its periods and dated goals.
await fails(coach, "select api.save_team_development_plan($1,8,'Kortare',$2,$3,'')", [season.id, `${year}-02-01`, `${year}-12-31`], /outside_season/);
plan = await call(coach, "select api.save_team_development_plan($1,8,'Säsongen',$2,$3,'Ny vision')", [season.id, `${year}-01-01`, `${year}-12-31`]);
assert.deepEqual([plan.title, plan.vision, plan.revision], ['Säsongen', 'Ny vision', 9]);

// A period goes with its own goals; goals are removed one by one.
plan = await call(coach, 'select api.delete_team_development_period($1,9,$2)', [season.id, spring.id]);
assert.deepEqual([plan.periods.length, plan.goals.map(g => g.horizon)], [1, ['season', 'short']]);
plan = await call(coach, 'select api.delete_team_development_goal($1,10,$2)', [season.id, plan.goals[1].id]);
assert.deepEqual(plan.goals.map(g => g.horizon), ['season']);
await fails(player, 'select api.delete_team_development_goal($1,11,$2)', [season.id, plan.goals[0].id], /not_found/);

// A club whose module ended reads its plan but cannot change it.
await db.exec(`update core.module_catalog set beta_open = false where key = 'module.team_development';
  insert into core.club_entitlements values ('${club}', 'module.team_development', 'read_only', null);`);
assert.equal((await get(coach)).can_edit, false);
await fails(coach, 'select api.delete_team_development_goal($1,11,$2)', [season.id, plan.goals[0].id], /not_allowed/);
// Without the module at all, there is no plan to read.
await db.exec(`delete from core.club_entitlements`);
await fails(coach, 'select api.get_team_development($1,null)', [team], /not_found/);

console.log('team_development_plan: ok');
