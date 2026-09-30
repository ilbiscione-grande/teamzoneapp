// Isolated check of 20260930170000_team_sport_club_admin_only.sql.
// Run: node supabase/tests/team_sport_admin.local.mjs
import fs from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const club = '00000000-0000-0000-0000-000000000c1b';
const other = '00000000-0000-0000-0000-000000000c2b';
const team = '00000000-0000-0000-0000-0000000000a1';
const id = (n) => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
// Profile 11: club admin. Profile 12: team leader with club.memberships.manage
// on the team only. Profile 13: club admin in another club.
await db.exec(`
create schema core; create schema internal; create schema auth; create schema api;
create role authenticated; create role anon;
create table auth.actor(id uuid);
create function auth.uid() returns uuid language sql as $$ select id from auth.actor limit 1 $$;
create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
create table core.teams(id uuid primary key,club_id uuid,sport text default 'football');
create table core.person_account_links(profile_id uuid,club_person_id uuid,club_id uuid,state text default 'active');
create table core.assignments(id uuid primary key,club_person_id uuid,club_id uuid,state text default 'active',
  starts_at timestamptz default now()-interval '1 day',ends_at timestamptz);
create table core.capability_grants(assignment_id uuid,club_id uuid,capability text,scope_type text,scope_id uuid,
  starts_at timestamptz default now()-interval '1 day',ends_at timestamptz);
create function internal.set_team_sport_for_actor(target_club_id uuid,target_team_id uuid,new_sport text,idempotency_key uuid)
returns text language plpgsql security definer set search_path='' as $f$
begin
 perform internal.assert_team_role_manager(target_club_id,target_team_id);
 update core.teams set sport=new_sport where id=target_team_id;
 return new_sport;
end$f$;
create function internal.list_team_roles_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $f$
declare manages_leaders boolean:=true;
begin
 return jsonb_build_object(
  'can_manage',manages_leaders,
  'roles','[]'::jsonb);
end$f$;
insert into core.teams values('${team}','${club}','football');
insert into core.person_account_links values('${id(11)}','${id(21)}','${club}'),('${id(12)}','${id(22)}','${club}'),
  ('${id(13)}','${id(23)}','${other}');
insert into core.assignments(id,club_person_id,club_id) values('${id(31)}','${id(21)}','${club}'),
  ('${id(32)}','${id(22)}','${club}'),('${id(33)}','${id(23)}','${other}');
insert into core.capability_grants(assignment_id,club_id,capability,scope_type,scope_id) values
  ('${id(31)}','${club}','club.memberships.manage','club','${club}'),
  ('${id(32)}','${club}','club.memberships.manage','team','${team}'),
  ('${id(32)}','${club}','team.leaders.manage','club','${club}'),
  ('${id(33)}','${other}','club.memberships.manage','club','${other}');
`);
await db.exec(fs.readFileSync('supabase/migrations/20260930170000_team_sport_club_admin_only.sql', 'utf8')
  .replace("notify pgrst,'reload schema';", ''));

const assert = (ok, msg) => { if (!ok) throw new Error(msg); console.log('ok -', msg); };
const as = (n) => db.exec(`delete from auth.actor; insert into auth.actor values('${id(n)}')`);
const setSport = (sport) => db.query(`select internal.set_team_sport_for_actor($1,$2,$3,gen_random_uuid()) v`,
  [club, team, sport]);
const refused = async (sport) => {
  try { await setSport(sport); return false; } catch (e) { return /club_admin_required/.test(e.message); }
};
const roles = async () => (await db.query(`select internal.list_team_roles_for_actor($1,$2) r`, [club, team])).rows[0].r;

await as(11);
assert((await setSport('handball')).rows[0].v === 'handball', 'club admin changes the sport');
assert((await roles()).can_set_sport === true && (await roles()).can_manage === true, 'roles list: admin may set sport');
await as(12);
assert(await refused('football'), 'team leader cannot change the sport');
assert((await roles()).can_set_sport === false, 'roles list: leader may not set sport');
await as(13);
assert(await refused('football'), "another club's admin cannot change the sport");
const sport = (await db.query(`select sport from core.teams`)).rows[0].sport;
assert(sport === 'handball', 'sport unchanged by refused calls');
console.log('PASS');
