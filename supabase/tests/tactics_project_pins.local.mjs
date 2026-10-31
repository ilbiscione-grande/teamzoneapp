// Tacticsboard's pins and project previews (20270109090000), in isolated
// Postgres with the reduced schema of tactics_event_boards.local.mjs.
// node supabase/tests/tactics_project_pins.local.mjs
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
  '20270102090000_tactics_leader_access', '20270103090000_tactics_player_links', '20270104090000_tactics_event_boards', '20270107090000_tactics_board_previews', '20270109090000_tactics_project_pins']) {
  await db.exec(read(`supabase/migrations/${file}.sql`));
}
await db.exec('begin');

const doc = JSON.stringify({ version: 1, boards: [{ id: 'A', name: 'Uppspel', view: 'defend', teams: {}, frames: [{ objects: [{ type: 'ball', x: 1, y: 2 }] }] }] });
const team_ = (await call(coach, "select api.create_tactics_project('Lagets', 'match', $1, $2::jsonb)", [team, doc])).id;
const own = (await call(helper, "select api.create_tactics_project('Annas egna', 'match', null, $1::jsonb)", [doc])).id;
const pinned = async (who, list) => (await (list === mineAs ? mine(who) : call(who, list))).map(project => [project.name, project.pinned]);
// Your own projects' summaries, as Mitt bibliotek lists them (its search is tested in tactics_my_library).
const mineAs = "select jsonb_agg(internal.tactics_project_summary(p) order by p.name) from core.tactics_projects p where p.owner_id = auth.uid()";
// Read as the table owner, as the security definer list functions do.
const mine = async who => { await as(who); return Object.values((await db.query(mineAs)).rows[0])[0]; };

// A summary brings its first board to draw.
const created = await call(coach, "select api.create_tactics_project('Tom', 'training', null, $1::jsonb)", [JSON.stringify({ version: 1, boards: [] })]);
assert.equal(created.preview, null);
const [lagets] = await mine(coach);
assert.deepEqual(lagets.preview, { view: 'defend', teams: {}, objects: [{ type: 'ball', x: 1, y: 2 }] });
assert.equal(lagets.pinned, false);

// Pins are your own: the helper pins the team's project and their own; the coach sees neither pinned.
await call(helper, 'select api.set_tactics_project_pinned($1, true)', [team_]);
await call(helper, 'select api.set_tactics_project_pinned($1, true)', [own]);
await call(helper, 'select api.set_tactics_project_pinned($1, true)', [own]);
assert.deepEqual(await pinned(helper, 'select api.list_team_tactics_projects()'), [['Lagets', true]]);
assert.deepEqual(await pinned(helper, mineAs), [['Annas egna', true]]);
assert.deepEqual((await pinned(coach, mineAs)).map(([, pin]) => pin), [false, false]);

// A project you cannot open is not pinned; unpinning takes it off; removing the project its pins.
await fails(coach, 'select api.set_tactics_project_pinned($1, true)', [own], /not_found/);
await fails(stranger, 'select api.set_tactics_project_pinned($1, true)', [team_], /not_found/);
await call(helper, 'select api.set_tactics_project_pinned($1, false)', [own]);
assert.deepEqual(await pinned(helper, mineAs), [['Annas egna', false]]);
await call(coach, 'select api.delete_tactics_project($1)', [team_]);
assert.equal((await db.query('select count(*)::int n from core.tactics_project_pins')).rows[0].n, 0);

await db.exec('rollback');
console.log('tactics_project_pins.local: ok');
