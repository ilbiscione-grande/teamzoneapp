// Tacticsboard's library, step 3 (2026-10-25): one library — shared with
// the whole community or only with a club — and the club's curated list of
// items picked from the whole library.
// node supabase/tests/tactics_club_library.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const anna = id(1), bo = id(2), admin = id(3), outsider = id(4), player = id(5);
const club = id(10), otherClub = id(11), project = id(30);
const person = n => id(100 + n);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth; create schema audit;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${anna}','Anna Tränare'),('${bo}','Bo Ledare'),('${admin}','Ada Admin'),('${outsider}','Olle'),('${player}','');
create table core.clubs(id uuid primary key, name text); insert into core.clubs values ('${club}','Demoklubben IF'),('${otherClub}','Annan IK');
create table core.person_account_links(profile_id uuid, club_id uuid, club_person_id uuid, state text);
create table core.assignments(club_id uuid, club_person_id uuid, role_package text, state text, starts_at timestamptz, ends_at timestamptz);
insert into core.person_account_links values ('${anna}','${club}','${person(1)}','active'),('${bo}','${club}','${person(2)}','active'),
  ('${admin}','${club}','${person(3)}','active'),('${outsider}','${otherClub}','${person(4)}','active'),('${player}','${club}','${person(5)}','active');
insert into core.assignments values ('${club}','${person(1)}','leader','active',now() - interval '1 day',null),
  ('${club}','${person(2)}','leader','active',now() - interval '1 day',null),
  ('${club}','${person(3)}','club_functionary','active',now() - interval '1 day',null),
  ('${otherClub}','${person(4)}','leader','active',now() - interval '1 day',null),
  ('${club}','${person(5)}','player','active',now() - interval '1 day',null);
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$
  select auth.uid() = '${admin}'::uuid and cap = 'club.memberships.manage' $$;
create table core.tactics_projects(id uuid primary key, owner_id uuid); insert into core.tactics_projects values ('${project}','${anna}');
create table audit.command_events(id uuid primary key default gen_random_uuid(), club_id uuid, actor_profile_id uuid, command_type text,
  aggregate_type text, aggregate_id uuid, aggregate_revision bigint, reason text, metadata jsonb, occurred_at timestamptz default now());
create function internal.actor_is_support_admin() returns boolean language sql stable as $$ select false $$;
grant usage on schema api, internal, core, auth to authenticated;`);
for (const name of ['20261213090000_tactics_library', '20261214090000_tactics_shared_library', '20261215090000_tactics_club_library']) {
  await db.exec(read(`supabase/migrations/${name}.sql`));
}
// The board preview alone from 20270107090000 (the rest of it is the match plan's), then the summaries with it.
const previews = read('supabase/migrations/20270107090000_tactics_board_previews.sql');
const previewStart = previews.indexOf('create or replace function internal.tactics_board_preview');
await db.exec(previews.slice(previewStart, previews.indexOf('\n$$;', previewStart) + 4));
await db.exec(read('supabase/migrations/20270113090000_tactics_shared_previews.sql'));
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
const search = (who, text = '', inClub = null) =>
  call(who, 'select api.search_tactics_shared_items($1,null,null,null,null,null,$2,false,0)', [text, inClub]);
const titles = list => list.map(item => item.title);
const saveLibrary = (title, board) => call(anna, 'select api.save_tactics_library_item($1,$2,$3::jsonb,$4::jsonb,$5,$6)',
  ['exercise', title, JSON.stringify({ part: 'warmup', minutes: 10 }),
    JSON.stringify({ schemaVersion: 1, boards: [{ id: board, name: title, frames: [] }] }), project, board]);

// The clubs whose library you use: as a leader or a club functionary, not as a player.
assert.deepEqual((await call(anna, 'select api.list_my_tactics_clubs()')).map(c => [c.club_name, c.can_manage]), [['Demoklubben IF', false]]);
assert.deepEqual((await call(admin, 'select api.list_my_tactics_clubs()')).map(c => c.can_manage), [true]);
assert.deepEqual(await call(player, 'select api.list_my_tactics_clubs()'), []);

// Shared only with the club: its leaders see it, other clubs do not.
const warmup = await saveLibrary('Klubbens uppvärmning', 'b1');
const forClub = await call(anna, 'select api.share_tactics_library_item($1,$2)', [warmup.id, club]);
assert.deepEqual([forClub.club_name, forClub.mine], ['Demoklubben IF', true]);
// Each item brings its first board to draw.
assert.deepEqual(forClub.preview, { view: null, teams: null, objects: [] });
assert.deepEqual(titles(await search(bo, 'klubbens')), ['Klubbens uppvärmning']);
assert.deepEqual(await search(outsider, 'klubbens'), []);
await fails(outsider, 'select api.get_tactics_shared_item($1)', [forClub.id], /not_found/);
await fails(player, "select api.search_tactics_shared_items('',null,null,null,null,null,$1,false,0)", [club], /not_found/);
await fails(anna, 'select api.share_tactics_library_item($1,$2)', [warmup.id, otherClub], /not_found/);
let library = await call(anna, 'select api.list_my_tactics_library()');
assert.deepEqual([library[0].shared.club_name, library[0].shared.current], ['Demoklubben IF', true]);

// Shared with the whole community: everyone sees it.
const rondo = await saveLibrary('Rondo för alla', 'b2');
await call(anna, 'select api.share_tactics_library_item($1,null)', [rondo.id]);
assert.deepEqual(titles(await search(outsider, 'rondo för alla')), ['Rondo för alla']);

// The club's list: what is shared only with it, and what the keeper picks from the whole library.
assert.deepEqual(titles(await search(bo, '', club)), ['Klubbens uppvärmning']);
const starter = (await search(admin, 'kontring'))[0];
await call(admin, 'select api.set_tactics_club_pick($1,$2,true)', [club, starter.id]);
await fails(bo, 'select api.set_tactics_club_pick($1,$2,true)', [club, starter.id], /not_found/);
assert.deepEqual(new Set(titles(await search(bo, '', club))), new Set(['Klubbens uppvärmning', 'Kontring från press 6 mot 6']));
assert.deepEqual((await search(admin, 'kontring'))[0].picked_by_clubs, [club]);
assert.deepEqual((await search(outsider, 'kontring'))[0].picked_by_clubs, [], 'another club\'s picks are not shown');
await call(admin, 'select api.set_tactics_club_pick($1,$2,false)', [club, starter.id]);
assert.deepEqual(titles(await search(bo, '', club)), ['Klubbens uppvärmning']);

// Moving a community item to the club only takes it out of other clubs' lists.
const theirs = await call(outsider, "select api.list_my_tactics_clubs()");
assert.equal(theirs.length, 1);
await db.exec(`insert into core.tactics_club_picks (club_id, shared_item_id) select '${otherClub}', id from core.tactics_shared_items where title = 'Rondo för alla'`);
await call(anna, 'select api.share_tactics_library_item($1,$2)', [rondo.id, club]);
assert.equal((await db.query(`select count(*)::int n from core.tactics_club_picks where club_id = '${otherClub}'`)).rows[0].n, 0);
assert.deepEqual(await search(outsider, 'rondo för alla'), []);

// Removing: the club's keeper removes what was shared with the club; another leader cannot.
await fails(bo, 'select api.unshare_tactics_item($1)', [forClub.id], /not_found/);
assert.equal((await search(admin, 'klubbens'))[0].can_remove, true);
await call(admin, 'select api.unshare_tactics_item($1)', [forClub.id]);
assert.deepEqual(await search(bo, 'klubbens'), []);
library = await call(anna, 'select api.list_my_tactics_library()');
assert.equal(library.find(item => item.id === warmup.id).shared, null, 'her own item stays, unshared');

// Favourites: marked items show as additions to your library; only what you see can be marked.
const favourites = () => call(bo, 'select api.search_tactics_shared_items(null,null,null,null,null,null,null,true,0)');
assert.deepEqual(await favourites(), []);
const kontring = (await search(bo, 'kontring'))[0];
await call(bo, 'select api.set_tactics_favorite($1,true)', [kontring.id]);
assert.deepEqual(titles(await favourites()), ['Kontring från press 6 mot 6']);
assert.equal((await search(bo, 'kontring'))[0].favorite, true);
assert.equal((await search(anna, 'kontring'))[0].favorite, false, 'favourites are your own');
const clubOnly = await call(anna, 'select api.share_tactics_library_item($1,$2)', [warmup.id, club]);
await fails(outsider, 'select api.set_tactics_favorite($1,true)', [clubOnly.id], /not_found/);
await call(bo, 'select api.set_tactics_favorite($1,false)', [kontring.id]);
assert.deepEqual(await favourites(), []);

console.log('tactics_club_library: ok');
