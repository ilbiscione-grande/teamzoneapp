// Tacticsboard's short links for players (20270103090000), in isolated
// Postgres with a reduced schema. node supabase/tests/tactics_player_links.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const owner = id(1), player = id(2), other = id(3);
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who ?? '']);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0] ?? {})[0];
// As the step-4 functions call it: inside the database, for the signed-in person.
const issue = async (who, board = null) => { await as(who); return one('select internal.issue_tactics_player_link($1,$2)', [project, board]); };
const shared = token => one('select internal.get_shared_tactics($1)', [token]);
const asOwner = async (sql, params) => { await as(owner); await db.exec('set role authenticated'); const value = await one(sql, params); await db.exec('reset role'); return value; };
await db.exec(`create role anon; create role authenticated; create role service_role;
create schema internal; create schema api; create schema core; create schema auth;
set check_function_bodies = off;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${owner}','Ägaren'),('${player}','Spelaren'),('${other}','Någon');
create table core.teams(id uuid primary key, name text);
create function internal.tournament_actor_teams() returns table(team_id uuid, team_name text, club_id uuid, club_name text) language sql stable as $$select null::uuid, null, null::uuid, null where false$$;
grant usage on schema api, internal, core, auth to authenticated;`);
for (const file of ['20261123090000_tacticsboard', '20261124090000_tactics_share_links', '20261227090000_tactics_shared_branding', '20270103090000_tactics_player_links']) {
  await db.exec(read(`supabase/migrations/${file}.sql`));
}
await db.exec('begin');
await as(owner);
await db.exec('set role authenticated');
const project = (await one("select api.create_tactics_project('Match', 'match', null, $1::jsonb)",
  [JSON.stringify({ version: 1, boards: [{ id: 'A', name: 'Uppspel' }, { id: 'B', name: 'Press' }] })])).id;
await db.exec('reset role');

// A player's link shows the boards, and asking again gives the same link.
const first = await issue(player);
assert.match(first, /^[0-9a-f]{40}$/);
assert.deepEqual((await shared(first)).boards.map(board => board.id), ['A', 'B']);
assert.equal(await issue(player), first);
assert.notEqual(await issue(other), first, 'each their own');
const oneBoard = await issue(player, 'B');
assert.deepEqual((await shared(oneBoard)).boards.map(board => board.id), ['B']);
const hours = await one('select extract(epoch from expires_at - now()) / 3600 from core.tactics_share_links where token = $1', [first]);
assert.ok(hours > 5.9 && hours <= 6, 'six hours');

// With less than an hour left a new one is made; run out, it shows nothing.
await db.exec(`update core.tactics_share_links set expires_at = now() + interval '30 minutes' where token = '${first}'`);
const second = await issue(player);
assert.notEqual(second, first);
await db.exec(`update core.tactics_share_links set expires_at = now() - interval '1 minute' where token = '${first}'`);
assert.equal(await shared(first), null);
assert.ok(await shared(second));

// The owner's own link is never a player's, and the owner's list leaves them out.
const owners = await asOwner('select api.create_tactics_share_link($1, null)', [project]);
assert.ok(![first, second].includes(owners));
assert.deepEqual((await asOwner('select api.list_tactics_share_links($1)', [project])).map(link => link.token), [owners]);
assert.ok(await shared(owners), 'an owner\'s link has no end');

// No one calls it directly.
await as(player);
await db.exec('savepoint s');
await db.exec('set role authenticated');
await assert.rejects(db.query('select internal.issue_tactics_player_link($1, null)', [project]), /permission denied/);
await db.exec('rollback to s');
await db.exec('reset role');
await as(null);
await db.exec('savepoint s');
await assert.rejects(db.query('select internal.issue_tactics_player_link($1, null)', [project]), /not_signed_in/);
await db.exec('rollback to s');

// A player's links run out a day ago go when they next ask.
await db.exec(`update core.tactics_share_links set expires_at = now() - interval '2 days' where token = '${first}'`);
await issue(player);
assert.equal(await one('select count(*)::int from core.tactics_share_links where token = $1', [first]), 0);

await db.exec('rollback');
console.log('tactics_player_links.local: ok');
