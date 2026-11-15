// Nya klubbar bara för utvalda (2026-11-15): open without a policy row,
// closed with one, except for the accounts in core.club_creators.
// node supabase/tests/club_creation_invite_only.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [owner, stranger] = [id(1), id(2)];
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table auth.users(id uuid primary key);
insert into auth.users values ('${owner}'),('${stranger}');
create table core.created(actor uuid, name text);
create function internal.create_club_with_first_team_for_actor(club_name text, team_name text, idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin insert into core.created values (auth.uid(), club_name); return jsonb_build_object('club', club_name); end $$;
create function api.create_club_with_first_team(club_name text, team_name text, idempotency_key uuid)
returns jsonb language sql set search_path = '' as $$select internal.create_club_with_first_team_for_actor(club_name,team_name,idempotency_key)$$;
grant usage on schema api, internal, core, auth to authenticated;
grant execute on function api.create_club_with_first_team(text, text, uuid) to authenticated;`);
await db.exec(read('supabase/migrations/20270325090000_club_creation_invite_only.sql'));
const create = async (who, name) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  await db.exec('set role authenticated');
  try {
    return (await db.query('select api.create_club_with_first_team($1, $2, gen_random_uuid()) r', [name, 'A-lag'])).rows[0].r;
  } finally { await db.exec('reset role'); }
};

// Without a policy row it is open, as before (the test project).
assert.deepEqual(await create(stranger, 'Öppen IF'), { club: 'Öppen IF' });

// Closed: only the listed account may start a club.
await db.exec(`insert into core.club_creation_policy(open) values (false);
insert into core.club_creators(profile_id, note) values ('${owner}', 'Produktägaren');`);
await assert.rejects(create(stranger, 'Stängd IF'), /club_creation_closed/);
assert.deepEqual(await create(owner, 'Ägarens IF'), { club: 'Ägarens IF' });
await assert.rejects(create(null, 'Anonym IF'), /unauthenticated/);

// The tables and the unchecked function are out of the clients' reach.
await db.query("select set_config('request.jwt.claim.sub',$1,false)", [stranger]);
await db.exec('set role authenticated');
await assert.rejects(db.query('select * from core.club_creators'), /permission denied/);
await assert.rejects(db.query(
  "select internal.create_club_with_first_team_unchecked_for_actor('X', 'Y', gen_random_uuid())"), /permission denied/);
await db.exec('reset role');
assert.deepEqual((await db.query('select actor, name from core.created order by name')).rows, [
  { actor: owner, name: 'Ägarens IF' }, { actor: stranger, name: 'Öppen IF' }]);
console.log('club creation invite only: ok');
