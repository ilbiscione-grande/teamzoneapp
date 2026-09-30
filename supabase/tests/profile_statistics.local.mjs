// Isolated check of 20260930160000_profile_statistics.sql.
// Run: node supabase/tests/profile_statistics.local.mjs
import fs from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const club = '00000000-0000-0000-0000-000000000c1b';
const team = '00000000-0000-0000-0000-0000000000a1';
const id = (n) => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
// Profile 12 owns person 22 (player); profile 11 leads; profile 13 is a teammate.
await db.exec(`
create schema core; create schema internal; create schema auth; create schema api;
create role authenticated; create role anon;
create table auth.actor(id uuid);
create function auth.uid() returns uuid language sql as $$ select id from auth.actor limit 1 $$;
create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
create table core.profiles(id uuid primary key);
create table core.events(id uuid primary key,club_id uuid,owning_team_id uuid,event_type text,state text default 'scheduled',
  starts_at timestamptz);
create table core.callups(id uuid primary key default gen_random_uuid(),club_id uuid,event_id uuid,club_person_id uuid,
  state text,sent_at timestamptz);
create table core.callup_responses(callup_id uuid,created_at timestamptz);
create table core.attendance_facts(club_id uuid,event_id uuid,club_person_id uuid,status text);
create table core.match_facts(club_id uuid,event_id uuid,fact_type text,side text,club_person_id uuid,
  secondary_club_person_id uuid,state text default 'active');
create table core.messages(sender_profile_id uuid,state text default 'sent');
create table core.person_account_links(club_person_id uuid,club_id uuid,profile_id uuid,state text default 'active',
  created_at timestamptz default now());
create function internal.person_in_team(c uuid,t uuid,p uuid) returns boolean language sql as $$ select true $$;
create function internal.actor_owns_club_person(c uuid,p uuid) returns boolean language sql as $$
  select auth.uid()='${id(12)}'::uuid and p='${id(22)}'::uuid $$;
create function internal.actor_leads_team(c uuid,t uuid) returns boolean language sql as $$
  select auth.uid()='${id(11)}'::uuid $$;
insert into core.profiles values('${id(11)}'),('${id(12)}'),('${id(13)}');
insert into core.person_account_links(club_person_id,club_id,profile_id) values('${id(22)}','${club}','${id(12)}');
insert into core.events values
  ('${id(41)}','${club}','${team}','training','scheduled',now()-interval '10 days'),
  ('${id(42)}','${club}','${team}','training','scheduled',now()-interval '3 days'),
  ('${id(43)}','${club}','${team}','match','scheduled',now()-interval '2 days'),
  ('${id(44)}','${club}','${team}','match','cancelled',now()-interval '1 day');
insert into core.attendance_facts values('${club}','${id(41)}','${id(22)}','present'),
  ('${club}','${id(42)}','${id(22)}','absent'),('${club}','${id(43)}','${id(22)}','present');
insert into core.callups(id,club_id,event_id,club_person_id,state,sent_at) values
  ('${id(51)}','${club}','${id(43)}','${id(22)}','accepted',now()-interval '5 days'),
  ('${id(52)}','${club}','${id(42)}','${id(22)}','declined',now()-interval '6 days');
insert into core.callup_responses values('${id(51)}',now()-interval '5 days'+interval '30 minutes'),
  ('${id(51)}',now()-interval '4 days'),('${id(52)}',now()-interval '6 days'+interval '90 minutes');
insert into core.match_facts(club_id,event_id,fact_type,side,club_person_id,secondary_club_person_id) values
  ('${club}','${id(43)}','goal','us','${id(22)}','${id(23)}'),
  ('${club}','${id(43)}','goal','us','${id(23)}','${id(22)}'),
  ('${club}','${id(43)}','card','us','${id(22)}',null);
insert into core.match_facts(club_id,event_id,fact_type,side,club_person_id,state) values
  ('${club}','${id(43)}','goal','us','${id(22)}','voided');
insert into core.messages(sender_profile_id) values('${id(12)}'),('${id(12)}'),('${id(13)}');
insert into core.messages(sender_profile_id,state) values('${id(12)}','recalled');
`);
await db.exec(fs.readFileSync('supabase/migrations/20260930160000_profile_statistics.sql', 'utf8')
  .replace("notify pgrst,'reload schema';", ''));

const assert = (ok, msg) => { if (!ok) throw new Error(msg); console.log('ok -', msg); };
const as = (n) => db.exec(`delete from auth.actor; insert into auth.actor values('${id(n)}')`);
const stats = async () => (await db.query(`select api.get_person_statistics($1,$2,$3) as r`, [club, team, id(22)])).rows[0].r;

// Active days: today, yesterday, the day before, then a gap and a longer run.
await as(12);
await db.query(`select api.record_activity()`);
await db.query(`select api.record_activity()`);
await db.exec(`insert into core.profile_activity_days(profile_id,day)
  select '${id(12)}',(now() at time zone 'Europe/Stockholm')::date-d from generate_series(1,2) d;
  insert into core.profile_activity_days(profile_id,day)
  select '${id(12)}',(now() at time zone 'Europe/Stockholm')::date-d from generate_series(10,14) d;`);

let s = await stats();
assert(s.sport.trainings_total === 2 && s.sport.trainings_attended === 1, 'training attendance');
assert(s.sport.matches_total === 1 && s.sport.matches_played === 1, 'matches, cancelled left out');
assert(s.sport.goals === 1 && s.sport.assists === 1 && s.sport.cards === 1, 'goals, assists and cards; voided left out');
assert(s.callups.received === 2 && s.callups.accepted === 1 && s.callups.declined === 1 && s.callups.answered === 2,
  'callup answers');
assert(Number(s.callups.avg_response_minutes) === 60, 'average of first answers (30 and 90 minutes)');
assert(s.app.messages_sent === 2, 'sent messages, recalled left out');
assert(s.app.current_streak === 3 && s.app.longest_streak === 5 && s.app.active_days_30 === 8, 'streaks and active days');

await as(11);
s = await stats();
assert(s.sport.goals === 1 && s.is_self === false, 'leader sees the sport figures');
assert(s.app.messages_sent === 2 && s.app.current_streak === 3,
  "leader sees the player's own app use, not their own");
await as(13);
let refused = false;
try { await stats(); } catch (e) { refused = /not_found/.test(e.message); }
assert(refused, 'teammate cannot read the statistics');
console.log('PASS');
