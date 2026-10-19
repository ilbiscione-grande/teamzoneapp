// REF-02 phase 2: reports, control questions, approval and payout lists for
// club referees, in isolated Postgres with the same reduced club as
// club_referees.local.mjs. node supabase/tests/club_referee_pay.local.mjs
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
  await db.exec('set check_function_bodies = off;' + read('supabase/migrations/20261110090000_club_referee_pay.sql').replace(/notify pgrst[^;]*;/, '') + 'set check_function_bodies = on;');
  const past1 = id(45), past2 = id(46);
  await db.exec(`insert into core.events(id,club_id,owning_team_id,event_type,state,title,starts_at,ends_at,opponent_name,home_away,referee_kind,referee_slots) values
   ('${past1}','${eksjo}','${p10}','match','scheduled','P10 spelad',now()-interval '2 days',now()-interval '2 days'+interval '1 hour','Aneby','home','club',2),
   ('${past2}','${eksjo}','${p10}','match','cancelled','P10 inställd',now()-interval '3 days',now()-interval '3 days'+interval '1 hour','Tranås','home','club',1);`);
  await db.exec('begin');
  await user(ada, 'select api.set_club_referee_coordinator($1,$2,$3)', [eksjo, pKim, true]);
  await user(kim, 'select api.set_club_referee($1,$2,$3)', [eksjo, pElin, true]);
  await user(kim, 'select api.set_club_referee($1,$2,$3)', [eksjo, pMax, true]);

  // Fees: the club's and P10's own; only the domaransvarig sets them.
  await user(kim, 'select api.save_club_referee_fee($1,$2,$3,$4)', [eksjo, null, 150, 100]);
  await user(kim, 'select api.save_club_referee_fee($1,$2,$3,$4)', [eksjo, p10, 200, 120]);
  await reject(() => user(lena, 'select api.save_club_referee_fee($1,$2,$3,$4)', [eksjo, null, 1, 1]), /not_found/);
  const fees = await user(kim, 'select api.get_club_referee_fees($1)', [eksjo]);
  assert.deepEqual(fees.club, { fee_main: 150, fee_assistant: 100 });
  assert.equal(fees.teams.find(t => t.team_name === 'P10').fee_main, 200);

  // Max (guardian Gun answers) is main referee and Elin assistant on the
  // played match; a cancelled match gives no report.
  const rMax = await user(kim, 'select api.propose_event_referee($1,$2,$3)', [past1, 'main', pMax]);
  await user(gun, 'select api.respond_event_referee($1,$2)', [rMax, true]);
  const rElin = await user(kim, 'select api.propose_event_referee($1,$2,$3)', [past1, 'assistant_1', pElin]);
  await user(elin, 'select api.respond_event_referee($1,$2)', [rElin, true]);
  await db.exec(`insert into core.event_referees(event_id,club_id,slot,referee_person_id,referee_club_id,state,proposed_side,kind)
    values('${past2}','${eksjo}','main','${pElin}','${eksjo}','confirmed','team','club')`);

  await reject(() => user(lena, 'select api.list_club_referee_reports($1)', [eksjo]), /not_found/);
  let list = await user(kim, 'select api.list_club_referee_reports($1)', [eksjo]);
  assert.deepEqual(list.reports.map(r => [r.name, r.slot, r.amount, r.state]).sort(),
    [['Elin Domare', 'assistant_1', 120, 'pending'], ['Max Domare', 'main', 200, 'pending']]);
  const repMax = list.reports.find(r => r.name === 'Max Domare').id;
  const repElin = list.reports.find(r => r.name === 'Elin Domare').id;

  // Notes from the referee side: Elin herself, Gun for Max, not Gun for Elin.
  await user(elin, 'select api.note_club_referee_report($1,$2)', [repElin, 'Dömde andra halvlek också']);
  await user(gun, 'select api.note_club_referee_report($1,$2)', [repMax, 'Allt gick bra']);
  await reject(() => user(gun, 'select api.note_club_referee_report($1,$2)', [repElin, 'x']), /not_found/);

  // The control question goes to P10's leaders; Lena answers on the match.
  await user(kim, 'select api.ask_club_referee_control($1)', [repMax]);
  assert.deepEqual((await notes('referee.control_question.v1')).map(n => n.who), [lena]);
  const view = await user(lena, 'select api.get_event_referees($1)', [past1]);
  assert.deepEqual(view.control_questions.map(q => q.name), ['Max Domare']);
  assert.deepEqual((await user(kim, 'select api.get_event_referees($1)', [past1])).control_questions, [],
    'only the team\'s leaders answer');
  await reject(() => user(kim, 'select api.answer_club_referee_control($1,$2)', [repMax, true]), /not_found/);
  await user(lena, 'select api.answer_club_referee_control($1,$2,$3)', [repMax, true, 'Ja, hela matchen']);
  assert.deepEqual((await notes('referee.control_answered.v1')).map(n => n.who).sort(), [ada, kim].sort());
  await reject(() => user(lena, 'select api.answer_club_referee_control($1,$2)', [repMax, false]), /not_pending/);

  // An amount by hand stays when the fee changes; the others follow.
  await user(kim, 'select api.set_club_referee_report_amount($1,$2)', [repElin, 150]);
  assert.equal(await user(kim, 'select api.save_club_referee_fee($1,$2,$3,$4)', [eksjo, p10, 250, 130]), 1);
  list = await user(kim, 'select api.list_club_referee_reports($1)', [eksjo]);
  assert.deepEqual(list.reports.map(r => [r.name, r.amount, r.control_state]).sort(),
    [['Elin Domare', 150, null], ['Max Domare', 250, 'confirmed']]);

  // Reject (the referee side hears) and approve, many at once.
  assert.equal(await user(kim, 'select api.decide_club_referee_reports($1,$2,$3,$4)', [eksjo, [repElin], false, 'Fel match']), 1);
  assert.deepEqual((await notes('referee.report_rejected.v1')).map(n => n.who), [elin]);
  assert.equal(await user(kim, 'select api.decide_club_referee_reports($1,$2,$3)', [eksjo, [repElin, repMax], true]), 2);

  // Domarersättning: Ada appoints Lena; Kim (only domaransvarig) cannot pay.
  await user(ada, 'select api.set_club_referee_payer($1,$2,$3)', [eksjo, pLena, true]);
  await reject(() => user(kim, 'select api.create_club_referee_payout($1)', [eksjo]), /not_found/);
  let payouts = await user(lena, 'select api.list_club_referee_payouts($1)', [eksjo]);
  assert.deepEqual([payouts.ready_count, payouts.ready_total, payouts.payers.map(p => p.name)], [2, 400, ['Lena Ledare']]);
  let payoutId = await user(lena, 'select api.create_club_referee_payout($1)', [eksjo]);
  await reject(() => user(lena, 'select api.create_club_referee_payout($1)', [eksjo]), /nothing_to_pay/);
  await reject(() => user(kim, 'select api.set_club_referee_report_amount($1,$2)', [repMax, 1]), /in_payout/);
  let payout = await user(lena, 'select api.get_club_referee_payout($1)', [payoutId]);
  assert.equal(payout.total, 400);
  assert.deepEqual(payout.lines.map(l => [l.name, l.amount, l.report_count, l.year_total, l.guardians]),
    [['Elin Domare', 150, 1, 150, null], ['Max Domare', 250, 1, 250, 'Gun Förälder']]);
  assert.equal(payout.reports.length, 2);
  assert.equal(payout.limit, 29600);

  // A list not paid can be removed and made again; then paid.
  await user(lena, 'select api.cancel_club_referee_payout($1)', [payoutId]);
  assert.equal((await user(lena, 'select api.list_club_referee_payouts($1)', [eksjo])).ready_count, 2);
  payoutId = await user(lena, 'select api.create_club_referee_payout($1)', [eksjo]);
  await user(lena, 'select api.mark_club_referee_payout_paid($1)', [payoutId]);
  await reject(() => user(lena, 'select api.cancel_club_referee_payout($1)', [payoutId]), /not_pending/);
  assert.deepEqual((await notes('referee.payout_paid.v1')).map(n => n.who).sort(), [elin, gun].sort());
  assert.deepEqual((await user(kim, 'select api.list_club_referee_reports($1,$2)', [eksjo, 'paid'])).reports.length, 2);
  assert.equal((await user(kim, 'select api.list_club_referee_reports($1)', [eksjo])).reports.length, 0, 'paid ones leave the list');

  // The referee's own pay, and the guardian's view of the child's.
  const mine = await user(elin, 'select api.list_my_referee_reports()');
  assert.deepEqual(mine.map(p => [p.name, p.year_total, p.reports[0].state, p.can_note]), [['Elin Domare', 150, 'paid', true]]);
  const gunView = await user(gun, 'select api.list_my_referee_reports()');
  assert.deepEqual(gunView.map(p => [p.name, p.year_total]), [['Max Domare', 250]]);
  assert.deepEqual(await user(lena, 'select api.list_my_referee_reports()'), []);

  // The summary: Lena pays, Kim manages.
  const lenaClubs = (await user(lena, 'select api.get_my_referee_summary()')).coordinator_clubs;
  assert.deepEqual(lenaClubs.map(c => [c.can_manage, c.can_pay]), [[false, true]]);
  const kimClubs = (await user(kim, 'select api.get_my_referee_summary()')).coordinator_clubs;
  assert.deepEqual(kimClubs.map(c => [c.can_manage, c.can_pay, c.pending_reports]), [[true, false, 0]]);

  // Push and deep links.
  assert.equal(await one(`select internal.notification_title('referee.payout_paid.v1')`), 'Domarersättningen är utbetald');
  console.log('club referee pay: ok');
} finally {
  await db.close();
}
