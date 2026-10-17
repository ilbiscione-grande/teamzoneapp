// POOL-01 matchpoolen: the real migration in isolated Postgres, with clubs,
// capabilities, the outbox and the event command reduced to what it reads.
// node supabase/tests/match_pool.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
import { pgcrypto } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/contrib/pgcrypto.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite({ extensions: { pgcrypto } });
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
// Alby (verified): coach A for P2012. Bro (unverified): coach B for P2012,
// coach C for F2013. Follower: no capability anywhere.
const coachA = id(1), coachB = id(2), coachC = id(3), follower = id(4), coachA2 = id(5);
const alby = id(10), bro = id(11);
const albyP12 = id(20), broP12 = id(21), broF13 = id(22);
const personA = id(31), personB = id(32), personC = id(33), personA2 = id(35);
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
const user = (who, sql, params) => as(who).then(() => asRole('authenticated', () => one(sql, params)));
const key = n => id(9000 + n);
const days = n => new Date(Date.now() + n * 86400000);
const localDate = n => days(n).toLocaleDateString('sv-SE', { timeZone: 'Europe/Stockholm' });
try {
  await db.exec(`create role anon;create role authenticated;create role service_role;
  create schema internal;create schema api;create schema core;create schema auth;create schema extensions;create schema cron;
  create extension pgcrypto schema extensions;
  set check_function_bodies = off;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table cron.job(jobid bigserial primary key,jobname text,schedule text,command text);
  create function cron.schedule(n text,s text,c text) returns bigint language sql as $$insert into cron.job(jobname,schedule,command) values(n,s,c) returning jobid$$;
  create function cron.unschedule(j bigint) returns boolean language sql as $$delete from cron.job where jobid=j returning true$$;
  create table core.profiles(id uuid primary key,display_name text not null default '',locale text,timezone text);
  insert into core.profiles values('${coachA}','Anna',null,null),('${coachB}','Bo',null,null),('${coachC}','Cia',null,null),
   ('${follower}','Följare',null,null),('${coachA2}','Anders',null,null);
  create table core.clubs(id uuid primary key,name text,status text default 'active',verification_status text default 'unofficial');
  insert into core.clubs values('${alby}','Alby IF','active','official'),('${bro}','Bro BK','active','unofficial');
  create table core.teams(id uuid primary key,club_id uuid,name text,status text default 'active',unique(id,club_id));
  insert into core.teams values('${albyP12}','${alby}','P2012','active'),('${broP12}','${bro}','P2012','active'),('${broF13}','${bro}','F2013','active');
  create table core.team_profiles(team_id uuid primary key,age_class text);
  insert into core.team_profiles values('${albyP12}','P12');
  create table core.person_account_links(profile_id uuid,club_id uuid,club_person_id uuid,state text);
  insert into core.person_account_links values('${coachA}','${alby}','${personA}','active'),('${coachB}','${bro}','${personB}','active'),
   ('${coachC}','${bro}','${personC}','active'),('${follower}','${bro}','${id(34)}','active'),('${coachA2}','${alby}','${personA2}','active');
  create table core.assignments(id uuid primary key default gen_random_uuid(),club_person_id uuid,club_id uuid,state text default 'active',
   starts_at timestamptz default now()-interval '1 day',ends_at timestamptz);
  create table core.capability_grants(assignment_id uuid,club_id uuid,capability text,scope_type text,scope_id uuid,
   starts_at timestamptz default now()-interval '1 day',ends_at timestamptz);
  with a as (insert into core.assignments(club_person_id,club_id) values('${personA}','${alby}') returning id)
   insert into core.capability_grants select a.id,'${alby}','event.manage','team','${albyP12}' from a;
  with a as (insert into core.assignments(club_person_id,club_id) values('${personA2}','${alby}') returning id)
   insert into core.capability_grants select a.id,'${alby}','event.manage','team','${albyP12}' from a;
  with a as (insert into core.assignments(club_person_id,club_id) values('${personB}','${bro}') returning id)
   insert into core.capability_grants select a.id,'${bro}','event.manage','team','${broP12}' from a;
  with a as (insert into core.assignments(club_person_id,club_id) values('${personC}','${bro}') returning id)
   insert into core.capability_grants select a.id,'${bro}','event.manage','team','${broF13}' from a;
  create function internal.actor_has_capability(c uuid,t uuid,cap text) returns boolean language sql stable security definer set search_path='' as $$
   select exists(select 1 from core.person_account_links l join core.assignments a on a.club_person_id=l.club_person_id
    join core.capability_grants g on g.assignment_id=a.id where l.profile_id=auth.uid() and a.club_id=c and l.state='active'
    and a.state='active' and (g.ends_at is null or g.ends_at>now()) and g.capability=cap and ((g.scope_type='club' and g.scope_id=c) or (g.scope_type='team' and g.scope_id=t)))$$;
  create table internal.notification_outbox(id uuid primary key default gen_random_uuid(),club_id uuid,domain_event_id uuid,
   event_type text,aggregate_type text,aggregate_id uuid,recipient_profile_id uuid,recipient_person_id uuid,payload_ref jsonb,
   state text default 'pending',created_at timestamptz default now(),unique(domain_event_id,recipient_person_id));
  -- The event command, as the acting leader: records who created what.
  create table core.events(id uuid primary key default gen_random_uuid(),club_id uuid,owning_team_id uuid,state text,
   title text,starts_at timestamptz,created_by uuid,location text,fields jsonb,audience text[],revision bigint default 1);
  create function internal.actor_can_manage_event(e uuid) returns boolean language sql stable security definer set search_path='' as $$
   select exists(select 1 from core.events ev where ev.id=e and internal.actor_has_capability(ev.club_id,ev.owning_team_id,'event.manage'))$$;
  create function internal.transition_event_for_actor(e uuid,target_state text,expected_revision bigint,reason text,idempotency_key uuid)
   returns bigint language plpgsql security definer set search_path='' as $$
   begin
    if not internal.actor_can_manage_event(e) then raise insufficient_privilege using message='not_found'; end if;
    update core.events set state=target_state, revision=revision+1 where id=e and revision=expected_revision;
    return expected_revision+1;
   end$$;
  create function internal.create_event_v2_for_actor(target_club_id uuid, target_team_id uuid, new_title text, new_description text,
   new_event_type text, new_state text, new_starts_at timestamptz, new_ends_at timestamptz, new_all_day boolean, new_timezone text,
   audience_types text[], location_name text, recurrence_frequency text, recurrence_interval integer, recurrence_count integer,
   typed_fields jsonb, idempotency_key uuid) returns uuid language plpgsql security definer set search_path='' as $$
   declare made uuid;
   begin
    if not internal.actor_has_capability(target_club_id,target_team_id,'event.manage') then raise insufficient_privilege using message='not_found'; end if;
    insert into core.events(club_id,owning_team_id,state,title,starts_at,created_by,location,fields,audience)
    values(target_club_id,target_team_id,new_state,new_title,new_starts_at,auth.uid(),location_name,typed_fields,audience_types) returning id into made;
    return made;
   end$$;
  grant usage on schema api, internal, core, extensions to authenticated, service_role;`);
  await db.exec(read('supabase/migrations/20261102090000_match_pool.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec(read('supabase/migrations/20261103090000_match_pool_app.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec(read('supabase/migrations/20261104090000_match_pool_watches_cancellation.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec(read('supabase/migrations/20261105090000_match_pool_age_groups.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec('set check_function_bodies = on');
  await db.exec('begin');

  // Only leaders: a follower account is refused.
  await reject(() => user(follower, 'select api.get_match_pool()'), /not_leader/);
  const page = await user(coachA, 'select api.get_match_pool()');
  assert.equal(page.teams.length, 1);
  assert.equal(page.teams[0].verified, true);
  assert.equal(page.teams[0].age_class, 'P12');

  // Starting points, rounded to about a kilometre.
  await user(coachA, 'select api.save_match_pool_base($1,$2,$3,$4)', [albyP12, 'Alby, Botkyrka', 59.23891, 17.84512]);
  await user(coachB, 'select api.save_match_pool_base($1,$2,$3,$4)', [broP12, 'Bro, Upplands-Bro', 59.51132, 17.63611]);
  await user(coachC, 'select api.save_match_pool_base($1,$2,$3,$4)', [broF13, 'Bro, Upplands-Bro', 59.51132, 17.63611]);
  assert.equal(await one(`select latitude::text from internal.match_pool_bases where team_id='${albyP12}'`), '59.24');
  await reject(() => user(coachA, 'select api.save_match_pool_base($1,$2,$3,$4)', [broP12, 'X', 59, 17]), /not_found/);

  // A home slot from Alby; the venue stays hidden from others.
  const homeSlot = {
    kind: 'home_slot', starts_at: days(10).toISOString(), ends_at: new Date(days(10).getTime() + 90 * 60000).toISOString(),
    place_label: 'Alby, Botkyrka', latitude: 59.23891, longitude: 17.84512, venue_name: 'Alby IP konstgräs',
    venue_surface: 'artificial', match_format: '7v7', age_class: 'P12', gender: 'boys', level: 'intermediate', note: 'Gärna lite tuffare motstånd',
  };
  const listing = await user(coachA, 'select api.create_match_pool_listing($1,$2,$3)', [albyP12, homeSlot, key(1)]);
  assert.equal(await user(coachA, 'select api.create_match_pool_listing($1,$2,$3)', [albyP12, homeSlot, key(1)]), listing, 'idempotent');
  await reject(() => user(coachB, 'select api.create_match_pool_listing($1,$2,$3)', [albyP12, homeSlot, key(2)]), /not_found/);
  await reject(() => user(coachA, 'select api.create_match_pool_listing($1,$2,$3)', [albyP12,
    { ...homeSlot, starts_at: days(-1).toISOString(), ends_at: days(-0.9).toISOString() }, key(3)]), /invalid_input/);
  await reject(() => user(coachA, 'select api.create_match_pool_listing($1,$2,$3)', [albyP12, { ...homeSlot, venue_name: '' }, key(4)]), /invalid_input/);
  await reject(() => user(coachA, 'select api.create_match_pool_listing($1,$2,$3)', [albyP12, { ...homeSlot, match_format: '6v6' }, key(5)]), /invalid_input/);

  // Bro sees it with distance (about 32 km) and verification, without the venue.
  let bro12 = await user(coachB, 'select api.get_match_pool($1,$2)', [broP12, 100]);
  assert.equal(bro12.listings.length, 1);
  const seen = bro12.listings[0];
  assert.equal(seen.verified, true);
  assert.equal(seen.club_name, 'Alby IF');
  assert.equal(seen.venue_name, null);
  assert.ok(seen.distance_km > 25 && seen.distance_km < 40, `distance ${seen.distance_km}`);
  assert.equal((await user(coachB, 'select api.get_match_pool($1,$2)', [broP12, 20])).listings.length, 0, 'distance filter');
  assert.equal((await user(coachA, 'select api.get_match_pool($1)', [albyP12])).listings.length, 0, 'own listings are not in the list');
  assert.equal((await user(coachA, 'select api.get_match_pool($1)', [albyP12])).mine[0].venue_name, 'Alby IP konstgräs');

  // Bro P2012 and Bro F2013 show interest; Alby's coaches are notified.
  const interest = await user(coachB, 'select api.express_match_pool_interest($1,$2,$3,$4)',
    [listing, broP12, { message: 'Vi kommer gärna!' }, key(10)]);
  assert.equal(await user(coachB, 'select api.express_match_pool_interest($1,$2,$3,$4)',
    [listing, broP12, { message: 'Vi kommer gärna!' }, key(10)]), interest, 'idempotent');
  await reject(() => user(coachB, 'select api.express_match_pool_interest($1,$2,$3,$4)',
    [listing, broP12, { message: 'Igen' }, key(11)]), /already_interested/);
  await reject(() => user(coachA, 'select api.express_match_pool_interest($1,$2,$3,$4)',
    [listing, albyP12, { message: 'Själv' }, key(12)]), /not_found/);
  const other = await user(coachC, 'select api.express_match_pool_interest($1,$2,$3,$4)',
    [listing, broF13, { message: 'Vi också', add_to_calendar: false }, key(13)]);
  assert.equal(await one(`select count(*)::int from internal.notification_outbox where event_type='matchpool.interest.received.v1'`), 4,
    'both Alby coaches, for each interest');

  // Conversation: unread for Alby until opened; text never in the outbox.
  let mine = (await user(coachA, 'select api.get_match_pool()')).mine[0];
  assert.equal(mine.interests.length, 2);
  assert.equal(mine.interests[0].unread, true);
  assert.equal(mine.interests[0].verified, false);
  assert.equal((await user(coachA, 'select api.get_match_pool_summary()')).unread, 2);
  const convo = await user(coachA, 'select api.get_match_pool_conversation($1)', [interest]);
  assert.equal(convo.my_side, 'listing');
  assert.equal(convo.messages[0].body, 'Vi kommer gärna!');
  assert.equal((await user(coachA, 'select api.get_match_pool_summary()')).unread, 1);
  await reject(() => user(follower, 'select api.get_match_pool_conversation($1)', [interest]), /not_found/);
  await reject(() => user(coachC, 'select api.get_match_pool_conversation($1)', [interest]), /not_found/);
  await user(coachA, 'select api.send_match_pool_message($1,$2,$3)', [interest, 'Toppen, kl 10 funkar?', key(20)]);
  assert.equal((await user(coachB, 'select api.get_match_pool_conversation($1)', [interest])).listing.venue_name, null,
    'venue hidden before booking');
  assert.equal(await one(`select count(*)::int from internal.notification_outbox where payload_ref::text like '%Toppen%'`), 0);

  // Accept: matched, the other interest closed and told, both calendars as
  // drafts, each created as its own side's leader.
  await reject(() => user(coachB, 'select api.accept_match_pool_interest($1)', [interest]), /not_found/);
  const booked = await user(coachA, 'select api.accept_match_pool_interest($1)', [interest]);
  assert.ok(booked.listing_event_id && booked.interest_event_id);
  assert.deepEqual(await user(coachA, 'select api.accept_match_pool_interest($1)', [interest]), booked, 'idempotent');
  const events = (await db.query(`select owning_team_id, state, created_by, title, location, fields->>'home_away' side,
    fields->>'opponent_name' opponent from core.events order by title`)).rows;
  assert.equal(events.length, 2);
  const albyEvent = events.find(e => e.owning_team_id === albyP12), broEvent = events.find(e => e.owning_team_id === broP12);
  assert.equal(albyEvent.created_by, coachA);
  assert.equal(albyEvent.side, 'home');
  assert.equal(albyEvent.opponent, 'P2012 · Bro BK');
  assert.equal(broEvent.created_by, coachB);
  assert.equal(broEvent.side, 'away');
  assert.equal(broEvent.state, 'draft');
  assert.equal(broEvent.location, 'Alby IP konstgräs');
  assert.equal(await one('select auth.uid()'), coachA, 'the claim is restored');
  assert.equal(await one(`select state from internal.match_pool_listings where id='${listing}'`), 'matched');
  assert.equal(await one(`select state from internal.match_pool_interests where id='${other}'`), 'closed');
  assert.equal(await one(`select count(*)::int from internal.notification_outbox where event_type='matchpool.interest.closed.v1'`), 1);
  assert.equal(await one(`select count(*)::int from internal.notification_outbox where event_type='matchpool.interest.accepted.v1'`), 1);
  assert.equal((await user(coachB, 'select api.get_match_pool_conversation($1)', [interest])).listing.venue_name, 'Alby IP konstgräs',
    'venue shown once booked');
  assert.equal((await user(coachB, 'select api.get_match_pool($1)', [broP12])).listings.length, 0, 'matched listings leave the list');
  await reject(() => user(coachC, 'select api.send_match_pool_message($1,$2,$3)', [other, 'Hallå?', key(21)]), /conversation_closed/);

  // The app's list: each side sees the conversation with the other team.
  const albyList = await user(coachA, 'select api.list_match_pool_conversations()');
  assert.deepEqual(albyList.map(c => [c.id, c.my_side, c.other_club_name]).sort(), [[interest, 'listing', 'Bro BK'], [other, 'listing', 'Bro BK']].sort());
  const broList = await user(coachB, 'select api.list_match_pool_conversations()');
  assert.equal(broList.length, 1);
  assert.equal(broList[0].other_verified, true);
  assert.equal(broList[0].listing.venue_name, 'Alby IP konstgräs', 'booked: venue shown');
  assert.equal((await user(follower, 'select api.list_match_pool_conversations()')).length, 0);
  // Notifications open the conversation.
  assert.equal(await one(`select internal.notification_deep_link(o) from internal.notification_outbox o
    where o.event_type='matchpool.interest.accepted.v1' limit 1`), '/inbox?pool=' + interest);

  // Sign-in from the app: once, only by the server, only for that user.
  const code = await user(coachB, 'select api.create_web_handoff()');
  assert.match(code, /^[0-9a-f]{64}$/);
  assert.equal(await one("select count(*)::int from internal.web_handoffs where code_hash = extensions.digest($1, 'sha256')", [code]), 1);
  await reject(() => user(coachB, 'select api.consume_web_handoff($1)', [code]), /permission denied/);
  const consume = c => asRole('service_role', () => one('select api.consume_web_handoff($1)', [c]));
  assert.equal(await consume(code), coachB);
  assert.equal(await consume(code), null, 'single use');
  assert.equal(await consume('f'.repeat(64)), null);
  const old = await user(coachB, 'select api.create_web_handoff()');
  await db.exec(`update internal.web_handoffs set expires_at = now() - interval '1 second' where consumed_at is null`);
  assert.equal(await consume(old), null, 'expired');
  await db.exec('savepoint limit_check');
  for (let n = 0; n < 10; n++) await user(coachC, 'select api.create_web_handoff()');
  await reject(() => user(coachC, 'select api.create_web_handoff()'), /permission denied|rate_limited/);
  await db.exec('rollback to limit_check');

  // Watches: Bro F2013 watches 7 mot 7 within 100 km; Bro P2012 only girls.
  await reject(() => user(coachA, 'select api.create_match_pool_watch($1,$2)', [broF13, { max_distance_km: 100 }]), /not_found/);
  const watchC = await user(coachC, 'select api.create_match_pool_watch($1,$2)', [broF13, { kind: 'all', max_distance_km: 100, match_format: '7v7', age_class: 'p1' }]);
  await user(coachB, 'select api.create_match_pool_watch($1,$2)', [broP12, { max_distance_km: 100, gender: 'girls' }]);
  await reject(() => user(coachC, 'select api.create_match_pool_watch($1,$2)', [broF13, { max_distance_km: 2 }]), /invalid_input/);
  assert.equal((await user(coachC, 'select api.list_match_pool_watches()')).length, 1, 'only the teams the leader leads');
  assert.equal((await user(coachC, 'select api.get_match_pool()')).watches.length, 1);

  // Cancellation needs both teams. Bro asks, cannot answer itself; Alby declines.
  await reject(() => user(coachC, 'select api.request_match_pool_cancellation($1,$2)', [interest, 'x']), /not_found/);
  await user(coachB, 'select api.request_match_pool_cancellation($1,$2)', [interest, 'Halva laget är sjukt']);
  await reject(() => user(coachB, 'select api.request_match_pool_cancellation($1,$2)', [interest, 'igen']), /cancellation_pending/);
  await reject(() => user(coachB, 'select api.respond_match_pool_cancellation($1,$2)', [interest, true]), /not_found/);
  let seenByAlby = await user(coachA, 'select api.get_match_pool_conversation($1)', [interest]);
  assert.equal(seenByAlby.interest.cancel_requested_side, 'interest');
  assert.equal(seenByAlby.interest.cancel_requested_team_name, 'P2012');
  assert.equal(seenByAlby.interest.cancel_reason, 'Halva laget är sjukt');
  assert.equal(await one(`select count(*)::int from internal.notification_outbox where event_type='matchpool.cancellation.requested.v1'`), 2,
    'both Alby coaches');
  assert.equal((await user(coachA, 'select api.respond_match_pool_cancellation($1,$2)', [interest, false])).cancelled, false);
  assert.equal(await one(`select state from internal.match_pool_interests where id='${interest}'`), 'accepted');
  assert.equal(await one(`select cancel_requested_side from internal.match_pool_interests where id='${interest}'`), null);

  // Alby asks and takes it back; Bro cannot take back Alby's request.
  await user(coachA, 'select api.request_match_pool_cancellation($1)', [interest]);
  await user(coachB, 'select api.withdraw_match_pool_cancellation($1)', [interest]);
  assert.equal(await one(`select cancel_requested_side from internal.match_pool_interests where id='${interest}'`), 'listing');
  await user(coachA, 'select api.withdraw_match_pool_cancellation($1)', [interest]);
  assert.equal(await one(`select cancel_requested_side from internal.match_pool_interests where id='${interest}'`), null);

  // Alby asks, Bro agrees: cancelled, both calendars cancelled, the asking team logged.
  await user(coachA, 'select api.request_match_pool_cancellation($1,$2)', [interest, 'Planen är avstängd']);
  const cancelled = await user(coachB, 'select api.respond_match_pool_cancellation($1,$2)', [interest, true]);
  assert.deepEqual([cancelled.cancelled, cancelled.listing_event_cancelled, cancelled.interest_event_cancelled], [true, true, true]);
  assert.deepEqual((await db.query(`select state from core.events where id in ('${booked.listing_event_id}','${booked.interest_event_id}')`)).rows.map(r => r.state), ['cancelled', 'cancelled']);
  assert.equal(await one('select auth.uid()'), coachB, 'the claim is restored');
  assert.equal(await one(`select state from internal.match_pool_interests where id='${interest}'`), 'cancelled');
  assert.equal(await one(`select state from internal.match_pool_listings where id='${listing}'`), 'cancelled');
  assert.equal(await one(`select requested_by_team_id from internal.match_pool_cancellations`), albyP12);
  assert.equal(await one(`select count(*)::int from internal.notification_outbox where event_type='matchpool.cancellation.accepted.v1'`), 2);
  await reject(() => user(coachB, 'select api.send_match_pool_message($1,$2,$3)', [interest, 'Hej?', key(60)]), /conversation_closed/);

  // Only Alby may put the listing out again; once; watches hear about it.
  assert.equal((await user(coachB, 'select api.get_match_pool_conversation($1)', [interest])).listing.can_republish, false);
  seenByAlby = await user(coachA, 'select api.get_match_pool_conversation($1)', [interest]);
  assert.equal(seenByAlby.listing.can_republish, true);
  assert.equal((await user(coachA, 'select api.get_match_pool()')).mine.find(l => l.id === listing).can_republish, true);
  await reject(() => user(coachB, 'select api.republish_match_pool_listing($1,$2)', [listing, key(61)]), /not_found/);
  const again = await user(coachA, 'select api.republish_match_pool_listing($1,$2)', [listing, key(62)]);
  assert.equal(await user(coachA, 'select api.republish_match_pool_listing($1,$2)', [listing, key(63)]), again, 'once');
  assert.equal(await one(`select state from internal.match_pool_listings where id='${again}'`), 'open');
  assert.equal(await one(`select venue_name from internal.match_pool_listings where id='${again}'`), 'Alby IP konstgräs');
  const watchNotes = (await db.query(`select recipient_profile_id, payload_ref from internal.notification_outbox
    where event_type='matchpool.watch.matched.v1'`)).rows;
  assert.deepEqual(watchNotes.map(n => n.recipient_profile_id), [coachC], 'gender filter keeps Bro P2012 out');
  assert.equal(watchNotes[0].payload_ref.watch_id, watchC);
  assert.equal(await one(`select internal.notification_deep_link(o) from internal.notification_outbox o
    where o.event_type='matchpool.watch.matched.v1'`), '/inbox?poolad=' + again);
  const ad = await user(coachC, 'select api.get_match_pool_listing($1)', [again]);
  assert.equal(ad.verified, true);
  assert.equal(ad.venue_name, null);
  assert.equal(ad.current, true);
  await reject(() => user(follower, 'select api.get_match_pool_listing($1)', [again]), /not_leader/);
  await user(coachA, 'select api.withdraw_match_pool_listing($1)', [again]);
  await user(coachC, 'select api.delete_match_pool_watch($1)', [watchC]);
  await reject(() => user(coachA, 'select api.delete_match_pool_watch($1)', [watchC]), /not_found/);

  // Away wanted from Bro F2013: the host gives a time in the range and a venue.
  const away = await user(coachC, 'select api.create_match_pool_listing($1,$2,$3)', [broF13, {
    kind: 'away_wanted', date_from: localDate(5), date_to: localDate(20), max_distance_km: 40,
    place_label: 'Bro, Upplands-Bro', latitude: 59.51132, longitude: 17.63611, match_format: '9v9',
    age_class: 'F13', gender: 'girls' }, key(30)]);
  await reject(() => user(coachA, 'select api.express_match_pool_interest($1,$2,$3,$4)', [away, albyP12,
    { message: 'Kom till oss', starts_at: days(30).toISOString(), ends_at: days(30.05).toISOString(), venue_name: 'Alby IP' }, key(31)]),
    /invalid_input/, 'outside the range');
  const host = await user(coachA, 'select api.express_match_pool_interest($1,$2,$3,$4)', [away, albyP12,
    { message: 'Kom till oss', starts_at: days(8).toISOString(), ends_at: days(8.05).toISOString(), venue_name: 'Alby IP',
      venue_surface: 'grass' }, key(32)]);
  // The leader who sent the interest lost the right: the booking stands, without that calendar.
  await db.exec(`update core.capability_grants set ends_at=now()-interval '1 minute' where scope_id='${albyP12}'
    and assignment_id in (select id from core.assignments where club_person_id='${personA}')`);
  const second = await user(coachC, 'select api.accept_match_pool_interest($1,$2)', [host, true]);
  assert.ok(second.listing_event_id);
  assert.equal(second.interest_event_id, null);
  assert.equal(await one(`select state from internal.match_pool_interests where id='${host}'`), 'accepted');
  assert.equal(await one('select auth.uid()'), coachC);

  // Too far for a team that travels at most 40 km is not shown.
  const nearby = await user(coachB, 'select api.create_match_pool_listing($1,$2,$3)', [broP12, {
    kind: 'away_wanted', date_from: localDate(5), date_to: localDate(20), max_distance_km: 10,
    place_label: 'Bro', latitude: 59.51, longitude: 17.64, match_format: '7v7', age_class: 'P12', gender: 'boys' }, key(40)]);
  await db.exec(`update core.capability_grants set ends_at=null`);
  assert.equal((await user(coachA, 'select api.get_match_pool($1,$2)', [albyP12, 500])).listings.some(l => l.id === nearby), false);
  assert.equal((await user(coachA, 'select api.get_match_pool()')).listings.some(l => l.id === nearby), true, 'without a starting point');

  // Reports: hidden after three clubs; one club counts once.
  await user(coachA, 'select api.report_match_pool_listing($1,$2)', [nearby, 'Konstig annons']);
  await user(coachA2, 'select api.report_match_pool_listing($1,$2)', [nearby, 'Konstig annons']);
  assert.equal(await one(`select count(*)::int from internal.match_pool_reports where listing_id='${nearby}'`), 1);
  await reject(() => user(coachC, 'select api.report_match_pool_listing($1,$2)', [nearby, 'Egen klubb']), /not_found/);

  // Age groups: fixed choices, a readable label, shared groups match a watch.
  assert.equal(await one(`select internal.match_pool_age_label(array['2013','2012','2015','senior'])`), '2012–2013, 2015, Senior');
  assert.equal(await one(`select internal.match_pool_age_label('{}')`), null);
  assert.equal(await one(`select internal.match_pool_age_groups('["2012","P12"]'::jsonb)`), null);
  const ageWatch = await user(coachA, 'select api.create_match_pool_watch($1,$2)', [albyP12, { max_distance_km: 100, age_groups: ['2013'] }]);
  assert.equal(await one(`select age_class from internal.match_pool_watches where id='${ageWatch}'`), '2013');
  await reject(() => user(coachA, 'select api.create_match_pool_watch($1,$2)', [albyP12, { max_distance_km: 100, age_groups: ['P12'] }]), /invalid_input/);
  const grouped = await user(coachB, 'select api.create_match_pool_listing($1,$2,$3)', [broP12, { kind: 'away_wanted',
    date_from: localDate(5), date_to: localDate(20), max_distance_km: 50, place_label: 'Bro', latitude: 59.51, longitude: 17.64,
    match_format: '11v11', age_groups: ['2013', '2012'], gender: 'boys' }, key(70)]);
  assert.equal(await one(`select age_class from internal.match_pool_listings where id='${grouped}'`), '2012–2013');
  assert.equal(await one(`select count(*)::int from internal.notification_outbox
    where event_type='matchpool.watch.matched.v1' and payload_ref->>'watch_id'='${ageWatch}'`), 1, 'shares 2013');
  await reject(() => user(coachB, 'select api.create_match_pool_listing($1,$2,$3)', [broP12, { kind: 'away_wanted',
    date_from: localDate(5), date_to: localDate(20), max_distance_km: 50, place_label: 'Bro', latitude: 59.51, longitude: 17.64,
    match_format: '11v11', age_groups: [], gender: 'boys' }, key(71)]), /invalid_input/);
  // Editing a watch: any leader of the team; the age groups change what it matches.
  await user(coachA2, 'select api.update_match_pool_watch($1,$2)', [ageWatch, { kind: 'home_slot', max_distance_km: 75, age_groups: ['2014'], verified_only: true }]);
  const edited = (await user(coachA, 'select api.list_match_pool_watches()')).find(w => w.id === ageWatch);
  assert.deepEqual([edited.kind, edited.max_distance_km, edited.age_groups, edited.age_class, edited.verified_only], ['home_slot', 75, ['2014'], '2014', true]);
  await reject(() => user(coachB, 'select api.update_match_pool_watch($1,$2)', [ageWatch, { max_distance_km: 50 }]), /not_found/);
  await reject(() => user(coachA, 'select api.update_match_pool_watch($1,$2)', [ageWatch, { max_distance_km: 1 }]), /invalid_input/);
  await user(coachB, 'select api.withdraw_match_pool_listing($1)', [grouped]);
  await user(coachA, 'select api.delete_match_pool_watch($1)', [ageWatch]);

  // Withdraw closes waiting interests; retention expires and later deletes.
  const later = await user(coachB, 'select api.create_match_pool_listing($1,$2,$3)', [broP12, { ...homeSlot,
    place_label: 'Bro', latitude: 59.51, longitude: 17.64, venue_name: 'Bro IP' }, key(50)]);
  const waiting = await user(coachA, 'select api.express_match_pool_interest($1,$2,$3,$4)', [later, albyP12, { message: 'Vi!' }, key(51)]);
  await user(coachB, 'select api.withdraw_match_pool_listing($1)', [later]);
  assert.equal(await one(`select state from internal.match_pool_interests where id='${waiting}'`), 'closed');
  await db.exec(`update internal.match_pool_listings set date_from=current_date-10, date_to=current_date-2 where id='${nearby}'`);
  await one('select internal.apply_match_pool_retention()');
  assert.equal(await one(`select state from internal.match_pool_listings where id='${nearby}'`), 'expired');
  await db.exec(`update internal.match_pool_listings set updated_at=now()-interval '40 days';
    update internal.match_pool_interests set updated_at=now()-interval '40 days'`);
  await one('select internal.apply_match_pool_retention()');
  assert.equal(await one('select count(*)::int from internal.match_pool_listings'), 0);
  assert.equal(await one('select count(*)::int from internal.match_pool_messages'), 0);

  // Notification texts and the daily job.
  assert.equal(await one(`select internal.notification_title('matchpool.interest.accepted.v1')`), 'Träningsmatchen är bokad');
  assert.equal(await one(`select count(*)::int from cron.job where jobname='match-pool-retention'`), 1);
  console.log('match pool: ok');
} finally {
  await db.close();
}
