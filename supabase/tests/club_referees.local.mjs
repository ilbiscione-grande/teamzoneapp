// REF-02 club referees: the referee migrations in isolated Postgres, with
// clubs, people, guardians, roles, events and the outbox reduced to what
// they read. node supabase/tests/club_referees.local.mjs
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
  await db.exec(read('supabase/migrations/20261108090000_referees.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec(read('supabase/migrations/20261109090000_club_referees.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec(`set check_function_bodies = on;
  with a as (insert into core.assignments(club_id,team_id,club_person_id,role_package) values('${eksjo}',null,'${pAda}','club_functionary') returning id)
   insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id) select '${eksjo}',a.id,'club.memberships.manage','club','${eksjo}' from a;
  with a as (insert into core.assignments(club_id,team_id,club_person_id,role_package) values('${eksjo}','${p10}','${pLena}','leader') returning id)
   insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id) select '${eksjo}',a.id,'event.manage','team','${p10}' from a;
  insert into core.assignments(club_id,team_id,club_person_id,role_package) values('${eksjo}','${aLag}','${pKim}','leader');
  insert into core.events(id,club_id,owning_team_id,event_type,state,title,starts_at,ends_at,opponent_name,home_away) values
   ('${home1}','${eksjo}','${p10}','match','scheduled','P10 hemma',${at(5)},${at(5)}+interval '1 hour','Vetlanda','home'),
   ('${away1}','${eksjo}','${p10}','match','scheduled','P10 borta',${at(6)},${at(6)}+interval '1 hour','Nässjö','away'),
   ('${jMatch}','${eksjo}','${j}','match','scheduled','J spelar',${at(5)},${at(5)}+interval '2 hours','Tranås','home'),
   ('${p12Match}','${eksjo}','${p12}','match','scheduled','P12 hemma',${at(8)},${at(8)}+interval '1 hour','Sävsjö','home');`);
  await db.exec('begin');

  // Domaransvarig: only the club's administrator appoints; Kim then manages.
  await reject(() => user(kim, 'select api.get_club_referee_board($1,$2,$3)', [eksjo, null, null]), /not_found/);
  await reject(() => user(lena, 'select api.set_club_referee_coordinator($1,$2,$3)', [eksjo, pKim, true]), /not_found/);
  await user(ada, 'select api.set_club_referee_coordinator($1,$2,$3)', [eksjo, pKim, true]);
  await reject(() => user(ada, 'select api.set_club_referee_coordinator($1,$2,$3)', [eksjo, pElin, true]), /no_assignment/);
  let board = await user(kim, 'select api.get_club_referee_board($1,$2,$3)', [eksjo, null, null]);
  assert.equal(board.can_appoint_coordinators, false);
  assert.equal(board.matches.length, 4, 'the club\'s matches in the coming two weeks');

  // Club referees, with training; a non-member of the club is refused.
  await user(kim, 'select api.set_club_referee($1,$2,$3,$4,$5)', [eksjo, pElin, true, '2026-03-01', '2027-03-01']);
  await user(kim, 'select api.set_club_referee($1,$2,$3)', [eksjo, pMax, true]);
  await reject(() => user(lena, 'select api.set_club_referee($1,$2,$3)', [eksjo, pElin, false]), /not_found/);
  board = await user(kim, 'select api.get_club_referee_board($1,$2,$3)', [eksjo, null, null]);
  assert.deepEqual(board.referees.map(r => [r.name, r.age >= 17, r.trained_on]), [['Elin Domare', true, '2026-03-01'], ['Max Domare', false, null]]);
  assert.deepEqual(board.coordinators.map(c => c.name), ['Kim Ansvarig']);
  const people = await user(kim, 'select api.search_club_people_for_referees($1,$2)', [eksjo, 'spelare']);
  assert.deepEqual(people.map(p => [p.name, p.team_names, p.club_referee]), [['Liten Spelare', 'P10', false], ['Stor Spelare', 'P12', false]]);
  await reject(() => user(lena, 'select api.search_club_people_for_referees($1,$2)', [eksjo, 'spelare']), /not_found/);

  // Team defaults: P10 home matches want one club referee; away does not.
  assert.equal(await user(kim, 'select api.save_team_referee_default($1,$2,$3,$4)', [p10, 'club', 1, true]), 1);
  assert.deepEqual((await db.query(`select id, referee_kind, referee_slots from core.events where owning_team_id='${p10}' order by starts_at`)).rows
    .map(r => [r.id, r.referee_kind, r.referee_slots]), [[home1, 'club', 1], [away1, null, 0]]);
  await db.exec(`insert into core.events(id,club_id,owning_team_id,event_type,state,title,starts_at,ends_at,home_away)
    values('${id(44)}','${eksjo}','${p10}','match','scheduled','Ny',${at(9)},${at(9)}+interval '1 hour','home')`);
  assert.equal(await one(`select referee_kind from core.events where id='${id(44)}'`), 'club', 'a new match follows the rule');
  await user(kim, 'select api.save_team_referee_default($1,$2,$3,$4)', [p12, 'club', 1, true]);

  // Suggestions: Elin plays at the same time as home1 (clash), both old enough.
  let candidates = await user(kim, 'select api.list_club_referee_candidates($1)', [home1]);
  assert.deepEqual(candidates.map(c => [c.name, c.age_ok, c.clash]), [['Max Domare', true, false], ['Elin Domare', true, true]]);
  candidates = await user(kim, 'select api.list_club_referee_candidates($1)', [p12Match]);
  assert.equal(candidates.find(c => c.name === 'Max Domare').age_ok, false, 'born 2013 vs players born 2012');

  // Kim proposes Max (13): his guardian answers. Lena cannot propose a club referee? She can as the team.
  const rMax = await user(kim, 'select api.propose_event_referee($1,$2,$3)', [home1, 'main', pMax]);
  assert.deepEqual((await notes('referee.proposed.v1')).map(n => n.who), [gun]);
  await reject(() => user(elin, 'select api.respond_event_referee($1,$2)', [rMax, true]), /not_found/);
  assert.equal(await user(gun, 'select api.respond_event_referee($1,$2)', [rMax, true]), 'confirmed');
  assert.equal(await one(`select kind from core.event_referees where id='${rMax}'`), 'club');
  // The coordinator cannot propose federation referees or write names in.
  await reject(() => user(kim, 'select api.propose_event_referee($1,$2,$3,$4)', [home1, 'assistant_1', null, 'Extern']), /not_found/);

  // Elin (17) sees open club matches and signs up; Kim approves.
  const open = await user(elin, 'select api.list_open_club_matches()');
  assert.deepEqual(open.map(m => m.event_id).sort(), [id(44), p12Match].sort(), 'home1 is full; P12 needs age 3 years over 2012: Elin 2009 ok');
  const rElin = await user(elin, 'select api.request_club_referee($1,$2,$3)', [p12Match, 'main', pElin]);
  await reject(() => user(gun, 'select api.request_club_referee($1,$2,$3)', [id(44), 'main', pElin]), /not_found/,
    'Gun is not Elin\'s guardian');
  await reject(() => user(gun, 'select api.request_club_referee($1,$2,$3)', [p12Match, 'main', pMax]), /slot_taken|too_young/);
  assert.deepEqual((await notes('referee.club_requested.v1')).map(n => n.who).sort(), [ada, kim].sort());
  await reject(() => user(lena, 'select api.respond_event_referee($1,$2)', [rElin, true]), /not_found/);
  assert.equal(await user(kim, 'select api.respond_event_referee($1,$2)', [rElin, true]), 'confirmed');
  assert.equal((await notes('referee.confirmed.v1')).filter(n => n.payload_ref.side === 'referee').length, 1);

  // Too young: Max for P12 (players born 2012) is refused.
  await db.exec(`update core.events set referee_slots=2 where id='${p12Match}'`);
  await reject(() => user(gun, 'select api.request_club_referee($1,$2,$3)', [p12Match, 'assistant_1', pMax]), /too_young/);

  // Summary and assignments for the referee and the guardian.
  assert.equal((await user(elin, 'select api.get_my_referee_summary()')).club_referee, true);
  assert.equal((await user(gun, 'select api.get_my_referee_summary()')).club_referee, true, 'Gun answers for Max');
  assert.deepEqual((await user(kim, 'select api.get_my_referee_summary()')).coordinator_clubs.map(c => c.club_name), ['IF Eksjö Fotboll']);
  assert.equal((await user(lena, 'select api.get_my_referee_summary()')).club_referee, false);
  assert.equal((await user(gun, 'select api.list_my_referee_assignments()')).length, 1);
  assert.equal((await user(elin, 'select api.list_my_referee_people()'))[0].club_referee, true);

  // Kind per match; "none" refused while referees are placed.
  await reject(() => user(kim, 'select api.set_event_referee_kind($1,$2)', [home1, 'none']), /slots_in_use/);
  await user(lena, 'select api.set_event_referee_kind($1,$2)', [away1, 'federation']);
  assert.equal(await one(`select referee_slots from core.events where id='${away1}'`), 1);

  // Withdrawing by the coordinator tells the referee side; ending the role.
  await user(kim, 'select api.withdraw_event_referee($1)', [rElin]);
  assert.deepEqual((await notes('referee.withdrawn.v1')).map(n => n.who), [elin]);
  await user(kim, 'select api.set_club_referee($1,$2,$3)', [eksjo, pElin, false]);
  assert.equal((await user(elin, 'select api.get_my_referee_summary()')).club_referee, false);
  // The whole test is one transaction (now() stands still): the grant is
  // dated back so that ending it "now" lies after its start.
  await db.exec(`update core.capability_grants set starts_at = now() - interval '1 hour' where capability = 'club.referees.manage'`);
  await user(ada, 'select api.set_club_referee_coordinator($1,$2,$3)', [eksjo, pKim, false]);
  await reject(() => user(kim, 'select api.get_club_referee_board($1,$2,$3)', [eksjo, null, null]), /not_found/);
  console.log('club referees: ok');
} finally {
  await db.close();
}
