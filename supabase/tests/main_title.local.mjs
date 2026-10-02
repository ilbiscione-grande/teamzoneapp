// Isolated check of 20261001210000_main_title.sql.
// Run: node supabase/tests/main_title.local.mjs
import fs from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const club = '00000000-0000-0000-0000-000000000c1b';
const team = '00000000-0000-0000-0000-0000000000a1';
const id = (n) => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
await db.exec(`
create schema core; create schema internal; create schema auth; create schema api;
create role authenticated; create role anon;
create table auth.actor(id uuid);
create function auth.uid() returns uuid language sql as $$ select id from auth.actor limit 1 $$;
create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
create table core.teams(id uuid primary key,sport text default 'football');
create table core.sport_positions(sport text,key text);
create table core.team_person_details(club_id uuid,team_id uuid,club_person_id uuid,functions text[] not null default '{}',
  positions text[] not null default '{}',custom_titles text[] not null default '{}',custom_positions text[] not null default '{}',
  main_position text,revision bigint default 0,primary key(team_id,club_person_id));
create function internal.validate_team_person_details() returns trigger language plpgsql as $f$ begin return new; end $f$;
create trigger team_person_details_validate before insert or update on core.team_person_details
for each row execute function internal.validate_team_person_details();
create function internal.normalize_labels(labels text[]) returns text[] language sql immutable as $f$
 select coalesce(array(select distinct btrim(label) from unnest(labels) label where label is not null and btrim(label)<>'' order by 1),'{}') $f$;
create function internal.set_team_person_details_v3_for_actor(target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_titles text[],new_positions text[],new_custom_titles text[],new_custom_positions text[],new_main_position text,
 expected_revision bigint,idempotency_key uuid) returns bigint language plpgsql as $f$
begin
 insert into core.team_person_details(club_id,team_id,club_person_id,functions,custom_titles,revision)
 values(target_club_id,target_team_id,target_person_id,internal.normalize_labels(new_titles),
  internal.normalize_labels(new_custom_titles),expected_revision+1)
 on conflict(team_id,club_person_id) do update set functions=excluded.functions,custom_titles=excluded.custom_titles,revision=excluded.revision;
 return expected_revision+1;
end$f$;
create function internal.list_team_roles_for_actor(target_club_id uuid,target_team_id uuid) returns jsonb language plpgsql as $f$
begin
 return (select jsonb_agg(jsonb_build_object('person_id',details.club_person_id,'main_position',details.main_position,
  'functions',details.functions)) from core.team_person_details details where details.team_id=target_team_id);
end$f$;
create function internal.get_my_team_titles_for_actor() returns jsonb language plpgsql as $f$
begin
 return (select jsonb_agg(jsonb_build_object('team_id',details.team_id,'titles',to_jsonb(details.functions),
      'custom_titles',to_jsonb(coalesce(details.custom_titles,'{}'::text[]))))
  from core.team_person_details details);
end$f$;
insert into core.teams(id) values('${team}');
insert into core.team_person_details(club_id,team_id,club_person_id,functions) values
  ('${club}','${team}','${id(22)}','{head_coach}'),('${club}','${team}','${id(23)}','{head_coach,team_manager}');
insert into auth.actor values('${id(11)}');
`);
await db.exec(fs.readFileSync('supabase/migrations/20261001210000_main_title.sql', 'utf8')
  .replace("notify pgrst,'reload schema';", ''));

const assert = (ok, msg) => { if (!ok) throw new Error(msg); console.log('ok -', msg); };
const title = async (n) => (await db.query(`select main_title t from core.team_person_details where club_person_id=$1`, [id(n)])).rows[0]?.t;
const save = (titles, custom, main, revision) => db.query(
  `select api.set_team_person_details_v4($1,$2,$3,$4,'{}',$5,'{}',$6,null,$7,gen_random_uuid()) r`,
  [club, team, id(21), titles, custom, main, revision]);
const fails = async (fn, pattern) => { try { await fn(); return false; } catch (e) { return pattern.test(e.message); } };

assert((await title(22)) === 'head_coach', 'a single existing title becomes the main title');
assert((await title(23)) === null, 'several titles wait for a choice');
await save(['assistant_coach', 'head_coach'], [], 'head_coach', 0);
assert((await title(21)) === 'head_coach', 'main title saved among the titles');
await save(['assistant_coach'], ['Ungdomsansvarig'], 'Ungdomsansvarig', 1);
assert((await title(21)) === 'Ungdomsansvarig', 'an own title can be the main title');
assert(await fails(() => save(['assistant_coach'], [], 'head_coach', 2), /invalid_main_title/),
  'a main title outside the titles is refused');
await db.exec(`update core.team_person_details set custom_titles='{}' where club_person_id='${id(21)}'`);
assert((await title(21)) === null, 'main title cleared when it is no longer a title');
const roles = (await db.query(`select internal.list_team_roles_for_actor($1,$2) r`, [club, team])).rows[0].r;
assert(roles.some((row) => row.main_title === 'head_coach'), 'roles list carries the main title');
const mine = (await db.query(`select internal.get_my_team_titles_for_actor() r`)).rows[0].r;
assert(mine.some((row) => row.main_title === 'head_coach'), 'own titles carry the main title');
console.log('PASS');
