// PUB-14 club-site messages as threads: the real migration in isolated
// Postgres, with publication, capabilities and the outbox reduced to what it
// reads. node supabase/tests/public_contact_threads.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
import { pgcrypto } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/contrib/pgcrypto.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite({ extensions: { pgcrypto } });
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const admin = id(1), coach = id(2), outsider = id(3);
const club = id(10), team = id(20), team2 = id(21);
const clubPublic = id(30), teamPublic = id(40), team2Public = id(41);
const adminPerson = id(51), coachPerson = id(52);
const captcha = 'a'.repeat(64);
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
// On failure the savepoint rollback in reject() also undoes the role.
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
const user = (who, sql, params) => as(who).then(() => asRole('authenticated', () => one(sql, params)));
const service = (sql, params) => asRole('service_role', () => one(sql, params));
const submit = (teamPub, email = 'Ada@Example.se', body = 'Hej! Kan min son börja träna?') => service(
  'select api.public_submit_contact_v2($1,$2,$3,$4,$5,$6,$7,true,$8)',
  [clubPublic, teamPub, 'Ada Andersson', email, 'Ny spelare', body, 'b'.repeat(64), captcha]);
try {
  await db.exec(`create role anon;create role authenticated;create role service_role;
  create schema internal;create schema api;create schema core;create schema auth;create schema extensions;
  create schema public_api;create schema vault;create schema cron;create schema net;
  create extension pgcrypto schema extensions;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table vault.secrets(name text primary key,secret text);
  create view vault.decrypted_secrets as select name,secret as decrypted_secret from vault.secrets;
  create table cron.job(jobid bigserial primary key,jobname text,schedule text,command text);
  create function cron.schedule(n text,s text,c text) returns bigint language sql as $$insert into cron.job(jobname,schedule,command) values(n,s,c) returning jobid$$;
  create function cron.unschedule(j bigint) returns boolean language sql as $$delete from cron.job where jobid=j returning true$$;
  create table net.calls(url text);
  create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds int) returns bigint language sql as $$insert into net.calls values(url);select 1::bigint$$;
  create table core.profiles(id uuid primary key,display_name text,locale text,timezone text);
  insert into core.profiles values('${admin}','Klubbadmin',null,null),('${coach}','Tränare Tina',null,null),('${outsider}','Ute',null,null);
  create table core.clubs(id uuid primary key,name text);
  insert into core.clubs values('${club}','Alby IF');
  create table core.teams(id uuid primary key,club_id uuid,name text,status text default 'active');
  insert into core.teams values('${team}','${club}','P2012','active'),('${team2}','${club}','F2013','active');
  create table core.person_account_links(profile_id uuid,club_id uuid,club_person_id uuid,state text);
  insert into core.person_account_links values('${admin}','${club}','${adminPerson}','active'),('${coach}','${club}','${coachPerson}','active');
  create table core.assignments(id uuid primary key default gen_random_uuid(),club_person_id uuid,club_id uuid,state text default 'active',
   starts_at timestamptz default now()-interval '1 day',ends_at timestamptz);
  create table core.capability_grants(assignment_id uuid,club_id uuid,capability text,scope_type text,scope_id uuid,
   starts_at timestamptz default now()-interval '1 day',ends_at timestamptz);
  with a as (insert into core.assignments(club_person_id,club_id) values('${adminPerson}','${club}') returning id)
   insert into core.capability_grants select a.id,'${club}','club.memberships.manage','club','${club}' from a;
  with a as (insert into core.assignments(club_person_id,club_id) values('${coachPerson}','${club}') returning id)
   insert into core.capability_grants select a.id,'${club}','team.roster.manage','team','${team}' from a;
  create function internal.actor_has_capability(c uuid,t uuid,cap text) returns boolean language sql stable security definer set search_path='' as $$
   select exists(select 1 from core.person_account_links l join core.assignments a on a.club_person_id=l.club_person_id
    join core.capability_grants g on g.assignment_id=a.id where l.profile_id=auth.uid() and a.club_id=c
    and (g.capability=cap or (cap='club.memberships.manage' and t is not null and g.capability='team.roster.manage' and g.scope_type='team'))
    and ((g.scope_type='club' and g.scope_id=c) or (g.scope_type='team' and g.scope_id=t)))$$;
  create function internal.actor_manages_club(c uuid) returns boolean language sql stable security definer set search_path='' as $$
   select internal.actor_has_capability(c,null,'club.memberships.manage')$$;
  create table core.publication_confirmations(id uuid primary key,state text,expires_at timestamptz);
  insert into core.publication_confirmations values('${id(60)}','active',now()+interval '1 year');
  create table core.club_publication_settings(club_id uuid,public_id uuid,mode text,confirmation_id uuid);
  insert into core.club_publication_settings values('${club}','${clubPublic}','published','${id(60)}');
  create table public_api.club_projections(public_id uuid primary key);
  insert into public_api.club_projections values('${clubPublic}');
  create table core.team_publication_settings(team_id uuid,club_id uuid,public_id uuid);
  insert into core.team_publication_settings values('${team}','${club}','${teamPublic}'),('${team2}','${club}','${team2Public}');
  create table public_api.team_projections(public_id uuid primary key);
  insert into public_api.team_projections values('${teamPublic}'),('${team2Public}');
  create function internal.public_runtime_enabled() returns boolean language sql as $$select true$$;
  create function internal.consume_public_rate_limit(h text,c text,s uuid) returns jsonb language sql as $$select '{"allowed":true}'::jsonb$$;
  create table internal.public_rate_limit_buckets(expires_at timestamptz);
  create table internal.notification_outbox(id uuid primary key default gen_random_uuid(),club_id uuid,domain_event_id uuid,
   event_type text,aggregate_type text,aggregate_id uuid,recipient_profile_id uuid,recipient_person_id uuid,payload_ref jsonb,
   state text default 'pending',created_at timestamptz default now(),unique(domain_event_id,recipient_person_id));
  create table internal.public_contact_submissions (
   id uuid primary key default gen_random_uuid(), public_id uuid not null default gen_random_uuid() unique,
   club_id uuid not null references core.clubs(id), sender_name text not null, sender_email text not null,
   subject text not null, message_body text not null,
   captcha_assertion_hash bytea not null check(octet_length(captcha_assertion_hash)=32),
   state text not null default 'pending', delivery_attempts integer not null default 0, last_error_code text,
   created_at timestamptz not null default now(), expires_at timestamptz not null default (now()+interval '30 days'),
   delivered_at timestamptz, erased_at timestamptz, revision bigint not null default 1,
   check(expires_at<=created_at+interval '30 days 1 minute'));
  insert into vault.secrets values('project_url','https://example.supabase.co'),('support_email_worker_token','t0k');
  -- The migration patches this one; only the patched line matters here.
  create function internal.get_publication_self_service_for_actor(target_club_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
  begin return (select jsonb_agg(jsonb_build_object('id',t.id,
    'can_request',internal.actor_has_capability(target_club_id,t.id,'team.roster.manage'),
    'name',t.name)) from core.teams t left join core.team_publication_settings ts on ts.team_id=t.id where t.club_id=target_club_id); end$$;
  grant usage on schema api, internal, core, public_api, extensions to authenticated, service_role;
  grant usage on schema vault to service_role;`);
  // push_message_for_outbox refers to push tables this test does not create.
  await db.exec('set check_function_bodies = off');
  await db.exec(read('supabase/migrations/20261101090000_public_contact_threads.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec('begin');
  const recipients = async sub => (await db.query(
    "select recipient_profile_id from internal.notification_outbox where aggregate_id=$1 order by created_at, recipient_profile_id", [sub])).rows
    .map(r => r.recipient_profile_id);
  const threadOf = email => one('select id from internal.public_contact_submissions where sender_email=$1', [email]);

  // 1. A message to the club goes to its administrators only.
  assert.equal((await submit(null)).accepted, true);
  const clubThread = await threadOf('ada@example.se');
  assert.deepEqual(await recipients(clubThread), [admin]);
  assert.equal(await one('select sender_email from internal.public_contact_submissions where id=$1', [clubThread]), 'ada@example.se');

  // 2. A message to a team goes to its roster managers; a team without
  // managers falls back to the club's administrators.
  await submit(teamPublic, 'bo@example.se');
  const teamThread = await threadOf('bo@example.se');
  assert.equal(await one('select team_id from internal.public_contact_submissions where id=$1', [teamThread]), team);
  assert.deepEqual(await recipients(teamThread), [coach]);
  await submit(team2Public, 'cia@example.se');
  assert.deepEqual(await recipients(await threadOf('cia@example.se')), [admin]);

  // 3. A team that switched the form off gets the neutral answer and no row.
  await db.query('update core.team_publication_settings set contact_enabled=false where team_id=$1', [team2]);
  const before = await one('select count(*)::int from internal.public_contact_submissions');
  assert.deepEqual(await submit(team2Public, 'dan@example.se'), { accepted: true });
  assert.equal(await one('select count(*)::int from internal.public_contact_submissions'), before);

  // 4. Who sees what: the admin all threads, the coach only the team's, others none.
  assert.equal((await user(admin, 'select api.list_contact_threads()')).length, 3);
  const coachThreads = await user(coach, 'select api.list_contact_threads()');
  assert.deepEqual(coachThreads.map(t => t.id), [teamThread]);
  assert.equal(coachThreads[0].unread, true);
  assert.deepEqual(await user(outsider, 'select api.list_contact_threads()'), []);
  await as(outsider);
  await reject(() => asRole('authenticated', () => one('select api.get_contact_thread($1)', [teamThread])), /not_found/);

  // 5. Reading marks the thread read for that person.
  const thread = await user(coach, 'select api.get_contact_thread($1)', [teamThread]);
  assert.equal(thread.messages.length, 1);
  assert.equal(thread.team_name, 'P2012');
  assert.equal((await user(coach, 'select api.list_contact_threads()'))[0].unread, false);

  // 6. An answer is queued once per idempotency key and extends the thread.
  const key = id(70);
  const reply = await user(coach, 'select api.reply_contact_thread($1,$2,$3)', [teamThread, ' Välkommen på torsdag! ', key]);
  assert.ok(reply.id);
  assert.deepEqual(await user(coach, 'select api.reply_contact_thread($1,$2,$3)', [teamThread, 'igen', key]), { id: reply.id, repeated: true });
  await as(coach);
  await reject(() => asRole('authenticated', () => one('select api.reply_contact_thread($1,$2,$3)', [teamThread, '   ', id(71)])), /invalid_reply/);
  assert.equal(await one("select count(*)::int from internal.public_contact_messages where direction='out'"), 1);

  // 7. The worker claims it, with the recipient and the original message, and
  // records the result. Only the service role may.
  await reject(() => asRole('authenticated', () => one('select api.claim_contact_emails(10)')), /permission denied/);
  const claimed = await service('select api.claim_contact_emails(10)');
  assert.equal(claimed.length, 1);
  assert.equal(claimed[0].to, 'bo@example.se');
  assert.equal(claimed[0].body, 'Välkommen på torsdag!');
  assert.equal(claimed[0].team_name, 'P2012');
  assert.deepEqual(await service('select api.claim_contact_emails(10)'), [], 'claimed once');
  await service('select api.finish_contact_email($1,true,$2,null)', [claimed[0].message_id, 're_123']);
  assert.equal(await one('select email_state from internal.public_contact_messages where id=$1', [reply.id]), 'sent');
  assert.equal(await one('select internal.invoke_contact_email_worker()'), null, 'nothing waiting, no call');

  // 8. The sender's e-mail reply: only from the same address, once per e-mail.
  await user(coach, 'select api.set_contact_thread_handled($1,true)', [teamThread]);
  const pub = await one('select public_id from internal.public_contact_submissions where id=$1', [teamThread]);
  assert.equal(await service('select api.receive_contact_email($1,$2,$3,$4)', [pub, 'evil@example.se', 'Hej', 'em_1']), 'wrong_sender');
  assert.equal(await service('select api.receive_contact_email($1,$2,$3,$4)', [pub, 'BO@example.se', 'Tack, vi kommer!', 'em_2']), 'accepted');
  assert.equal(await service('select api.receive_contact_email($1,$2,$3,$4)', [pub, 'bo@example.se', 'Tack, vi kommer!', 'em_2']), 'duplicate');
  assert.equal(await service('select api.receive_contact_email($1,$2,$3,$4)', [id(99), 'bo@example.se', 'Hej', 'em_3']), 'closed');
  const afterReply = (await user(coach, 'select api.list_contact_threads()'))[0];
  assert.equal(afterReply.handled, false, 'a new e-mail reopens the thread');
  assert.equal(afterReply.unread, true);
  assert.equal(afterReply.preview, 'Tack, vi kommer!');
  assert.equal((await recipients(teamThread)).length, 2, 'the coach is notified again');
  const full = await user(coach, 'select api.get_contact_thread($1)', [teamThread]);
  assert.deepEqual(full.messages.map(m => m.direction), ['in', 'out', 'in']);
  assert.equal(full.messages[1].author_name, 'Tränare Tina');

  // 9. Pending answers wake the worker.
  await user(coach, 'select api.reply_contact_thread($1,$2,$3)', [teamThread, 'Perfekt.', id(72)]);
  assert.equal(await one('select internal.invoke_contact_email_worker()'), 1);
  assert.equal(await one('select url from net.calls'), 'https://example.supabase.co/functions/v1/contact-email-worker');
  assert.equal(await one("select count(*)::int from cron.job where jobname in ('contact-email-worker','public-contact-retention')"), 2);

  // 10. The notification texts never contain the message.
  assert.equal(await one("select internal.notification_title('contact.message.received.v1')"), 'Nytt meddelande via klubbsajten');

  // 11. Retention erases the thread with its messages and reads.
  await db.query("update internal.public_contact_submissions set expires_at=now()-interval '1 second' where id=$1", [teamThread]);
  assert.ok(await one('select internal.apply_public_contact_retention(10)') >= 1);
  assert.equal(await one('select state from internal.public_contact_submissions where id=$1', [teamThread]), 'erased');
  assert.equal(await one('select count(*)::int from internal.public_contact_messages where submission_id=$1', [teamThread]), 0);
  assert.equal(await one('select count(*)::int from internal.public_contact_reads where submission_id=$1', [teamThread]), 0);
  assert.equal(await service('select api.receive_contact_email($1,$2,$3,$4)', [pub, 'bo@example.se', 'Hallå?', 'em_9']), 'closed');

  // 12. The team form switch: leaders of that team (or the club) only, shown in the publication settings.
  const teams = await user(coach, 'select internal.get_publication_self_service_for_actor($1)', [club]);
  assert.deepEqual(teams.find(t => t.id === team).contact_enabled, true);
  assert.equal(teams.find(t => t.id === team).can_set_contact, true);
  assert.equal(teams.find(t => t.id === team2).can_set_contact, false);
  await user(coach, 'select api.set_team_contact_enabled($1,false)', [team]);
  assert.equal(await one('select contact_enabled from core.team_publication_settings where team_id=$1', [team]), false);
  await as(coach);
  await reject(() => asRole('authenticated', () => one('select api.set_team_contact_enabled($1,true)', [team2])), /not_found/);
  await user(admin, 'select api.set_team_contact_enabled($1,true)', [team2]);

  // 13. Users cannot read the tables or call the worker functions.
  for (const t of ['public_contact_messages', 'public_contact_reads']) {
    assert.equal(await one('select has_table_privilege($1,$2,$3)', ['authenticated', `internal.${t}`, 'select']), false, t);
  }
  for (const fn of ['api.receive_contact_email(uuid,text,text,text)', 'api.claim_contact_emails(integer)',
    'api.public_submit_contact_v2(uuid,uuid,text,text,text,text,text,boolean,text)']) {
    assert.equal(await one('select has_function_privilege($1,$2,$3)', ['authenticated', fn, 'execute']), false, fn);
    assert.equal(await one('select has_function_privilege($1,$2,$3)', ['anon', fn, 'execute']), false, fn);
  }
  await db.exec('rollback');
  console.log('public contact threads: ok');
} finally {
  await db.close();
}
