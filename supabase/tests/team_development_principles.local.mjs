// Team Development Plan, step 2 (2026-10-24): principles, key figures,
// check-ins on goals and key figures, the check-in interval and the
// assistant's goals due for a check-in.
// node supabase/tests/team_development_principles.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), player = id(2), club = id(10), team = id(20);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${coach}','Anna Tränare'),('${player}','');
create table core.teams(id uuid primary key, club_id uuid); insert into core.teams values ('${team}','${club}');
create table core.person_account_links(profile_id uuid, club_id uuid, state text);
insert into core.person_account_links values ('${coach}','${club}','active'),('${player}','${club}','active');
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
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable
  as $$ select auth.uid() = '${coach}'::uuid and cap = 'development.manage' $$;
grant usage on schema api, internal, core, auth to authenticated;`);
for (const name of ['20261202090000_module_foundation', '20261209090000_team_development_plan',
  '20261210090000_team_development_principles']) await db.exec(read(`supabase/migrations/${name}.sql`));
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

let plan = await call(coach, "select api.create_team_development_plan($1,'Säsongen',$2,$3,'')", [team, day(-60), day(200)]);
const season = plan.id;
assert.equal(plan.checkin_every_days, null);

// The check-in interval is set with the season: one to four weeks, or never.
plan = await call(coach, "select api.save_team_development_plan($1,1,'Säsongen',$2,$3,'',14)", [season, day(-60), day(200)]);
assert.deepEqual([plan.checkin_every_days, plan.revision], [14, 2]);
await fails(coach, "select api.save_team_development_plan($1,2,'Säsongen',$2,$3,'',10)", [season, day(-60), day(200)], /invalid_input/);

// Principles per area and key figures change the plan on its revision.
plan = await call(coach, "select api.save_team_development_principle($1,2,null,'defence','Vinn bollen tillbaka inom fem sekunder','')", [season]);
plan = await call(coach, "select api.save_team_development_principle($1,3,null,'attack','Spela framåt när det går','Hellre en djupledsboll')", [season]);
assert.deepEqual(plan.principles.map(p => p.area), ['defence', 'attack']);
await fails(coach, "select api.save_team_development_principle($1,4,null,'offside','Fel','')", [season], /invalid_input/);
plan = await call(coach, "select api.save_team_development_kpi($1,4,null,'Avslut per match','st',12,true)", [season]);
plan = await call(coach, "select api.save_team_development_kpi($1,5,null,'Insläppta mål','st',1,false)", [season]);
assert.deepEqual(plan.kpis.map(k => [k.title, Number(k.target), k.higher_is_better]), [['Avslut per match', 12, true], ['Insläppta mål', 1, false]]);
await fails(coach, "select api.save_team_development_kpi($1,5,null,'Gammal','',null,true)", [season], /stale_revision/);
const [shots] = plan.kpis;

// Goals for the check-ins: one of the season, one long ago changed.
plan = await call(coach, "select api.save_team_development_goal($1,6,null,'season',null,'Alla spelar mycket','',null,'open')", [season]);
const goal = plan.goals[0].id;
assert.equal(plan.revision, 7);

// Check-ins never move the revision: a leader editing meanwhile is not made stale.
plan = await call(coach, "select api.add_team_development_checkin($1,$2,null,$3,'at_risk',null,'Några får för lite tid')", [season, goal, day(0)]);
plan = await call(coach, 'select api.add_team_development_checkin($1,null,$2,$3,null,9,$4)', [season, shots.id, day(-7), '']);
plan = await call(coach, 'select api.add_team_development_checkin($1,null,$2,$3,null,14,$4)', [season, shots.id, day(0), '']);
assert.equal(plan.revision, 7);
assert.deepEqual(plan.checkins.filter(c => c.kpi_id).map(c => Number(c.value)), [14, 9], 'newest first');
assert.equal(plan.checkins.find(c => c.goal_id).created_by, 'Anna Tränare');
await fails(coach, "select api.add_team_development_checkin($1,$2,null,$3,'fine',null,'')", [season, goal, day(0)], /invalid_input/);
await fails(coach, "select api.add_team_development_checkin($1,$2,null,$3,null,3,'')", [season, goal, day(0)], /invalid_input/);
await fails(coach, "select api.add_team_development_checkin($1,$2,null,$3,'on_track',null,'')", [season, goal, day(5)], /outside_season/);
await fails(player, "select api.add_team_development_checkin($1,$2,null,$3,'on_track',null,'')", [season, goal, day(0)], /not_found/);
plan = await call(coach, "select api.save_team_development_goal($1,7,$2,'season',null,'Alla spelar mycket','',null,'open')", [season, goal]);

// Due for a check-in: open goals whose last check-in is an interval ago.
const due = () => call(coach, 'select api.list_my_team_development_checkins_due()');
assert.deepEqual(await due(), [], 'checked today');
await db.exec(`update core.team_development_checkins set checked_on = current_date - 20 where goal_id = '${goal}'`);
const [row] = await due();
assert.deepEqual([row.team_id, row.due, row.title], [team, 1, 'Säsongen']);
assert.deepEqual(await call(player, 'select api.list_my_team_development_checkins_due()'), []);
plan = await call(coach, "select api.add_team_development_checkin($1,$2,null,$3,'on_track',null,'')", [season, goal, day(0)]);
assert.deepEqual(await due(), []);

// Removing a check-in, a key figure (with its values) and a principle.
plan = await call(coach, 'select api.delete_team_development_checkin($1,$2)', [season, plan.checkins.find(c => c.goal_id).id]);
plan = await call(coach, 'select api.delete_team_development_kpi($1,$2,$3)', [season, plan.revision, shots.id]);
assert.equal(plan.checkins.filter(c => c.kpi_id).length, 0);
plan = await call(coach, 'select api.delete_team_development_principle($1,$2,$3)', [season, plan.revision, plan.principles[0].id]);
assert.deepEqual(plan.principles.map(p => p.area), ['attack']);

console.log('team_development_principles: ok');
