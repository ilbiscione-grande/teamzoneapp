// Player attributes (2026-11-21): the team's leaders tick strengths and
// areas to develop per player; nobody else sees them; they go when the
// player leaves the team.
// node supabase/tests/player_attributes.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), playerLogin = id(2), club = id(10), team = id(20), other = id(21);
const [ada, bo, leaderPerson] = [id(50), id(51), id(52)];
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.teams(id uuid primary key, club_id uuid, sport text not null default 'football');
insert into core.teams values ('${team}','${club}','football'),('${other}','${club}','football');
create table core.club_people(id uuid primary key, club_id uuid, display_name text, status text default 'active');
insert into core.club_people values ('${ada}','${club}','Ada','active'),('${bo}','${club}','Bo','active'),
 ('${leaderPerson}','${club}','Coach','active');
create table core.assignments(id uuid primary key default gen_random_uuid(), club_id uuid, team_id uuid, club_person_id uuid,
  role_package text, state text, starts_at timestamptz default now() - interval '1 day', ends_at timestamptz);
insert into core.assignments(club_id, team_id, club_person_id, role_package, state) values
  ('${club}','${team}','${ada}','player','active'),('${club}','${team}','${bo}','player','active'),
  ('${club}','${team}','${leaderPerson}','leader','active'),('${club}','${other}','${ada}','player','active');
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$
  select auth.uid() = '${coach}'::uuid and cap = 'team.roster.manage' and t = '${team}'::uuid $$;
grant usage on schema api, internal, core, auth to authenticated;`);
await db.exec(read('supabase/migrations/20270407090000_player_attributes.sql'));
await db.exec('begin');

const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0];
const get = (t = team) => one('select api.get_team_player_attributes($1,$2) v', [club, t]).then(r => r.v);
const set = (person, strengths, development) => one(
  'select api.set_player_attributes($1,$2,$3,$4::text[],$5::text[]) v', [club, team, person, strengths, development]).then(r => r.v);
const rejects = async (fn, message) => {
  await db.exec('savepoint r');
  try { await assert.rejects(fn, e => e.message === message, message); } finally { await db.exec('rollback to r'); }
};
const player = (list, person) => list.players.find(p => p.person_id === person);

await db.exec('set role authenticated');
await as(coach);
let list = await get();
assert.equal(list.sport, 'football');
assert.ok(list.catalog.length >= 25, 'football list');
assert.deepEqual(list.catalog.slice(0, 2).map(a => a.key), ['acceleration', 'speed'], 'in list order');
assert.deepEqual(list.players.map(p => p.name), ['Ada', 'Bo'], 'players only, not leaders');
assert.deepEqual(player(list, ada).strengths, []);

// Ticking and replacing.
list = await set(ada, ['heading', 'speed', 'speed'], ['crossing']);
assert.deepEqual(player(list, ada).strengths, ['heading', 'speed']);
assert.deepEqual(player(list, ada).development, ['crossing']);
list = await set(ada, ['heading', 'crossing'], []);
assert.deepEqual(player(list, ada).strengths, ['crossing', 'heading'], 'moved from development to strength');
assert.deepEqual(player(list, ada).development, []);
await rejects(() => set(ada, ['speed'], ['speed']), 'attribute_both_ways');
await rejects(() => set(ada, ['flying'], []), 'invalid_attribute');
await rejects(() => set(leaderPerson, ['speed'], []), 'attributes_need_player_role');

// The team's own attributes.
list = await one('select api.save_team_attribute($1,$2,null,$3) v', [club, team, '  Långa   inkast ']).then(r => r.v);
const throwIns = list.custom[0];
assert.equal(throwIns.label, 'Långa inkast');
await rejects(() => one('select api.save_team_attribute($1,$2,null,$3) v', [club, team, 'långa INKAST']), 'attribute_label_taken');
await rejects(() => one('select api.save_team_attribute($1,$2,null,$3) v', [club, team, '   ']), 'invalid_label');
list = await set(bo, [throwIns.id], ['shooting']);
assert.deepEqual(player(list, bo).strengths, [throwIns.id]);
list = await one('select api.save_team_attribute($1,$2,$3,$4) v', [club, team, throwIns.id, 'Inkast']).then(r => r.v);
assert.equal(list.custom[0].label, 'Inkast');
list = await one('select api.delete_team_attribute($1,$2,$3) v', [club, team, throwIns.id]).then(r => r.v);
assert.deepEqual(list.custom, []);
assert.deepEqual(player(list, bo).strengths, [], 'ticks on a removed attribute go');
for (let n = 0; n < 15; n++) await one('select api.save_team_attribute($1,$2,null,$3) v', [club, team, 'Egen ' + n]);
await rejects(() => one('select api.save_team_attribute($1,$2,null,$3) v', [club, team, 'En till']), 'too_many_attributes');

// Nobody but the team's leaders.
await as(playerLogin);
await rejects(() => get(), 'not_found');
await rejects(() => set(ada, ['speed'], []), 'not_found');
await as(coach);
await rejects(() => get(other), 'not_found');
await rejects(() => db.query('select * from core.player_attributes'), 'permission denied for table player_attributes');

// Changing sport hides keys the new list lacks; leaving the team deletes.
await db.exec('set role authenticated');
await set(ada, ['heading', 'speed'], []);
await db.exec('reset role');
await db.query(`update core.teams set sport='handball' where id=$1`, [team]);
await db.exec('set role authenticated');
assert.deepEqual(player(await get(), ada).strengths, ['speed'], 'heading is not a handball attribute');
await db.exec('reset role');
await db.query(`update core.teams set sport='football' where id=$1`, [team]);
await db.query(`update core.assignments set state='ended' where club_person_id=$1 and team_id=$2`, [ada, team]);
assert.equal((await one('select count(*)::int n from core.player_attributes where club_person_id=$1', [ada])).n, 0);
await db.exec('set role authenticated');
assert.deepEqual((await get()).players.map(p => p.name), ['Bo']);
console.log('player attributes: ok');
