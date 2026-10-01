// Isolated check of 20261001150000_team_show_matches.sql.
// Run: node supabase/tests/team_show_matches.local.mjs
import fs from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const team = '00000000-0000-0000-0000-0000000000a1';
const id = (n) => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
// The stubs keep the exact text the migration patches.
await db.exec(`
create schema core; create schema internal; create schema auth; create schema api; create schema audit; create schema public_api;
create role authenticated; create role anon;
create table auth.actor(id uuid);
create function auth.uid() returns uuid language sql as $$ select id from auth.actor limit 1 $$;
create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,aggregate_id uuid,
  aggregate_revision bigint,metadata jsonb);
create table core.teams(id uuid primary key,club_id uuid);
create table core.events(id uuid primary key,owning_team_id uuid,event_type text,state text default 'scheduled',
  starts_at timestamptz,archived_at timestamptz);
create table core.event_publication_settings(event_id uuid primary key,state text);
create table core.team_event_visibility(team_id uuid primary key,show_results boolean not null default false,
  show_training boolean not null default false,revision bigint not null default 1,changed_by uuid,changed_at timestamptz);
create table public_api.event_projections(public_id uuid primary key);
create function internal.get_team_event_visibility_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable as $f$
declare result jsonb;
begin
 select jsonb_build_object('show_results',show_results,'show_training',show_training,'revision',revision)
 into result from core.team_event_visibility where team_id=target_team_id;
 return coalesce(result,jsonb_build_object('show_results',false,'show_training',false,'revision',0));
end;$f$;
create function internal.sync_team_public_event(target_event_id uuid)
returns void language plpgsql as $f$
declare e core.events%rowtype; preference core.team_event_visibility%rowtype; manual core.event_publication_settings%rowtype;
 completed boolean:=false; score record;
begin
 select * into e from core.events where id=target_event_id;
 select * into preference from core.team_event_visibility where team_id=e.owning_team_id;
 select * into manual from core.event_publication_settings where event_id=e.id;
 select null::uuid as event_id into score;
 if preference.team_id is not null and e.archived_at is null and e.state in('scheduled','completed') and (
   (e.event_type='training' and preference.show_training) or
   (e.event_type='match' and (manual.state='published' or (preference.show_results and completed and score.event_id is not null)))) then
  insert into public_api.event_projections values(e.id) on conflict do nothing;
 else
  delete from public_api.event_projections where public_id=e.id;
 end if;
end;$f$;
insert into core.teams values('${team}','${id(90)}');
insert into core.events(id,owning_team_id,event_type,starts_at) values
  ('${id(1)}','${team}','match',now()+interval '3 days'),
  ('${id(2)}','${team}','match',now()-interval '3 days'),
  ('${id(3)}','${team}','match',now()+interval '9 days'),
  ('${id(4)}','${team}','training',now()+interval '1 day');
insert into core.events(id,owning_team_id,event_type,starts_at,state) values('${id(5)}','${team}','match',now()+interval '5 days','cancelled');
insert into core.event_publication_settings values('${id(3)}','private');
insert into auth.actor values('${id(11)}');
`);
await db.exec(fs.readFileSync('supabase/migrations/20261001150000_team_show_matches.sql', 'utf8')
  .replace("notify pgrst,'reload schema';", ''));

const assert = (ok, msg) => { if (!ok) throw new Error(msg); console.log('ok -', msg); };
const shown = async () => (await db.query(`select public_id from public_api.event_projections order by 1`)).rows.map(r => r.public_id);
const set = (results, training, matches, revision) => db.query(
  `select api.set_team_event_visibility_v2($1,$2,$3,$4,$5) r`, [team, results, training, matches, revision]);

assert((await db.query(`select internal.get_team_event_visibility_for_actor($1) r`, [team])).rows[0].r.show_matches === false,
  'matches are hidden by default');
let r = (await set(false, true, false, 0)).rows[0].r;
assert(JSON.stringify(await shown()) === JSON.stringify([id(4)]), 'training only');
r = (await set(false, true, true, r.revision)).rows[0].r;
assert(r.show_matches === true, 'show_matches saved');
assert(JSON.stringify(await shown()) === JSON.stringify([id(1), id(2), id(4)]),
  'upcoming and played matches shown; private and cancelled ones not');
// An older client changing results and training keeps the match choice.
r = (await db.query(`select internal.set_team_event_visibility_for_actor($1,true,true,$2) r`, [team, r.revision])).rows[0].r;
assert(r.show_matches === true && r.show_results === true, 'older clients keep show_matches');
r = (await set(true, true, false, r.revision)).rows[0].r;
assert(JSON.stringify(await shown()) === JSON.stringify([id(4)]), 'turning it off hides the matches again');
let stale = false;
try { await set(true, true, true, 1); } catch (e) { stale = /revision_conflict/.test(e.message); }
assert(stale, 'stale revision refused');
console.log('PASS');
