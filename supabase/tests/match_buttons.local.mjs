// Match module, step 3c (2026-10-23): a team's own Live buttons, a leader's
// Min vy, and a tap counted as a 'kpi' fact that minus voids again.
// node supabase/tests/match_buttons.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), player = id(2), club = id(10), team = id(20), match = id(30);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth; create schema audit;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key); insert into core.profiles values ('${coach}'),('${player}');
create table core.teams(id uuid primary key, club_id uuid, match_format text); insert into core.teams values ('${team}','${club}','7v7');
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, event_type text, title text, state text default 'scheduled',
  starts_at timestamptz, archived_at timestamptz, opponent_name text, home_away text);
insert into core.events values ('${match}','${club}','${team}','match','Match','scheduled', now(), null, 'Aneby SK', 'home');
create table core.match_workspaces(event_id uuid primary key, club_id uuid, team_id uuid, updated_by uuid, period_minutes integer[], state text default 'live');
insert into core.match_workspaces values ('${match}','${club}','${team}',null,'{25,25}','live');
create table core.match_projections(event_id uuid primary key);
create table core.event_match_settings(event_id uuid primary key, period_minutes integer[]);
create function internal.match_format_period_minutes(format text) returns integer[] language sql immutable as $$ select array[45,45] $$;
create table core.match_plans(event_id uuid primary key, revision bigint not null default 0, set_pieces_notes text not null default '',
  tactics_notes text not null default '', key_opponents_notes text not null default '', updated_at timestamptz, updated_by uuid);
create table core.match_facts(id uuid primary key, event_id uuid, minute integer, fact_type text, side text, club_id uuid, detail jsonb,
  source_command_id uuid, created_by uuid, updated_by uuid, state text default 'active', voided_at timestamptz, voided_by uuid,
  void_reason text, fact_revision integer default 1, created_at timestamptz default clock_timestamp(), updated_at timestamptz);
create table audit.match_fact_versions(fact_id uuid, event_id uuid, fact_revision integer, snapshot jsonb, action text, actor_profile_id uuid, reason text);
create table audit.match_commands(command_id uuid primary key, result jsonb);
create function internal.register_match_command(c uuid, e uuid, r bigint, t text, p jsonb) returns boolean language plpgsql security definer set search_path = '' as $$
begin insert into audit.match_commands values (c, null) on conflict do nothing; return found; end $$;
create function internal.ensure_match_workspace(e uuid) returns void language sql as $$ select $$;
create function internal.assert_match_manager(e uuid) returns void language plpgsql as $$
begin if auth.uid() <> '${coach}'::uuid then raise insufficient_privilege using message = 'not_found'; end if; end $$;
create function internal.finish_match_command(c uuid, e uuid, r jsonb) returns jsonb language sql as $$ select r $$;
create table core.club_entitlements(club_id uuid, entitlement_key text, access_mode text, expires_at timestamptz);
create function internal.actor_has_club_access(target uuid) returns boolean language sql stable as $$ select true $$;
create function internal.actor_can_read_event(target uuid) returns boolean language sql stable as $$ select auth.uid() in ('${coach}'::uuid, '${player}'::uuid) $$;
create function internal.actor_has_event_capability(target uuid, cap text) returns boolean language sql stable as $$ select auth.uid() = '${coach}'::uuid $$;
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$ select auth.uid() = '${coach}'::uuid $$;
grant usage on schema api, internal, core, auth, audit to authenticated;`);
for (const name of ['20261202090000_module_foundation', '20261203090000_match_plans', '20261206090000_match_buttons'])
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
const tap = (who, button, delta) => call(who, 'select api.record_match_button(gen_random_uuid(), $1, $2, $3, 12)', [match, button, delta]);

// None yet; the coach may set them, a player sees them but may not.
assert.deepEqual(await call(coach, 'select api.get_match_buttons($1)', [match]), { buttons: [], revision: 0, can_edit: true, my_view: null });
assert.equal((await call(player, 'select api.get_match_buttons($1)', [match])).can_edit, false);
const buttons = [{ id: 'wins', label: ' Brytningar ' }, { id: 'cross', label: 'Inlägg' }];
assert.equal(await call(coach, 'select api.save_match_buttons($1, $2::jsonb, 0)', [match, j(buttons)]), 1);
assert.deepEqual((await call(coach, 'select api.get_match_buttons($1)', [match])).buttons.map(b => b.label), ['Brytningar', 'Inlägg']);
await fails(coach, 'select api.save_match_buttons($1, $2::jsonb, 0)', [match, j(buttons)], /stale_revision/);
await fails(coach, 'select api.save_match_buttons($1, $2::jsonb, 1)', [match, j([{ id: 'a', label: 'A' }, { id: 'a', label: 'B' }])], /invalid_buttons/);
await fails(coach, 'select api.save_match_buttons($1, $2::jsonb, 1)', [match, j([{ id: 'a', label: '' }])], /invalid_buttons/);
await fails(player, 'select api.save_match_buttons($1, $2::jsonb, 1)', [match, j(buttons)], /not_allowed/);

// Min vy is each leader's own, and null shows everything again.
await call(player, 'select api.save_my_match_view($1, $2::jsonb)', [match, j(['shot', 'button:wins'])]);
assert.deepEqual((await call(player, 'select api.get_match_buttons($1)', [match])).my_view, ['shot', 'button:wins']);
assert.equal((await call(coach, 'select api.get_match_buttons($1)', [match])).my_view, null);
await call(player, 'select api.save_my_match_view($1, null)', [match]);
assert.equal((await call(player, 'select api.get_match_buttons($1)', [match])).my_view, null);

// Taps: plus counts, minus voids the latest; only the match's managers, only own buttons.
assert.equal((await tap(coach, 'wins', 1)).value, 1);
assert.equal((await tap(coach, 'wins', 1)).value, 2);
assert.equal((await tap(coach, 'wins', -1)).value, 1);
const facts = (await db.query("select detail, state from core.match_facts where fact_type = 'kpi' order by created_at")).rows;
assert.deepEqual(facts.map(f => [f.detail.label, f.state]), [['Brytningar', 'active'], ['Brytningar', 'voided']]);
await fails(coach, 'select api.record_match_button(gen_random_uuid(), $1, $2, 1, 12)', [match, 'nope'], /invalid_button/);
await fails(player, 'select api.record_match_button(gen_random_uuid(), $1, $2, 1, 12)', [match, 'wins'], /not_found/);
await fails(coach, 'select api.record_match_button(gen_random_uuid(), $1, $2, -1, 12)', [match, 'cross'], /invalid_fact/);
console.log('match buttons: ok');
