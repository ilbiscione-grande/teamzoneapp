// Isolated check of 20260929180000_team_member_profile_for_leaders.sql:
// a leader without a home-team assignment resolves through their role.
// Run: node supabase/tests/member_profile_leaders.local.mjs
import fs from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
await db.exec(`
create schema core; create schema internal; create schema auth;
create role authenticated; create role anon;
create table auth.actor(id uuid);
create function auth.uid() returns uuid language sql as $$ select id from auth.actor limit 1 $$;
create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
create table core.teams(id uuid primary key,club_id uuid,name text);
create table core.club_people(id uuid primary key,club_id uuid,display_name text,age_class text,
  status text default 'active',revision bigint default 1,safeguarding_required boolean default false,
  representation_available boolean default false,provenance text default 'created');
create table core.team_assignments(id uuid primary key default gen_random_uuid(),club_id uuid,club_person_id uuid,
  team_id uuid,state text default 'active',starts_at timestamptz default now()-interval '1 day',ends_at timestamptz,revision bigint default 1);
create table core.assignments(id uuid primary key default gen_random_uuid(),club_id uuid,club_person_id uuid,
  team_id uuid,role_package text,state text default 'active',starts_at timestamptz default now()-interval '1 day',ends_at timestamptz);
create table core.person_account_links(profile_id uuid,club_person_id uuid,club_id uuid,state text default 'active');
create function internal.actor_has_capability(c uuid,t uuid,cap text) returns boolean language sql as $$ select true $$;
create function internal.actor_owns_club_person(c uuid,p uuid) returns boolean language sql
  as $$ select exists(select 1 from core.person_account_links l where l.club_person_id=p and l.profile_id=auth.uid()) $$;
`);
const ids = {
  club: '00000000-0000-0000-0000-000000000c1b', team: '00000000-0000-0000-0000-0000000000a1',
  other: '00000000-0000-0000-0000-0000000000b2', me: '00000000-0000-0000-0000-000000000001',
  lars: '00000000-0000-0000-0000-000000000002', ada: '00000000-0000-0000-0000-000000000003',
  gone: '00000000-0000-0000-0000-000000000004', profile: '00000000-0000-0000-0000-0000000000ff',
};
await db.exec(`
insert into auth.actor values('${ids.profile}');
insert into core.teams values('${ids.team}','${ids.club}','F2012'),('${ids.other}','${ids.club}','F2011');
insert into core.club_people(id,club_id,display_name,age_class) values
 ('${ids.me}','${ids.club}','Me',null),('${ids.lars}','${ids.club}','Lars',null),
 ('${ids.ada}','${ids.club}','Ada','F2012'),('${ids.gone}','${ids.club}','Gone',null);
insert into core.person_account_links(profile_id,club_person_id,club_id) values('${ids.profile}','${ids.me}','${ids.club}');
insert into core.assignments(club_id,club_person_id,team_id,role_package) values
 ('${ids.club}','${ids.me}','${ids.team}','leader'),('${ids.club}','${ids.lars}','${ids.team}','leader'),
 ('${ids.club}','${ids.ada}','${ids.team}','player'),('${ids.club}','${ids.ada}','${ids.team}','leader'),
 ('${ids.club}','${ids.gone}','${ids.other}','leader');
insert into core.team_assignments(club_id,club_person_id,team_id) values('${ids.club}','${ids.ada}','${ids.team}');
`);
await db.exec(fs.readFileSync('supabase/migrations/20260929180000_team_member_profile_for_leaders.sql', 'utf8')
  .replace("notify pgrst,'reload schema';", ''));

const details = async (person) => (await db.query(
  `select internal.get_roster_person_details_for_actor($1,$2,$3) as r`, [ids.club, ids.team, person])).rows[0].r;
const assert = (ok, msg) => { if (!ok) throw new Error(msg); console.log('ok -', msg); };

const lars = await details(ids.lars);
assert(lars.display_name === 'Lars' && lars.home_member === false, 'leader resolves through role, not home');
assert(lars.assignment_state === 'active' && lars.team_name === 'F2012', 'leader has active state and team');
assert(lars.representation_available === undefined, 'representation hidden for leaders');
assert(lars.management.assignment_revision === undefined, 'no home assignment revision for leaders');
const me = await details(ids.me);
assert(me.is_self === true, 'own leader profile is marked self');
const ada = await details(ids.ada);
assert(ada.home_member === true && ada.management.assignment_revision === 1, 'player+leader prefers home assignment');
let refused = false;
try { await details(ids.gone); } catch (e) { refused = /not_found/.test(e.message); }
assert(refused, 'leader of another team is not found here');
await db.exec(`update core.assignments set state='ended',ends_at=now() where club_person_id='${ids.lars}'`);
refused = false;
try { await details(ids.lars); } catch (e) { refused = /not_found/.test(e.message); }
assert(refused, 'ended leader role no longer resolves');
console.log('PASS');
