// Isolated check of 20260929190000_my_team_titles.sql.
// Run: node supabase/tests/my_team_titles.local.mjs
import fs from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const club = '00000000-0000-0000-0000-000000000c1b';
const teamA = '00000000-0000-0000-0000-0000000000a1';
const teamB = '00000000-0000-0000-0000-0000000000b2';
const me = '00000000-0000-0000-0000-000000000001';
const other = '00000000-0000-0000-0000-000000000002';
const profile = '00000000-0000-0000-0000-0000000000ff';
await db.exec(`
create schema core; create schema internal; create schema auth; create schema api;
create role authenticated; create role anon;
create function auth.uid() returns uuid language sql as $$ select '${profile}'::uuid $$;
create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
create table core.person_account_links(profile_id uuid,club_person_id uuid,club_id uuid,state text default 'active');
create table core.assignments(club_id uuid,club_person_id uuid,team_id uuid,role_package text,
  state text default 'active',starts_at timestamptz default now()-interval '1 day',ends_at timestamptz);
create table core.team_person_details(club_id uuid,team_id uuid,club_person_id uuid,
  functions text[] default '{}',custom_titles text[] default '{}');
insert into core.person_account_links(profile_id,club_person_id,club_id) values('${profile}','${me}','${club}');
insert into core.assignments(club_id,club_person_id,team_id,role_package) values
 ('${club}','${me}','${teamA}','leader'),('${club}','${me}','${teamB}','player'),
 ('${club}','${other}','${teamA}','leader');
insert into core.team_person_details values
 ('${club}','${teamA}','${me}','{head_coach}','{Ungdomsansvarig}'),
 ('${club}','${teamB}','${me}','{team_manager}','{}'),
 ('${club}','${teamA}','${other}','{assistant_coach}','{}');
`);
await db.exec(fs.readFileSync('supabase/migrations/20260929190000_my_team_titles.sql', 'utf8')
  .replace("notify pgrst,'reload schema';", ''));
const rows = (await db.query('select api.get_my_team_titles() as r')).rows[0].r;
const assert = (ok, msg) => { if (!ok) throw new Error(msg); console.log('ok -', msg); };
assert(rows.length === 1 && rows[0].team_id === teamA, 'only teams where you are an active leader');
assert(rows[0].titles[0] === 'head_coach' && rows[0].custom_titles[0] === 'Ungdomsansvarig', 'own titles and labels');
await db.exec(`update core.assignments set state='ended',ends_at=now() where club_person_id='${me}' and team_id='${teamA}'`);
assert((await db.query('select api.get_my_team_titles() as r')).rows[0].r.length === 0, 'ended leader role hides titles');
console.log('PASS');
