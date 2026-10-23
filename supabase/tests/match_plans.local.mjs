// Match module, step 1 (2026-10-23): the match plan, what players see of
// it, its links, the module's match list, and the module's access.
// node supabase/tests/match_plans.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), player = id(2), outsider = id(3), club = id(10), team = id(20);
const match = id(30), training = id(31), oldMatch = id(32);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key); insert into core.profiles values ('${coach}'),('${player}'),('${outsider}');
create table core.teams(id uuid primary key, club_id uuid, match_format text); insert into core.teams values ('${team}','${club}','11v11');
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, event_type text, title text, state text default 'scheduled',
  starts_at timestamptz, archived_at timestamptz, opponent_name text, home_away text);
insert into core.events values
  ('${match}','${club}','${team}','match','Match mot Aneby','scheduled', now() + interval '3 days', null, 'Aneby SK', 'home'),
  ('${training}','${club}','${team}','training','Träning','scheduled', now() + interval '1 day', null, null, null),
  ('${oldMatch}','${club}','${team}','match','Gammal','scheduled', now() - interval '60 days', null, 'Tranås', 'away');
create table core.event_lineups(event_id uuid primary key, published boolean);
-- Match Space v2 (S07) as far as the plan needs it.
create table core.match_workspaces(event_id uuid primary key, club_id uuid, team_id uuid, updated_by uuid, period_minutes integer[]);
create table core.match_projections(event_id uuid primary key);
create table core.event_match_settings(event_id uuid primary key, period_minutes integer[]);
create function internal.match_format_period_minutes(format text) returns integer[] language sql immutable as $$ select array[45,45] $$;
create table core.match_plans(event_id uuid primary key references core.match_workspaces(event_id) on delete cascade,
  revision bigint not null default 0, formation text, starting_xi jsonb not null default '[]', substitution_checklist jsonb not null default '[]',
  set_pieces_notes text not null default '', tactics_notes text not null default '', match_kpis text not null default '',
  key_opponents_notes text not null default '', kpi_review text not null default '', updated_at timestamptz not null default now(), updated_by uuid);
insert into core.event_lineups values ('${match}', false);
create table core.club_entitlements(club_id uuid, entitlement_key text, access_mode text, expires_at timestamptz);
create function internal.actor_has_club_access(target uuid) returns boolean language sql stable as $$ select auth.uid() <> '${outsider}'::uuid $$;
create function internal.actor_can_read_event(target uuid) returns boolean language sql stable as $$ select auth.uid() in ('${coach}'::uuid, '${player}'::uuid) $$;
create function internal.actor_has_event_capability(target uuid, cap text) returns boolean language sql stable as $$ select auth.uid() = '${coach}'::uuid and cap = 'match.plan' $$;
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$ select auth.uid() = '${coach}'::uuid and cap = 'match.plan' $$;
grant usage on schema api, internal, core, auth to authenticated;`);
for (const name of ['20261202090000_module_foundation', '20261203090000_match_plans']) await db.exec(read(`supabase/migrations/${name}.sql`));
await db.exec('begin');
const call = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  await db.exec('set role authenticated');
  const rows = await db.query(sql, params).then(result => result.rows, error => { throw error; }).finally(() => {});
  await db.exec('reset role');
  return Object.values(rows[0] ?? {})[0];
};
const fails = async (who, sql, params, pattern) => {
  await db.exec('savepoint s');
  await assert.rejects(call(who, sql, params), pattern);
  await db.exec('rollback to s');
};
const save = (who, revision, published, opponentVisible = false) => call(who,
  "select api.save_match_plan($1,$2,'Hög press','Hörnor: zon','Aneby spelar långt; 9:an farlig',true,true,$3,$4)", [match, revision, opponentVisible, published]);

// No plan yet: the coach gets an empty one to fill in, a player nothing.
const empty = await call(coach, 'select api.get_match_plan($1)', [match]);
assert.deepEqual([empty.can_edit, empty.revision, empty.opponent_name, empty.sections.opponent.visible], [true, 0, 'Aneby SK', false]);
assert.equal(await call(player, 'select api.get_match_plan($1)', [match]), null);
await fails(outsider, 'select api.get_match_plan($1)', [match], /not_found/);
await fails(coach, 'select api.get_match_plan($1)', [training], /not_found/);

// Saving: the coach alone, with the revision read; the match's v2 workspace is made with the plan.
assert.equal(await save(coach, 0, false), 1);
assert.equal((await db.query('select count(*)::int n from core.match_workspaces where event_id = $1', [match])).rows[0].n, 1);
assert.equal((await db.query('select tactics_notes from core.match_plans where event_id = $1', [match])).rows[0].tactics_notes, 'Hög press', 'the v2 plan row');
await fails(coach, "select api.save_match_plan($1,0,'x','','',true,true,false,false)", [match], /stale_revision/);
await fails(player, "select api.save_match_plan($1,1,'x','','',true,true,false,false)", [match], /not_allowed/);
assert.equal(await call(player, 'select api.get_match_plan($1)', [match]), null, 'a draft is the coach’s');

// Published: the players see the shown parts; the opponent stays hidden unless shown.
assert.equal(await save(coach, 1, true), 2);
const seen = await call(player, 'select api.get_match_plan($1)', [match]);
assert.deepEqual([seen.can_edit, seen.sections.tactics.text, seen.sections.set_pieces.text, seen.sections.opponent], [false, 'Hög press', 'Hörnor: zon', null]);
await save(coach, 2, true, true);
assert.equal((await call(player, 'select api.get_match_plan($1)', [match])).sections.opponent.text, 'Aneby spelar långt; 9:an farlig');

// Links: https only, shown to the players or not, removed.
const video = await call(coach, "select api.add_match_plan_link($1,'Motståndarens senaste match','https://video.example/abc',false)", [match]);
await call(coach, "select api.add_match_plan_link($1,'Hörnvarianter','https://docs.example/h',true)", [match]);
await fails(coach, "select api.add_match_plan_link($1,'Osäker','http://x.example',true)", [match], /invalid_link/);
await fails(player, "select api.add_match_plan_link($1,'Min','https://x.example',true)", [match], /not_allowed/);
assert.deepEqual((await call(player, 'select api.get_match_plan($1)', [match])).links.map(l => l.title), ['Hörnvarianter']);
await call(coach, 'select api.change_match_plan_link($1,true)', [video.id]);
assert.equal((await call(player, 'select api.get_match_plan($1)', [match])).links.length, 2);
await call(coach, 'select api.change_match_plan_link($1,null)', [video.id]);
assert.deepEqual((await call(coach, 'select api.get_match_plan($1)', [match])).links.map(l => l.title), ['Hörnvarianter']);

// The module's match list: the team's matches in the period with how far they are prepared.
const list = await call(coach, "select api.list_module_matches($1, now() - interval '7 days', now() + interval '30 days')", [team]);
assert.deepEqual(list.map(m => [m.title, m.plan, m.lineup]), [['Match mot Aneby', 'published', 'draft']]);
await fails(player, "select api.list_module_matches($1, now(), now() + interval '1 day')", [team], /not_found/);
await fails(coach, "select api.list_module_matches($1, now(), now() - interval '1 day')", [team], /invalid_period/);

// Without the module: nothing to read; after a purchase ended, readable but not writable.
await db.exec("update core.module_catalog set beta_open = false where key = 'module.match_workspace'");
await fails(coach, 'select api.get_match_plan($1)', [match], /not_found/);
await db.query("insert into core.club_entitlements values ($1,'module.match_workspace','write', now() - interval '1 day')", [club]);
const readOnly = await call(coach, 'select api.get_match_plan($1)', [match]);
assert.deepEqual([readOnly.can_edit, readOnly.sections.tactics.text], [false, 'Hög press']);
await fails(coach, "select api.save_match_plan($1,3,'x','','',true,true,false,true)", [match], /not_allowed/);
console.log('match plans: ok');
