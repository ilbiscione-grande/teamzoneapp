// Match module, step 2 (2026-10-23): the line-up on the pitch, its places
// and substitution plan, kept by the line-up under Förberedelser.
// node supabase/tests/match_lineup.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), player = id(2), club = id(10), team = id(20), match = id(30);
const [keeper, back, striker, sub] = [id(41), id(42), id(43), id(44)], stranger = id(49);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key); insert into core.profiles values ('${coach}'),('${player}');
create table core.teams(id uuid primary key, club_id uuid, match_format text); insert into core.teams values ('${team}','${club}','7v7');
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, event_type text, title text, state text default 'scheduled',
  starts_at timestamptz, archived_at timestamptz, opponent_name text, home_away text);
insert into core.events values ('${match}','${club}','${team}','match','Match','scheduled', now() + interval '3 days', null, 'Aneby SK', 'home');
create table core.club_people(id uuid primary key, club_id uuid, display_name text, person_id uuid);
insert into core.club_people values ('${keeper}','${club}','Mia'),('${back}','${club}','Ali'),('${striker}','${club}','Sam'),('${sub}','${club}','Noa'),('${stranger}', gen_random_uuid(), 'X');
create table core.team_person_details(club_id uuid, team_id uuid, club_person_id uuid, positions text[] default '{}', main_position text, jersey_number smallint);
insert into core.team_person_details values ('${club}','${team}','${keeper}','{goalkeeper}','goalkeeper',1),('${club}','${team}','${striker}','{forward}','forward',9);
create table core.assignments(club_person_id uuid, team_id uuid, role_package text, state text);
insert into core.assignments values ('${keeper}','${team}','player','active'),('${striker}','${team}','player','active'),('${coach}','${team}','leader','active');
create table core.event_lineups(event_id uuid primary key, club_id uuid not null, formation text, starters jsonb not null default '[]',
  substitutes jsonb not null default '[]', published boolean not null default false, revision bigint not null default 1,
  updated_by uuid, updated_at timestamptz not null default now());
create table core.match_workspaces(event_id uuid primary key, club_id uuid, team_id uuid, updated_by uuid, period_minutes integer[]);
create table core.match_projections(event_id uuid primary key);
create table core.event_match_settings(event_id uuid primary key, period_minutes integer[]);
create function internal.match_format_period_minutes(format text) returns integer[] language sql immutable as $$ select array[45,45] $$;
create table core.match_plans(event_id uuid primary key, revision bigint not null default 0, set_pieces_notes text not null default '',
  tactics_notes text not null default '', key_opponents_notes text not null default '', updated_at timestamptz, updated_by uuid);
create table core.club_entitlements(club_id uuid, entitlement_key text, access_mode text, expires_at timestamptz);
create function internal.actor_has_club_access(target uuid) returns boolean language sql stable as $$ select true $$;
create function internal.actor_can_read_event(target uuid) returns boolean language sql stable as $$ select auth.uid() in ('${coach}'::uuid, '${player}'::uuid) $$;
create function internal.actor_has_event_capability(target uuid, cap text) returns boolean language sql stable as $$ select auth.uid() = '${coach}'::uuid $$;
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$ select auth.uid() = '${coach}'::uuid $$;
create function internal.actor_can_manage_squad(target uuid) returns boolean language sql stable as $$ select auth.uid() = '${coach}'::uuid $$;
grant usage on schema api, internal, core, auth to authenticated;`);
for (const name of ['20261202090000_module_foundation', '20261203090000_match_plans', '20261204090000_match_lineup', '20261204100000_match_lineup_fix'])
  await db.exec(read(`supabase/migrations/${name}.sql`));
await db.exec('begin');
const call = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  await db.exec('set role authenticated');
  const rows = (await db.query(sql, params)).rows;
  await db.exec('reset role');
  return Object.values(rows[0] ?? {})[0];
};
const fails = async (who, sql, params, pattern) => {
  await db.exec('savepoint s');
  await assert.rejects(call(who, sql, params), pattern);
  await db.exec('rollback to s');
};
const j = value => JSON.stringify(value);
const saveModule = (revision, starters, subs, plan, published = false) => call(coach,
  'select api.save_match_lineup($1,$2,$3,$4::jsonb,$5::jsonb,$6::jsonb,$7)', [match, revision, '2-3-1', j(starters), j(subs), j(plan), published]);
const starters = [
  { person_id: keeper, slot: 'GK', position: 'MV', x: 0.06, y: 0.5 },
  { person_id: back, slot: 'D1', position: 'VB', x: 0.25, y: 0.3 },
  { person_id: striker, slot: 'F1', position: 'ANF', x: 0.85, y: 0.5 },
];
const plan = [{ id: 'a', minute: 30, out_id: striker, in_id: sub, note: 'om vi leder' }];

// Empty first: the coach gets the format and the team's numbers; a player nothing.
const empty = await call(coach, 'select api.get_match_lineup($1)', [match]);
assert.deepEqual([empty.can_edit, empty.revision, empty.match_format, empty.players.length], [true, 0, '7v7', 2]);
assert.equal(await call(player, 'select api.get_match_lineup($1)', [match]), null);

// Saved with places and a plan; the numbers come with the players.
assert.equal(await saveModule(0, starters, [{ person_id: sub }], plan), 1);
const saved = await call(coach, 'select api.get_match_lineup($1)', [match]);
assert.deepEqual(saved.starters.map(s => [s.name, s.slot, s.x, s.number]), [['Mia', 'GK', 0.06, 1], ['Ali', 'D1', 0.25, null], ['Sam', 'F1', 0.85, 9]]);
assert.deepEqual(saved.substitution_plan.map(s => [s.minute, s.out_name, s.in_name, s.note]), [[30, 'Sam', 'Noa', 'om vi leder']]);

// Wrong input: a place off the pitch, a substitution outside the line-up, someone from another club, a stale revision, a player.
await fails(coach, 'select api.save_match_lineup($1,1,$2,$3::jsonb,$4::jsonb,$5::jsonb,false)', [match, '2-3-1', j([{ person_id: keeper, slot: 'GK', x: 1.4, y: 0.5 }]), '[]', '[]'], /invalid_input/);
await fails(coach, 'select api.save_match_lineup($1,1,$2,$3::jsonb,$4::jsonb,$5::jsonb,false)', [match, '2-3-1', j(starters), '[]', j(plan)], /invalid_substitution/);
await fails(coach, 'select api.save_match_lineup($1,1,$2,$3::jsonb,$4::jsonb,$5::jsonb,false)', [match, '2-3-1', j([{ person_id: stranger }]), '[]', '[]'], /invalid_input/);
await fails(coach, 'select api.save_match_lineup($1,0,$2,$3::jsonb,$4::jsonb,$5::jsonb,false)', [match, '2-3-1', j(starters), '[]', '[]'], /stale_revision/);
await fails(player, 'select api.save_match_lineup($1,1,$2,$3::jsonb,$4::jsonb,$5::jsonb,false)', [match, '2-3-1', '[]', '[]', '[]'], /not_allowed/);

// The line-up under Förberedelser: a kept starter keeps its place, the plan stays while its players do.
await call(coach, 'select internal.save_event_lineup_for_actor($1,$2,$3::jsonb,$4::jsonb,true,1)',
  [match, '2-3-1', j([{ person_id: keeper, position: 'MV' }, { person_id: striker, position: 'ANF' }]), j([{ person_id: sub }])]);
const kept = await call(player, 'select api.get_match_lineup($1)', [match]);
assert.deepEqual([kept.can_edit, kept.players.length], [false, 0], 'players see it published, without the team details');
assert.deepEqual(kept.starters.map(s => [s.name, s.slot, s.y]), [['Mia', 'GK', 0.5], ['Sam', 'F1', 0.5]]);
assert.equal(kept.substitution_plan.length, 0, 'the plan is the leaders’');
assert.equal((await call(coach, 'select api.get_match_lineup($1)', [match])).substitution_plan.length, 1);
await call(coach, 'select internal.save_event_lineup_for_actor($1,null,$2::jsonb,$3::jsonb,true,2)', [match, j([{ person_id: keeper }]), '[]']);
assert.equal((await call(coach, 'select api.get_match_lineup($1)', [match])).substitution_plan.length, 0, 'the plan drops what left the line-up');
console.log('match lineup: ok');
