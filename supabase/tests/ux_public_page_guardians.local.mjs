// UX review: the club public page link and a player's guardians, in
// isolated Postgres with the reduced club of club_referees.local.mjs.
// node supabase/tests/ux_public_page_guardians.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
import { pgcrypto } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/contrib/pgcrypto.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite({ extensions: { pgcrypto } });
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
// Eksjö: admin Ada, leader Lena (P10), Kim (leader of A-lag, becomes
// domaransvarig), club referees Elin (born 2009, account, plays in J) and
// Max (born 2013, no account, guardian Gun). P10 players born 2016, P12
// players born 2012.
const ada = id(1), lena = id(2), kim = id(3), elin = id(4), gun = id(5);
const eksjo = id(10);
const p10 = id(20), aLag = id(21), j = id(22), p12 = id(23);
const pAda = id(31), pLena = id(32), pKim = id(33), pElin = id(34), pMax = id(35), pGun = id(36), pKid = id(37), pBig = id(38);
const home1 = id(40), away1 = id(41), jMatch = id(42), p12Match = id(43);
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
const user = (who, sql, params) => as(who).then(() => asRole('authenticated', () => one(sql, params)));
const notes = async type => (await db.query(`select recipient_profile_id who, payload_ref from internal.notification_outbox
  where event_type=$1 order by created_at, recipient_profile_id`, [type])).rows;
const at = days => `now()+interval '${days} days'`;
try {
  await db.exec(`create role anon;create role authenticated;create role service_role;
  create schema internal;create schema api;create schema core;create schema auth;create schema extensions;create schema audit;
  create extension pgcrypto schema extensions;
  set check_function_bodies = off;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table core.profiles(id uuid primary key,display_name text not null default '',locale text,timezone text);
  insert into core.profiles(id,display_name) values('${ada}','Ada'),('${lena}','Lena'),('${kim}','Kim'),('${elin}','Elin'),('${gun}','Gun');
  create table core.clubs(id uuid primary key,name text,status text default 'active');
  insert into core.clubs values('${eksjo}','IF Eksjö Fotboll','active');
  create table core.teams(id uuid primary key,club_id uuid,name text,status text default 'active',unique(id,club_id));
  insert into core.teams values('${p10}','${eksjo}','P10','active'),('${aLag}','${eksjo}','A-lag','active'),
   ('${j}','${eksjo}','J','active'),('${p12}','${eksjo}','P12','active');
  create table core.club_people(id uuid primary key,club_id uuid,display_name text,status text default 'active',
   birth_date date,birth_year smallint,unique(id,club_id));
  insert into core.club_people(id,club_id,display_name,birth_date,birth_year) values
   ('${pAda}','${eksjo}','Ada Admin',null,null),('${pLena}','${eksjo}','Lena Ledare',null,null),
   ('${pKim}','${eksjo}','Kim Ansvarig',null,null),('${pElin}','${eksjo}','Elin Domare','2009-03-01',null),
   ('${pMax}','${eksjo}','Max Domare',null,2013),('${pGun}','${eksjo}','Gun Förälder',null,null),
   ('${pKid}','${eksjo}','Liten Spelare','2016-05-01',null),('${pBig}','${eksjo}','Stor Spelare',null,2012);
  create table core.person_account_links(profile_id uuid,club_id uuid,club_person_id uuid,state text);
  insert into core.person_account_links values('${ada}','${eksjo}','${pAda}','active'),('${lena}','${eksjo}','${pLena}','active'),
   ('${kim}','${eksjo}','${pKim}','active'),('${elin}','${eksjo}','${pElin}','active'),('${gun}','${eksjo}','${pGun}','active');
  create table core.guardian_relations(id uuid primary key default gen_random_uuid(),club_id uuid,guardian_person_id uuid,
   child_person_id uuid,state text,starts_at timestamptz default now()-interval '1 day',ends_at timestamptz);
  insert into core.guardian_relations(club_id,guardian_person_id,child_person_id,state) values('${eksjo}','${pGun}','${pMax}','active');
  create table core.team_assignments(club_id uuid,team_id uuid,club_person_id uuid,state text default 'active');
  insert into core.team_assignments(club_id,team_id,club_person_id) values('${eksjo}','${p10}','${pKid}'),
   ('${eksjo}','${j}','${pElin}'),('${eksjo}','${p12}','${pBig}');
  create table core.assignments(id uuid primary key default gen_random_uuid(),club_id uuid,team_id uuid,club_person_id uuid,
   role_package text not null,state text default 'active',starts_at timestamptz default now()-interval '1 day',ends_at timestamptz);
  create table core.capability_grants(club_id uuid,assignment_id uuid,capability text,scope_type text,scope_id uuid,
   starts_at timestamptz default now()-interval '1 day',ends_at timestamptz,created_by uuid,check(ends_at is null or ends_at>starts_at));
  create function internal.actor_has_capability(c uuid,t uuid,cap text) returns boolean language sql stable security definer set search_path='' as $$
   select exists(select 1 from core.person_account_links l join core.assignments a on a.club_person_id=l.club_person_id
    join core.capability_grants g on g.assignment_id=a.id where l.profile_id=auth.uid() and a.club_id=c and g.capability=cap
    and g.starts_at<=now() and (g.ends_at is null or g.ends_at>now())
    and ((g.scope_type='club' and g.scope_id=c) or (g.scope_type='team' and g.scope_id=t)))$$;
  create function internal.actor_manages_club(c uuid) returns boolean language sql stable security definer set search_path='' as $$
   select internal.actor_has_capability(c,null,'club.memberships.manage')$$;
  create table core.event_locations(id uuid primary key,name text,pitch text);
  create function internal.event_place_label(place_name text,place_pitch text) returns text language sql immutable set search_path='' as $$
   select nullif(concat_ws(' · ',nullif(btrim(place_name),''),nullif(btrim(place_pitch),'')),'')$$;
  create table core.events(id uuid primary key default gen_random_uuid(),club_id uuid,owning_team_id uuid,event_type text,state text,title text,
   starts_at timestamptz,ends_at timestamptz,timezone text default 'Europe/Stockholm',location_id uuid,opponent_name text,home_away text);
  create function internal.actor_can_manage_event(e uuid) returns boolean language sql stable security definer set search_path='' as $$
   select exists(select 1 from core.events ev where ev.id=e and internal.actor_has_capability(ev.club_id,ev.owning_team_id,'event.manage'))$$;
  create function internal.actor_can_read_event(e uuid) returns boolean language sql stable security definer set search_path='' as $$
   select exists(select 1 from core.events ev join core.person_account_links l on l.club_id=ev.club_id
    where ev.id=e and l.profile_id=auth.uid() and l.state='active')$$;
  create table internal.notification_outbox(id uuid primary key default gen_random_uuid(),club_id uuid,domain_event_id uuid,
   event_type text,aggregate_type text,aggregate_id uuid,recipient_profile_id uuid,recipient_person_id uuid,payload_ref jsonb,
   state text default 'pending',created_at timestamptz default clock_timestamp(),unique(domain_event_id,recipient_person_id));
  create function internal.match_pool_recipients(target_club_id uuid,target_team_id uuid)
   returns table(profile_id uuid,club_person_id uuid) language sql stable security definer set search_path='' as $$
   select distinct l.profile_id,l.club_person_id from core.person_account_links l join core.assignments a on a.club_person_id=l.club_person_id
    join core.capability_grants g on g.assignment_id=a.id where l.club_id=target_club_id and g.capability='event.manage'
    and ((g.scope_type='team' and g.scope_id=target_team_id) or (g.scope_type='club' and g.scope_id=target_club_id))$$;
  grant usage on schema api, internal, core, extensions to authenticated, service_role;`);
  await db.exec(`create table core.club_publication_settings(club_id uuid primary key,mode text,slug text);
  insert into core.club_publication_settings values('${eksjo}','published','if-eksjo-fotboll');
  create function internal.get_person_contact_for_actor(c uuid,t uuid,p uuid) returns jsonb language sql stable security definer set search_path='' as $$
   select jsonb_build_object('phone','070-'||right(p::text,2),'can_see_contact',true)$$;`);
  await db.exec(read('supabase/migrations/20261111090000_ux_public_page_and_guardians.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec(`with a as (insert into core.assignments(club_id,team_id,club_person_id,role_package) values('${eksjo}','${p10}','${pLena}','leader') returning id)
   insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id) select '${eksjo}',a.id,'team.roster.view','team','${p10}' from a;
  insert into core.guardian_relations(club_id,guardian_person_id,child_person_id,state) values('${eksjo}','${pGun}','${pKid}','active');`);
  await db.exec('begin');

  // The public page: members get the slug; others nothing.
  assert.equal(await user(elin, 'select api.get_club_public_page($1)', [eksjo]), 'if-eksjo-fotboll');
  await db.exec(`update core.club_publication_settings set mode='draft'`);
  assert.equal(await user(elin, 'select api.get_club_public_page($1)', [eksjo]), null);

  // Guardians for the team's leader; not for someone outside the team.
  const g = await user(lena, 'select api.get_person_guardians($1,$2,$3)', [eksjo, p10, pKid]);
  assert.deepEqual(g.guardians.map(x => [x.name, x.has_account, x.can_see_contact]), [['Gun Förälder', true, true]]);
  assert.deepEqual(g.message_profile_ids, [gun]);
  await reject(() => user(elin, 'select api.get_person_guardians($1,$2,$3)', [eksjo, p10, pKid]), /not_found/);
  await reject(() => user(lena, 'select api.get_person_guardians($1,$2,$3)', [eksjo, p10, pElin]), /not_found/,
    'Elin is not in P10');
  console.log('public page and guardians: ok');
} finally {
  await db.close();
}
