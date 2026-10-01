// Isolated check of 20261001190000_main_position_and_roster_avatars.sql.
// Run: node supabase/tests/main_position_avatars.local.mjs
import fs from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const club = '00000000-0000-0000-0000-000000000c1b';
const other = '00000000-0000-0000-0000-000000000c2b';
const team = '00000000-0000-0000-0000-0000000000a1';
const id = (n) => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
await db.exec(`
create schema core; create schema internal; create schema auth; create schema api;
create role authenticated; create role anon;
create table auth.actor(id uuid);
create function auth.uid() returns uuid language sql as $$ select id from auth.actor limit 1 $$;
create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
create table core.teams(id uuid primary key,club_id uuid,sport text default 'football');
create table core.sport_positions(sport text,key text);
insert into core.sport_positions values('football','striker'),('football','central_midfielder'),('football','left_winger');
create table core.team_person_details(club_id uuid,team_id uuid,club_person_id uuid,functions text[] default '{}',
  positions text[] not null default '{}',custom_titles text[] default '{}',custom_positions text[] not null default '{}',
  revision bigint default 0,primary key(team_id,club_person_id));
create function internal.normalize_labels(labels text[]) returns text[] language sql immutable as $f$
 select coalesce(array(select distinct btrim(label) from unnest(labels) label where label is not null and btrim(label)<>'' order by 1),'{}') $f$;
create function internal.validate_team_person_details() returns trigger language plpgsql as $f$ begin return new; end $f$;
create trigger team_person_details_validate before insert or update on core.team_person_details
for each row execute function internal.validate_team_person_details();
create function internal.save_team_person_details(target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_titles text[],new_positions text[],new_custom_titles text[],new_custom_positions text[],
 expected_revision bigint,idempotency_key uuid,command_type text) returns bigint language plpgsql as $f$
begin
 insert into core.team_person_details(club_id,team_id,club_person_id,positions,custom_positions,revision)
 values(target_club_id,target_team_id,target_person_id,internal.normalize_labels(new_positions),
  internal.normalize_labels(new_custom_positions),expected_revision+1)
 on conflict(team_id,club_person_id) do update set positions=excluded.positions,custom_positions=excluded.custom_positions,
  revision=excluded.revision;
 return expected_revision+1;
end$f$;
create function internal.list_team_roles_for_actor(target_club_id uuid,target_team_id uuid) returns jsonb language plpgsql as $f$
begin
 return (select jsonb_agg(jsonb_build_object('person_id',details.club_person_id,
  'positions',coalesce(details.positions,'{}'::text[]),'custom_positions',details.custom_positions))
  from core.team_person_details details where details.team_id=target_team_id);
end$f$;
create function internal.actor_has_club_access(c uuid) returns boolean language sql as $f$ select c='${club}'::uuid and auth.uid() is not null $f$;
create table core.assignments(club_id uuid,team_id uuid,club_person_id uuid,role_package text,state text);
create table core.person_account_links(club_person_id uuid,club_id uuid,profile_id uuid,state text);
create table core.profiles(id uuid primary key,avatar_asset_id uuid);
create table core.profile_avatars(id uuid primary key,profile_id uuid,object_key text,state text);
insert into core.teams values('${team}','${club}');
insert into core.assignments values('${club}','${team}','${id(21)}','player','active'),('${club}','${team}','${id(22)}','player','active'),
  ('${club}','${team}','${id(23)}','leader','active'),('${club}','${team}','${id(24)}','player','ended');
insert into core.person_account_links values('${id(21)}','${club}','${id(11)}','active'),('${id(22)}','${club}','${id(12)}','active'),
  ('${id(23)}','${club}','${id(13)}','active'),('${id(24)}','${club}','${id(14)}','active');
insert into core.profile_avatars values('${id(31)}','${id(11)}','a/1.upload','active'),('${id(32)}','${id(12)}','a/2.upload','replaced'),
  ('${id(33)}','${id(13)}','a/3.upload','active'),('${id(34)}','${id(14)}','a/4.upload','active');
insert into core.profiles values('${id(11)}','${id(31)}'),('${id(12)}','${id(32)}'),('${id(13)}','${id(33)}'),('${id(14)}','${id(34)}');
insert into auth.actor values('${id(11)}');
`);
await db.exec(fs.readFileSync('supabase/migrations/20261001190000_main_position_and_roster_avatars.sql', 'utf8')
  .replace("notify pgrst,'reload schema';", ''));

const assert = (ok, msg) => { if (!ok) throw new Error(msg); console.log('ok -', msg); };
const save = (positions, custom, main, revision) => db.query(
  `select api.set_team_person_details_v3($1,$2,$3,'{}',$4,'{}',$5,$6,$7,gen_random_uuid()) r`,
  [club, team, id(21), positions, custom, main, revision]);
const main = async () => (await db.query(`select main_position m from core.team_person_details where club_person_id=$1`, [id(21)])).rows[0]?.m;
const fails = async (fn, pattern) => { try { await fn(); return false; } catch (e) { return pattern.test(e.message); } };

await save(['striker', 'central_midfielder', 'left_winger'], [], 'striker', 0);
assert((await main()) === 'striker', 'main position saved among the positions');
const roles = (await db.query(`select internal.list_team_roles_for_actor($1,$2) r`, [club, team])).rows[0].r;
assert(roles[0].main_position === 'striker' && roles[0].positions.length === 3, 'roles list carries the main position');
await save(['central_midfielder'], ['Libero'], 'Libero', 1);
assert((await main()) === 'Libero', 'an own position can be the main position');
assert(await fails(() => save(['central_midfielder'], [], 'striker', 2), /invalid_main_position/),
  'a main position outside the positions is refused');
// An older client saving positions without the main one clears it.
await db.exec(`update core.team_person_details set custom_positions='{}' where club_person_id='${id(21)}'`);
assert((await main()) === null, 'main position cleared when it is no longer a position');
await save(['striker'], [], null, 2);
assert((await main()) === null, 'no main position is allowed');

const avatars = (await db.query(`select api.list_team_avatars($1,$2) r`, [club, team])).rows[0].r;
const people = avatars.map((a) => a.person_id).sort();
assert(JSON.stringify(people) === JSON.stringify([id(21), id(23)]),
  'avatars of current players and leaders with an active picture only');
assert(await fails(() => db.query(`select api.list_team_avatars($1,$2)`, [other, team]), /not_found/),
  'outside the club nothing is listed');
const grants = (await db.query(`select has_function_privilege('anon','api.list_team_avatars(uuid,uuid)','execute') a`)).rows[0];
assert(!grants.a, 'anonymous callers cannot list avatars');
console.log('PASS');
