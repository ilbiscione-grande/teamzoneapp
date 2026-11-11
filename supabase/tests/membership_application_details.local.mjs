// Membership applications say who is asking (2026-11-11): the review list
// has the applicant's e-mail and whether they used a team code; someone
// without a name sets one before applying.
// node supabase/tests/membership_application_details.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const club = id(10), team = id(20), admin = id(1), coach = id(2), viaCode = id(3), viaSearch = id(4);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth; create schema audit;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table auth.users(id uuid primary key, email text);
insert into auth.users values ('${viaCode}','ny@example.com'),('${viaSearch}','sok@example.com');
create table core.profiles(id uuid primary key, display_name text, updated_at timestamptz, revision bigint default 1);
insert into core.profiles values ('${admin}','Admin',now(),1),('${coach}','Coach',now(),1),('${viaCode}','',now(),1),('${viaSearch}','Sara Sök',now(),1);
create table core.teams(id uuid primary key, club_id uuid, name text);
insert into core.teams values ('${team}','${club}','A');
create table core.membership_applications(id uuid primary key default gen_random_uuid(), applicant_profile_id uuid, club_id uuid,
  team_id uuid, requested_role text, status text, created_at timestamptz default now());
insert into core.membership_applications(id, applicant_profile_id, club_id, team_id, requested_role, status, created_at) values
  ('${id(31)}','${viaCode}','${club}','${team}','leader','pending', now() - interval '1 hour'),
  ('${id(32)}','${viaSearch}','${club}','${team}','player','pending', now());
create table audit.command_events(command_type text, aggregate_type text, aggregate_id uuid);
insert into audit.command_events values ('roster.team_code.claim.v1','membership_application','${id(31)}');
create function internal.actor_has_capability(target_club_id uuid, target_team_id uuid, required_capability text)
returns boolean language sql stable as $$ select auth.uid() = '${admin}'::uuid and required_capability = 'club.memberships.manage' $$;
grant usage on schema api, internal, core, auth, audit to authenticated;`);
await db.exec(`create function internal.list_pending_membership_applications_for_actor(target_club_id uuid, target_team_id uuid default null)
returns table(application_id uuid) language sql as $$ select null::uuid $$;
create function api.list_pending_membership_applications(target_club_id uuid, target_team_id uuid default null)
returns table(application_id uuid) language sql as $$ select null::uuid $$;`);
await db.exec(read('supabase/migrations/20270219090000_membership_application_details.sql'));
const call = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  await db.exec('set role authenticated');
  try { return (await db.query(sql, params)).rows; } finally { await db.exec('reset role'); }
};

const rows = await call(admin, 'select * from api.list_pending_membership_applications($1)', [club]);
assert.deepEqual(rows.map(r => [r.applicant_display_name, r.applicant_email, r.source, r.requested_role]), [
  ['Ny användare', 'ny@example.com', 'team_code', 'leader'],
  ['Sara Sök', 'sok@example.com', 'search', 'player'],
]);
await assert.rejects(call(coach, 'select * from api.list_pending_membership_applications($1)', [club]), /not_found/);

// The new user names themself; the list shows the name.
assert.equal((await call(viaCode, "select api.set_my_display_name('  Nils   Nysson ') r"))[0].r.display_name, 'Nils Nysson');
await assert.rejects(call(viaCode, "select api.set_my_display_name(' x ')"), /invalid_display_name/);
const named = await call(admin, 'select * from api.list_pending_membership_applications($1)', [club]);
assert.equal(named[0].applicant_display_name, 'Nils Nysson');
console.log('membership application details: ok');
