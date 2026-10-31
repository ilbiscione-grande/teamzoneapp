// Tacticsboard in the match plan and the training (20270104090000), in
// isolated Postgres with a reduced schema: who reads and prepares an event
// is stubbed here, as the match plan's and training's own tests cover it.
// node supabase/tests/tactics_event_boards.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), helper = id(2), player = id(3), stranger = id(4);
const club = id(10), team = id(20), match = id(30), training = id(31);
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who ?? '']);
const call = async (who, sql, params = []) => {
  // No finally: in an aborted transaction it would hide the real error; the rollback resets the role.
  await as(who); await db.exec('set role authenticated');
  const value = Object.values((await db.query(sql, params)).rows[0] ?? {})[0];
  await db.exec('reset role');
  return value;
};
const fails = async (who, sql, params, pattern) => {
  await db.exec('savepoint s');
  await assert.rejects(call(who, sql, params), pattern);
  await db.exec('rollback to s');
};
await db.exec(`create role anon; create role authenticated; create role service_role;
create schema internal; create schema api; create schema core; create schema auth;
set check_function_bodies = off;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${coach}','Tränaren'),('${helper}','Anna'),('${player}','Spelaren'),('${stranger}','Någon');
create table core.teams(id uuid primary key, name text);
insert into core.teams values ('${team}','P2012');
create table core.clubs(id uuid primary key);
-- The coach and the helper lead the team.
create function internal.tournament_actor_teams() returns table(team_id uuid, team_name text, club_id uuid, club_name text) language sql stable security definer set search_path = '' as
  $$select '${team}'::uuid, null::text, null::uuid, null::text where auth.uid() in ('${coach}'::uuid, '${helper}'::uuid)$$;
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, event_type text, archived_at timestamptz,
  opponent_name text, home_away text, starts_at timestamptz);
insert into core.events values ('${match}','${club}','${team}','match',null,'Aneby','home',now()),
  ('${training}','${club}','${team}','training',null,null,null,now());
create table core.match_plans(event_id uuid primary key, revision bigint default 1, tactics_notes text default '', set_pieces_notes text default '',
  key_opponents_notes text default '', tactics_visible boolean default true, set_pieces_visible boolean default true,
  opponent_visible boolean default false, published boolean default false, updated_at timestamptz default now());
create table core.module_attachments (
  id uuid primary key default gen_random_uuid(), club_id uuid not null, owner_kind text not null check (owner_kind in ('match_plan', 'team_goal')),
  owner_id uuid not null, kind text not null check (kind in ('link')), title text not null check (length(btrim(title)) between 1 and 120),
  url text check (url ~ '^https://[^[:space:]]{3,}$' and length(url) <= 2000), visible_to_players boolean not null default false,
  position integer not null default 0, created_by uuid, created_at timestamptz not null default now(), check (kind <> 'link' or url is not null));
create table core.training_sessions(event_id uuid primary key, published boolean not null default false);
create table core.training_blocks(id uuid primary key default gen_random_uuid(), event_id uuid, position integer,
  board_source text, board_ref uuid, board_id text);
-- Everyone but the stranger reads the events; the coach and the helper prepare them.
create function internal.match_plan_event(target uuid) returns core.events language plpgsql stable security definer set search_path = '' as $$
declare e core.events; begin select * into e from core.events where id = target and event_type = 'match';
  if e.id is null or auth.uid() is null or auth.uid() = '${stranger}'::uuid then raise insufficient_privilege using message = 'not_found'; end if; return e; end $$;
create function internal.match_plan_can_edit(e core.events) returns boolean language sql stable security definer set search_path = '' as
  $$select auth.uid() in ('${coach}'::uuid, '${helper}'::uuid)$$;
create function internal.training_session_event(target uuid) returns core.events language plpgsql stable security definer set search_path = '' as $$
declare e core.events; begin select * into e from core.events where id = target and event_type = 'training';
  if e.id is null or auth.uid() is null or auth.uid() = '${stranger}'::uuid then raise insufficient_privilege using message = 'not_found'; end if; return e; end $$;
create function internal.training_session_can_edit(e core.events) returns boolean language sql stable security definer set search_path = '' as
  $$select auth.uid() in ('${coach}'::uuid, '${helper}'::uuid)$$;
grant usage on schema api, internal, core, auth to authenticated;`);
for (const file of ['20261123090000_tacticsboard', '20261124090000_tactics_share_links', '20261227090000_tactics_shared_branding',
  '20270102090000_tactics_leader_access', '20270103090000_tactics_player_links', '20270104090000_tactics_event_boards', '20270107090000_tactics_board_previews']) {
  await db.exec(read(`supabase/migrations/${file}.sql`));
}
await db.exec('begin');

const doc = JSON.stringify({ version: 1, boards: [{ id: 'A', name: 'Uppspel' }, { id: 'B', name: 'Press', view: 'attack', teams: { home: { color: '#f00' } },
  frames: [{ objects: [{ type: 'ball', x: 60, y: 30 }] }, { objects: [] }] }] });
const mine = (await call(coach, "select api.create_tactics_project('Matchplan', 'match', $1, $2::jsonb)", [team, doc])).id;
const private_ = (await call(helper, "select api.create_tactics_project('Annas egna', 'match', null, $1::jsonb)", [doc])).id;
const annas = (await call(helper, "select api.create_tactics_project('Annas lag', 'match', $1, $2::jsonb)", [team, doc])).id;
const planAs = async (who, edit) => { await as(who); return (await db.query('select internal.match_plan_json(e, $2) v from core.events e where e.id = $1', [match, edit])).rows[0].v; };
const shared = path => db.query('select internal.get_shared_tactics($1) v', [path.replace('/delad/', '')]).then(result => result.rows[0].v);

// The coach picks from their own and the team's projects, not another's private one.
const choices = await call(coach, 'select api.list_match_plan_board_choices($1)', [match]);
assert.deepEqual(choices.map(choice => choice.name).sort(), ['Annas lag', 'Matchplan']);
assert.deepEqual(choices.find(choice => choice.name === 'Matchplan').boards, [{ id: 'A', name: 'Uppspel' }, { id: 'B', name: 'Press' }]);
await fails(player, 'select api.list_match_plan_board_choices($1)', [match], /not_allowed/);

// Boards go on the plan; one the coach cannot open, or a board not in the project, does not.
const press = await call(coach, 'select api.add_match_plan_board($1,$2,$3,$4)', [match, mine, 'B', true]);
assert.equal(press.title, 'Press · Matchplan');
const whole = await call(coach, 'select api.add_match_plan_board($1,$2,$3,$4)', [match, annas, null, false]);
assert.equal(whole.title, 'Annas lag');
await fails(coach, 'select api.add_match_plan_board($1,$2,$3,$4)', [match, private_, null, true], /not_found/);
await fails(coach, 'select api.add_match_plan_board($1,$2,$3,$4)', [match, mine, 'X', true], /not_found/);
await fails(player, 'select api.add_match_plan_board($1,$2,$3,$4)', [match, mine, null, true], /not_allowed/);

// The plan lists its boards apart from its links; the players see the shown ones once it is published.
await db.exec(`insert into core.match_plans (event_id, published) values ('${match}', false)`);
let plan = await planAs(coach, true);
assert.deepEqual(plan.boards.map(board => board.title), ['Press · Matchplan', 'Annas lag']);
// Each board brings its first frame to draw; a whole project its first board.
assert.deepEqual(plan.boards[0].preview, { view: 'attack', teams: { home: { color: '#f00' } }, objects: [{ type: 'ball', x: 60, y: 30 }] });
assert.deepEqual(plan.boards[1].preview, { view: null, teams: null, objects: [] });
assert.deepEqual(plan.links, []);
await fails(player, 'select api.open_match_plan_board($1)', [press.id], /not_found/);
await db.exec(`update core.match_plans set published = true where event_id = '${match}'`);
plan = await planAs(player, false);
assert.deepEqual(plan.boards.map(board => board.title), ['Press · Matchplan']);

// Opening gives the player a short link of their own to the one board.
const path = await call(player, 'select api.open_match_plan_board($1)', [press.id]);
assert.match(path, /^\/delad\/[0-9a-f]{40}$/);
assert.deepEqual((await shared(path)).boards.map(board => board.id), ['B']);
const issued = await db.query('select issued_to, expires_at > now() + interval \'5 hours\' fresh from core.tactics_share_links where token = $1', [path.slice(7)]);
assert.equal(issued.rows[0].issued_to, player);
assert.equal(issued.rows[0].fresh, true);
await fails(player, 'select api.open_match_plan_board($1)', [whole.id], /not_found/);
await fails(stranger, 'select api.open_match_plan_board($1)', [press.id], /not_found/);
assert.ok(await call(coach, 'select api.open_match_plan_board($1)', [whole.id]), 'those preparing open hidden ones');

// A removed project takes its boards off the plan.
await call(helper, 'select api.delete_tactics_project($1)', [annas]);
assert.equal((await db.query("select count(*)::int n from core.module_attachments where kind = 'tactics'")).rows[0].n, 1);

// A training exercise's own board opens for the players of a published session; a library one does not yet.
const [own, library] = (await db.query(`insert into core.training_blocks (event_id, position, board_source, board_ref, board_id) values
  ('${training}', 0, 'mine', '${mine}', 'A'), ('${training}', 1, 'club', '${id(99)}', 'Z') returning id`)).rows.map(row => row.id);
await fails(player, 'select api.open_training_block_board($1)', [own], /not_found/);
await db.exec(`insert into core.training_sessions values ('${training}', true)`);
const exercise = await call(player, 'select api.open_training_block_board($1)', [own]);
assert.deepEqual((await shared(exercise)).boards.map(board => board.id), ['A']);
await fails(player, 'select api.open_training_block_board($1)', [library], /library_board/);
await fails(stranger, 'select api.open_training_block_board($1)', [own], /not_found/);

await db.exec('rollback');
console.log('tactics_event_boards.local: ok');
