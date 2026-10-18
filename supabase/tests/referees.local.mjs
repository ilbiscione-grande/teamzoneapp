// REF-01 referees: the real migration in isolated Postgres, with clubs,
// roles, events and the outbox reduced to what it reads.
// node supabase/tests/referees.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
import { pgcrypto } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/contrib/pgcrypto.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite({ extensions: { pgcrypto } });
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
// Eksjö: leader Lena (team J). Njudungs FDK: referees Anna (account) and Bo
// (no account), assigner Ulla, referee Cia (account). Follower Fia.
const lena = id(1), anna = id(2), ulla = id(3), cia = id(4), fia = id(5), otherLeader = id(6);
const eksjo = id(10), fdk = id(11), alby = id(12);
const teamJ = id(20), fdkTeam = id(21), albyTeam = id(22);
const pLena = id(31), pAnna = id(32), pBo = id(33), pUlla = id(34), pCia = id(35), pOther = id(36);
const match1 = id(40), match2 = id(41), training = id(42), albyMatch = id(43);
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
const user = (who, sql, params) => as(who).then(() => asRole('authenticated', () => one(sql, params)));
const notes = async type => (await db.query(`select recipient_profile_id who, payload_ref from internal.notification_outbox
  where event_type=$1 order by created_at, recipient_profile_id`, [type])).rows;
try {
  await db.exec(`create role anon;create role authenticated;create role service_role;
  create schema internal;create schema api;create schema core;create schema auth;create schema extensions;create schema audit;
  create extension pgcrypto schema extensions;
  set check_function_bodies = off;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table core.profiles(id uuid primary key,display_name text not null default '',locale text,timezone text);
  insert into core.profiles(id,display_name) values('${lena}','Lena'),('${anna}','Anna'),('${ulla}','Ulla'),('${cia}','Cia'),('${fia}','Fia'),('${otherLeader}','Olle');
  create table core.clubs(id uuid primary key,name text,status text default 'active');
  insert into core.clubs values('${eksjo}','IF Eksjö Fotboll','active'),('${fdk}','Njudungs FDK','active'),('${alby}','Alby IF','active');
  create table core.teams(id uuid primary key,club_id uuid,name text,status text default 'active');
  insert into core.teams values('${teamJ}','${eksjo}','J','active'),('${fdkTeam}','${fdk}','Domare','active'),('${albyTeam}','${alby}','P12','active');
  create table core.club_people(id uuid primary key,club_id uuid,display_name text,status text default 'active',birth_date date,birth_year smallint,unique(id,club_id));
  insert into core.club_people(id,club_id,display_name,status) values('${pLena}','${eksjo}','Lena Ledare','active'),('${pAnna}','${fdk}','Anna Domare','active'),
   ('${pBo}','${fdk}','Bo Domare','active'),('${pUlla}','${fdk}','Ulla Tillsättare','active'),('${pCia}','${fdk}','Cia Domare','active'),
   ('${pOther}','${alby}','Olle Ledare','active');
  create table core.guardian_relations(club_id uuid,guardian_person_id uuid,child_person_id uuid,state text,starts_at timestamptz,ends_at timestamptz);
  create table core.team_assignments(club_id uuid,team_id uuid,club_person_id uuid,state text);
  create function internal.actor_manages_club(c uuid) returns boolean language sql stable as $$select false$$;
  create table core.person_account_links(profile_id uuid,club_id uuid,club_person_id uuid,state text);
  insert into core.person_account_links values('${lena}','${eksjo}','${pLena}','active'),('${anna}','${fdk}','${pAnna}','active'),
   ('${ulla}','${fdk}','${pUlla}','active'),('${cia}','${fdk}','${pCia}','active'),('${otherLeader}','${alby}','${pOther}','active');
  create table core.assignments(id uuid primary key default gen_random_uuid(),club_id uuid,team_id uuid,club_person_id uuid,
   role_package text not null check (role_package in ('player','leader','guardian','club_functionary','guest')),
   state text default 'active',starts_at timestamptz default now()-interval '1 day',ends_at timestamptz);
  create table core.capability_grants(assignment_id uuid,club_id uuid,capability text,scope_type text,scope_id uuid,
   starts_at timestamptz default now()-interval '1 day',ends_at timestamptz);
  create function internal.actor_has_capability(c uuid,t uuid,cap text) returns boolean language sql stable security definer set search_path='' as $$
   select exists(select 1 from core.person_account_links l join core.assignments a on a.club_person_id=l.club_person_id
    join core.capability_grants g on g.assignment_id=a.id where l.profile_id=auth.uid() and a.club_id=c and g.capability=cap
    and ((g.scope_type='club' and g.scope_id=c) or (g.scope_type='team' and g.scope_id=t)))$$;
  create table core.event_locations(id uuid primary key,name text,pitch text);
  insert into core.event_locations values('${id(50)}','Eksjö IP','Plan 1');
  create function internal.event_place_label(place_name text,place_pitch text) returns text language sql immutable set search_path='' as $$
   select nullif(concat_ws(' · ',nullif(btrim(place_name),''),nullif(btrim(place_pitch),'')),'')$$;
  create table core.events(id uuid primary key,club_id uuid,owning_team_id uuid,event_type text,state text,title text,
   starts_at timestamptz,ends_at timestamptz,timezone text default 'Europe/Stockholm',location_id uuid,opponent_name text,home_away text);
  insert into core.events values
   ('${match1}','${eksjo}','${teamJ}','match','scheduled','Match mot Vetlanda',now()+interval '5 days',now()+interval '5 days 2 hours','Europe/Stockholm','${id(50)}','Vetlanda FF','home'),
   ('${match2}','${eksjo}','${teamJ}','match','scheduled','Match mot Nässjö',now()+interval '10 days',now()+interval '10 days 2 hours','Europe/Stockholm',null,'Nässjö FF','away'),
   ('${training}','${eksjo}','${teamJ}','training','scheduled','Träning',now()+interval '2 days',now()+interval '2 days 1 hour','Europe/Stockholm',null,null,null),
   ('${albyMatch}','${alby}','${albyTeam}','match','scheduled','Match',now()+interval '6 days',now()+interval '6 days 2 hours','Europe/Stockholm',null,'Bro BK','home');
  create function internal.actor_can_manage_event(e uuid) returns boolean language sql stable security definer set search_path='' as $$
   select exists(select 1 from core.events ev where ev.id=e and internal.actor_has_capability(ev.club_id,ev.owning_team_id,'event.manage'))$$;
  create function internal.actor_can_read_event(e uuid) returns boolean language sql stable security definer set search_path='' as $$
   select exists(select 1 from core.events ev join core.person_account_links l on l.club_id=ev.club_id
    where ev.id=e and l.profile_id=auth.uid() and l.state='active')$$;
  create table internal.notification_outbox(id uuid primary key default gen_random_uuid(),club_id uuid,domain_event_id uuid,
   event_type text,aggregate_type text,aggregate_id uuid,recipient_profile_id uuid,recipient_person_id uuid,payload_ref jsonb,
   state text default 'pending',created_at timestamptz default clock_timestamp(),unique(domain_event_id,recipient_person_id));
  -- The match pool's recipients: event managers of the team (as in 20261102090000).
  create function internal.match_pool_recipients(target_club_id uuid,target_team_id uuid)
   returns table(profile_id uuid,club_person_id uuid) language sql stable security definer set search_path='' as $$
   select distinct l.profile_id,l.club_person_id from core.person_account_links l join core.assignments a on a.club_person_id=l.club_person_id
    join core.capability_grants g on g.assignment_id=a.id where l.club_id=target_club_id and g.capability='event.manage'
    and ((g.scope_type='team' and g.scope_id=target_team_id) or (g.scope_type='club' and g.scope_id=target_club_id))$$;
  grant usage on schema api, internal, core, extensions to authenticated, service_role;`);
  await db.exec(read('supabase/migrations/20261108090000_referees.sql').replace(/notify pgrst[^;]*;/, ''));
  // REF-02 rewrites several of these functions: the federation flows still hold.
  await db.exec(read('supabase/migrations/20261109090000_club_referees.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec(`set check_function_bodies = on;
  with a as (insert into core.assignments(club_id,team_id,club_person_id,role_package) values('${eksjo}','${teamJ}','${pLena}','leader') returning id)
   insert into core.capability_grants select a.id,'${eksjo}','event.manage','team','${teamJ}' from a;
  with a as (insert into core.assignments(club_id,team_id,club_person_id,role_package) values('${alby}','${albyTeam}','${pOther}','leader') returning id)
   insert into core.capability_grants select a.id,'${alby}','event.manage','team','${albyTeam}' from a;
  insert into core.assignments(club_id,team_id,club_person_id,role_package) values
   ('${fdk}','${fdkTeam}','${pAnna}','referee'),('${fdk}','${fdkTeam}','${pBo}','referee'),
   ('${fdk}','${fdkTeam}','${pCia}','referee'),('${fdk}','${fdkTeam}','${pUlla}','referee_assigner');`);
  await db.exec('begin');

  // The roles exist and labels are allowed.
  assert.equal(await one(`select count(*)::int from core.assignments where role_package in ('referee','referee_assigner')`), 4);

  // A leader sees the places and finds referees; a follower cannot search.
  let view = await user(lena, 'select api.get_event_referees($1)', [match1]);
  assert.deepEqual([view.slots, view.can_manage, view.referees.length], [0, true, 0]);
  await user(lena, 'select api.set_event_referee_slots($1,$2)', [match1, 3]);
  await reject(() => user(lena, 'select api.set_event_referee_slots($1,$2)', [match1, 4]), /invalid_input/);
  await reject(() => user(otherLeader, 'select api.set_event_referee_slots($1,$2)', [match1, 1]), /not_found/);
  const found = await user(lena, 'select api.search_referees($1)', ['domare']);
  assert.deepEqual(found.map(r => [r.name, r.club_name]), [['Anna Domare', 'Njudungs FDK'], ['Bo Domare', 'Njudungs FDK'], ['Cia Domare', 'Njudungs FDK']]);
  assert.equal(found.find(r => r.name === 'Bo Domare').confirmable, true, 'the assigner answers for Bo');
  await reject(() => user(fia, 'select api.search_referees($1)', ['domare']), /not_found/);

  // Proposals: Anna waits for her answer, Bo for the assigner's, a written-in
  // referee is confirmed at once. A place is taken once.
  const rAnna = await user(lena, 'select api.propose_event_referee($1,$2,$3)', [match1, 'main', pAnna]);
  const rBo = await user(lena, 'select api.propose_event_referee($1,$2,$3)', [match1, 'assistant_1', pBo]);
  const rExt = await user(lena, 'select api.propose_event_referee($1,$2,$3,$4)', [match1, 'assistant_2', null, 'Kalle Extern']);
  await reject(() => user(lena, 'select api.propose_event_referee($1,$2,$3)', [match1, 'main', pCia]), /slot_taken/);
  await reject(() => user(lena, 'select api.propose_event_referee($1,$2,$3)', [training, 'main', pCia]), /not_a_match/);
  await reject(() => user(lena, 'select api.propose_event_referee($1,$2,$3)', [match2, 'main', pLena]), /not_a_referee/);
  view = await user(lena, 'select api.get_event_referees($1)', [match1]);
  assert.deepEqual(view.referees.map(r => [r.slot, r.name, r.state]), [
    ['main', 'Anna Domare', 'awaiting_referee'], ['assistant_1', 'Bo Domare', 'awaiting_referee'],
    ['assistant_2', 'Kalle Extern', 'confirmed']]);
  assert.deepEqual((await notes('referee.proposed.v1')).map(n => n.who).sort(), [anna, ulla, ulla].sort(),
    'Anna and the assigner for Anna, the assigner for Bo');
  assert.equal((await notes('referee.proposed.v1'))[0].payload_ref.side, 'referee');

  // Anna answers herself; the assigner answers for Bo; the team is told.
  let mine = await user(anna, 'select api.list_my_referee_assignments()');
  assert.deepEqual(mine.map(r => [r.slot, r.awaiting_me, r.match.team_name, r.match.location]), [['main', true, 'J', 'Eksjö IP · Plan 1']]);
  await reject(() => user(cia, 'select api.respond_event_referee($1,$2)', [rAnna, true]), /not_found/);
  assert.equal(await user(anna, 'select api.respond_event_referee($1,$2)', [rAnna, true]), 'confirmed');
  assert.equal(await user(ulla, 'select api.respond_event_referee($1,$2)', [rBo, false]), 'declined');
  assert.deepEqual((await notes('referee.confirmed.v1')).map(n => [n.who, n.payload_ref.side]), [[lena, 'team']]);
  assert.deepEqual((await notes('referee.declined.v1')).map(n => n.who), [lena]);
  await reject(() => user(lena, 'select api.set_event_referee_slots($1,$2)', [match1, 2]), /slots_in_use/);

  // The referee side: search matches, offer to referee, the team answers.
  await reject(() => user(fia, 'select api.search_referee_matches($1,$2,$3)', ['', null, null]), /not_found/);
  const matches = await user(cia, 'select api.search_referee_matches($1,$2,$3)', ['', null, null]);
  assert.deepEqual(matches.map(m => m.event_id), [match1, albyMatch, match2], 'scheduled matches only, by time');
  assert.equal(matches[0].taken.length, 2);
  assert.equal((await user(cia, 'select api.search_referee_matches($1,$2,$3)', ['nässjö', null, null])).length, 1);
  await reject(() => user(cia, 'select api.request_event_referee($1,$2,$3)', [match2, 'main', pAnna]), /not_found/);
  const rCia = await user(cia, 'select api.request_event_referee($1,$2,$3)', [match2, 'main', pCia]);
  await reject(() => user(cia, 'select api.request_event_referee($1,$2,$3)', [match2, 'assistant_1', pCia]), /invalid_input/,
    'match2 has no places set: only the first');
  assert.deepEqual((await notes('referee.requested.v1')).map(n => [n.who, n.payload_ref.side]), [[lena, 'team']]);
  // The assigner offers Bo (no account) for an open place.
  const people = await user(ulla, 'select api.list_my_referee_people()');
  assert.deepEqual(people.map(p => p.name), ['Anna Domare', 'Bo Domare', 'Cia Domare']);
  const rBo2 = await user(ulla, 'select api.request_event_referee($1,$2,$3)', [match1, 'assistant_1', pBo]);
  await reject(() => user(cia, 'select api.respond_event_referee($1,$2)', [rCia, true]), /not_found/);
  assert.equal(await user(lena, 'select api.respond_event_referee($1,$2)', [rCia, true]), 'confirmed');
  assert.equal(await user(lena, 'select api.respond_event_referee($1,$2)', [rBo2, true]), 'confirmed');
  assert.deepEqual((await notes('referee.confirmed.v1')).filter(n => n.payload_ref.side === 'referee').map(n => n.who).sort(),
    [cia, ulla, ulla].sort());

  // Who sees a match's referees: the team, the referee; not an outsider.
  assert.equal((await user(cia, 'select api.get_event_referees($1)', [match2])).referees.length, 1);
  await reject(() => user(otherLeader, 'select api.get_event_referees($1)', [match2]), /not_found/);

  // Withdrawing: the referee withdraws, the team is told.
  await user(cia, 'select api.withdraw_event_referee($1)', [rCia]);
  assert.equal(await one(`select state from core.event_referees where id='${rCia}'`), 'withdrawn');
  assert.deepEqual((await notes('referee.withdrawn.v1')).map(n => n.who), [lena]);
  await reject(() => user(fia, 'select api.withdraw_event_referee($1)', [rAnna]), /not_found/);

  // Notification links: the team opens the match, the referee the home page.
  assert.equal(await one(`select internal.notification_deep_link(o) from internal.notification_outbox o
    where event_type='referee.requested.v1' limit 1`), '/calendar/event/' + match2);
  assert.equal(await one(`select internal.notification_deep_link(o) from internal.notification_outbox o
    where event_type='referee.proposed.v1' limit 1`), '/home');
  assert.equal(await one(`select internal.notification_title('referee.proposed.v1')`), 'Förfrågan om att döma');
  console.log('referees: ok');
} finally {
  await db.close();
}
