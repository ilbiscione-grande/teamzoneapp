// Isolated check of 20260930090000_event_place_pitch_surface.sql with stubs
// for the functions it builds on. Run: node supabase/tests/event_place.local.mjs
import fs from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const club = '00000000-0000-0000-0000-000000000c1b';
const team = '00000000-0000-0000-0000-0000000000a1';
const actor = '00000000-0000-0000-0000-0000000000ff';
await db.exec(`
create schema core; create schema internal; create schema auth; create schema api;
create role authenticated; create role anon;
create function auth.uid() returns uuid language sql as $$ select '${actor}'::uuid $$;
create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
create table core.event_locations(id uuid primary key default gen_random_uuid(),club_id uuid,name text,
  address text,created_by uuid,created_at timestamptz default clock_timestamp());
create table core.events(id uuid primary key default gen_random_uuid(),club_id uuid,owning_team_id uuid,
  recurrence_id uuid,occurrence_number int,event_type text default 'training',location_id uuid,revision bigint default 1,
  updated_at timestamptz default now(),
  assembly_minutes_before int,training_theme text,training_focus text,training_plan text,opponent_name text,
  home_away text,match_notes text,meeting_purpose text,meeting_agenda text);
create table core.event_revisions(event_id uuid,event_revision bigint,snapshot jsonb);
create function internal.actor_has_capability(c uuid,t uuid,cap text) returns boolean language sql as $$ select true $$;
create function internal.actor_can_manage_event(e uuid) returns boolean language sql as $$ select true $$;
create function internal.event_snapshot(e core.events) returns jsonb language sql as $$ select to_jsonb(e) $$;
create function internal.normalized_event_type_fields(t text,f jsonb,a core.events default null) returns jsonb
  language sql as $$ select f $$;
-- Stand-ins for the existing commands: create saves a fresh place by name,
-- revise reuses the latest place with that name (as the real ones do).
create function internal.create_event_for_actor(c uuid,t uuid,title text,d text,ty text,s text,sa timestamptz,
  ea timestamptz,ad boolean,tz text,aud text[],location_name text,rf text,ri int,rc int,k uuid) returns uuid
language plpgsql as $$ declare loc uuid; e uuid; begin
  if nullif(btrim(location_name),'') is not null then
    insert into core.event_locations(club_id,name,created_by) values(c,btrim(location_name),auth.uid()) returning id into loc;
  end if;
  insert into core.events(club_id,owning_team_id,event_type,location_id) values(c,t,ty,loc) returning id into e;
  insert into core.event_revisions values(e,1,null);
  return e; end $$;
create function internal.revise_event_v2_for_actor(e uuid,sc text,patch jsonb,r bigint,k uuid) returns bigint
language plpgsql as $$ declare loc uuid; begin
  if patch ?| array['location_pitch','location_surface'] then raise exception 'v2 must not see pitch/surface'; end if;
  if patch?'location_name' then
    select id into loc from core.event_locations where lower(btrim(name))=lower(btrim(patch->>'location_name'))
    order by created_at desc limit 1;
    update core.events set location_id=loc where id=e;
  end if;
  update core.events set revision=revision+1 where id=e;
  return (select revision from core.events where id=e); end $$;
-- Projection stand-in: must be patched to show the pitch as well.
create function internal.list_calendar_for_actor(e uuid) returns text language sql as $$
  select location.name from core.events event_row join core.event_locations location on location.id=event_row.location_id
  where event_row.id=e $$;
`);
for (const fn of ['list_calendar_page_for_actor', 'list_archived_events_for_actor', 'get_leader_home_for_actor',
  'get_player_home_for_actor', 'get_guardian_home_for_actor']) {
  await db.exec(`create function internal.${fn}(e uuid) returns text language sql as $$
    select location.name from core.events event_row join core.event_locations location on location.id=event_row.location_id
    where event_row.id=e $$;`);
}
await db.exec(fs.readFileSync('supabase/migrations/20260930090000_event_place_pitch_surface.sql', 'utf8')
  .replace("notify pgrst,'reload schema';", ''));

const assert = (ok, msg) => { if (!ok) throw new Error(msg); console.log('ok -', msg); };
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];

assert(await one(`select internal.event_place_label('Arena A','Plan 3')`) === 'Arena A · Plan 3', 'label with pitch');
assert(await one(`select internal.event_place_label('Arena A',null)`) === 'Arena A', 'label without pitch');

const create = (name, fields) => one(`select internal.create_event_v2_for_actor($1,$2,'Träning',null,'training','scheduled',
  now(),now()+interval '1 hour',false,'Europe/Stockholm',array['players'],$3,null,null,null,$4::jsonb,gen_random_uuid())`,
  [club, team, name, JSON.stringify(fields)]);
const e1 = await create('Arena A', { location_pitch: 'Plan 3', location_surface: 'Konstgräs' });
const place = async (e) => (await db.query(`select l.name,l.pitch,l.surface from core.events e join core.event_locations l
  on l.id=e.location_id where e.id=$1`, [e])).rows[0];
let p = await place(e1);
assert(p.name === 'Arena A' && p.pitch === 'Plan 3' && p.surface === 'Konstgräs', 'create saves facility, pitch and surface');
assert(await one(`select internal.list_calendar_for_actor($1)`, [e1]) === 'Arena A · Plan 3', 'projection shows facility · pitch');
assert((await one(`select api.list_saved_event_places($1,$2)`, [club, team])).length === 1, 'no stray name-only place is saved');

const e2 = await create(' arena a ', { location_pitch: 'plan 3', location_surface: 'konstgräs' });
const e3 = await create('Arena A', { location_pitch: 'Plan 1' });
const e4 = await create('Arena A', {});
assert((await place(e2)).pitch === 'Plan 3', 'same combination is reused case-insensitively');
assert(await one(`select count(distinct location_id) from core.events where id in ($1,$2)`, [e1, e2]) === 1, 'shared saved place');
assert((await place(e4)).pitch === null, 'place without pitch stays plain');

const saved = await one(`select api.list_saved_event_places($1,$2)`, [club, team]);
const combos = saved.map((s) => `${s.name}|${s.pitch ?? ''}|${s.surface ?? ''}`);
assert(combos.length === 3 && combos.includes('Arena A|Plan 3|Konstgräs') && combos.includes('Arena A|Plan 1|')
  && combos.includes('Arena A||'), 'saved places are the distinct combinations');

// Revise only the pitch: facility and surface are kept; other events untouched.
await one(`select internal.revise_event_v3_for_actor($1,'one','{"location_pitch":"Plan 2"}'::jsonb,1,gen_random_uuid())`, [e1]);
p = await place(e1);
assert(p.name === 'Arena A' && p.pitch === 'Plan 2' && p.surface === 'Konstgräs', 'revise pitch keeps facility and surface');
assert((await place(e2)).pitch === 'Plan 3', 'event sharing the old place is unchanged');
// Revise the facility by name only: pitch and surface are kept.
await one(`select internal.revise_event_v3_for_actor($1,'one','{"location_name":"Bergby IP"}'::jsonb,2,gen_random_uuid())`, [e1]);
p = await place(e1);
assert(p.name === 'Bergby IP' && p.pitch === 'Plan 2' && p.surface === 'Konstgräs', 'new facility keeps pitch and surface');
// Clearing the facility clears the place.
await one(`select internal.revise_event_v3_for_actor($1,'one','{"location_name":null}'::jsonb,3,gen_random_uuid())`, [e1]);
assert(await one(`select location_id from core.events where id=$1`, [e1]) === null, 'clearing the facility clears the place');
// Revising something else leaves the place alone.
await one(`select internal.revise_event_v3_for_actor($1,'one','{"training_theme":"Passningar"}'::jsonb,1,gen_random_uuid())`, [e3]);
assert((await place(e3)).pitch === 'Plan 1', 'unrelated revise keeps the place');
let refused = false;
try { await create('Arena A', { location_pitch: 'x'.repeat(81) }); } catch { refused = true; }
assert(refused, 'overlong pitch is refused');
console.log('PASS');
