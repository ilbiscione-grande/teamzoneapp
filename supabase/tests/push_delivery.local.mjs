// The real push delivery migration in isolated Postgres with pgcrypto and
// stubbed Vault, pg_cron and pg_net.
// node supabase/tests/push_delivery.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
import { pgcrypto } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/contrib/pgcrypto.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite({ extensions: { pgcrypto } });
const anna = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', bo = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const club = '10000000-0000-4000-8000-000000000001', team = '20000000-0000-4000-8000-000000000001';
const event = '30000000-0000-4000-8000-000000000001', thread = '40000000-0000-4000-8000-000000000001';
const person = '50000000-0000-4000-8000-000000000001';
const tokenA = 'fcm-token-anna-device-0123456789:APA91b_x', tokenB = 'fcm-token-bo-device-0123456789:APA91b_y';
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
// On failure the savepoint rollback in reject() also undoes the role.
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
try {
  await db.exec(`create role anon;create role authenticated;create role service_role;
  create schema internal;create schema api;create schema core;create schema auth;create schema extensions;
  create schema vault;create schema cron;create schema net;
  create extension pgcrypto schema extensions;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table vault.secrets(name text primary key,secret text,description text);
  create view vault.decrypted_secrets as select name,secret as decrypted_secret from vault.secrets;
  create function vault.create_secret(s text,n text,d text) returns uuid language sql as $$insert into vault.secrets values(n,s,d);select gen_random_uuid()$$;
  create table cron.job(jobid bigserial primary key,jobname text,schedule text,command text);
  create function cron.schedule(n text,s text,c text) returns bigint language sql as $$insert into cron.job(jobname,schedule,command) values(n,s,c) returning jobid$$;
  create function cron.unschedule(id bigint) returns boolean language sql as $$delete from cron.job where jobid=id returning true$$;
  create table net.calls(url text,headers jsonb);
  create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds int) returns bigint language sql as $$insert into net.calls values(url,headers);select 1::bigint$$;
  create table core.profiles(id uuid primary key,locale text,timezone text);
  insert into core.profiles values('${anna}','sv','Europe/Stockholm'),('${bo}','en',null);
  create table core.teams(id uuid primary key,name text);
  insert into core.teams values('${team}','P2012');
  create table core.events(id uuid primary key,owning_team_id uuid,event_type text,title text,starts_at timestamptz,timezone text);
  insert into core.events values('${event}','${team}','training','Avslutning hos Anna Andersson','2026-10-17 16:00+00','Europe/Stockholm');
  create table core.thread_scopes(thread_id uuid,club_id uuid,team_id uuid);
  insert into core.thread_scopes values('${thread}','${club}','${team}');
  create table core.notification_endpoints(id uuid primary key default gen_random_uuid(),profile_id uuid not null,
   channel text not null,endpoint_hash bytea not null,state text not null default 'active',created_at timestamptz default now(),
   unique(profile_id,channel,endpoint_hash));
  create table internal.notification_outbox(id uuid primary key default gen_random_uuid(),club_id uuid,domain_event_id uuid,
   event_type text,aggregate_type text,aggregate_id uuid,recipient_profile_id uuid,recipient_person_id uuid,payload_ref jsonb not null default '{}',
   state text default 'pending',created_at timestamptz default now());
  create function internal.notification_deep_link(outbox internal.notification_outbox) returns text language sql stable as $$
   select case when outbox.event_type like 'callup.%' then '/calendar/event/'||(outbox.payload_ref->>'event_id') else '/inbox?thread='||(outbox.payload_ref->>'thread_id') end$$;
  insert into vault.secrets values('project_url','https://example.supabase.co',null);
  grant usage on schema api, internal, core, extensions to authenticated, service_role;
  grant usage on schema vault to service_role;`);
  const migration = read('supabase/migrations/20261023090000_push_delivery.sql')
    .replace(/notify pgrst[^;]*;/, '')
    .replace(/create extension if not exists pg_(cron|net);/g, ''); // stubbed above
  await db.exec(migration);
  await db.exec('begin');

  // 1. A user registers a device; the token is stored encrypted, the hash as before.
  await as(anna);
  await asRole('authenticated', () => db.query('select api.register_push_endpoint($1,$2)', ['android', tokenA]));
  assert.equal(await one('select count(*)::int from core.notification_endpoints where profile_id=$1 and state=$2', [anna, 'active']), 1);
  const cipher = await one('select encode(token_ciphertext,$1) from internal.push_endpoint_tokens', ['escape']);
  assert.ok(!cipher.includes('fcm-token'), 'the token is not stored in plain text');
  await reject(() => asRole('authenticated', () => db.query('select api.register_push_endpoint($1,$2)', ['web', tokenA])), /invalid_push_token/);
  await reject(() => asRole('authenticated', () => db.query('select api.register_push_endpoint($1,$2)', ['android', 'short'])), /invalid_push_token/);
  await reject(() => asRole('authenticated', () => db.query('select api.register_push_endpoint($1,$2)', ['android', 'x'.repeat(30) + ' <script>'])), /invalid_push_token/);

  // 2. Lock-screen text: type + team + time, never the event title.
  const outbox = async (type, payload, profile = anna) => one(
    `insert into internal.notification_outbox(event_type,recipient_profile_id,payload_ref) values($1,$2,$3) returning id`,
    [type, profile, payload]);
  const callup = await outbox('callup.callup.sent.v1', { event_id: event });
  const message = await asRole('service_role', () => one('select api.push_message_for_outbox($1)', [callup]));
  assert.equal(message.title, 'Ny kallelse');
  assert.equal(message.body, 'Träning · P2012 · lör 17 okt 18:00');
  assert.equal(message.route, `/calendar/event/${event}`);
  assert.equal(message.targets.length, 1);
  assert.equal(message.targets[0].token, tokenA, 'the worker gets the decrypted token');
  assert.ok(!JSON.stringify(message).includes('Anna Andersson'), 'free-text event titles never reach the lock screen');
  const reminded = await outbox('callup.callup.reminded.v2', { event_id: event });
  assert.equal((await asRole('service_role', () => one('select api.push_message_for_outbox($1)', [reminded]))).title,
    'Påminnelse: svara på kallelsen');
  const cancelled = await outbox('callup.callup.cancelled.v2', { event_id: event });
  assert.equal((await asRole('service_role', () => one('select api.push_message_for_outbox($1)', [cancelled]))).title,
    'Kallelsen är inställd');
  const chat = await outbox('message.message.sent.v1', { thread_id: thread, message_id: person });
  const chatMessage = await asRole('service_role', () => one('select api.push_message_for_outbox($1)', [chat]));
  assert.deepEqual([chatMessage.title, chatMessage.body], ['Nytt meddelande', 'P2012']);

  // 3. English for an English profile (UTC when no time zone is set).
  const english = await outbox('callup.callup.sent.v1', { event_id: event }, bo);
  const en = await asRole('service_role', () => one('select api.push_message_for_outbox($1)', [english]));
  assert.deepEqual([en.title, en.body, en.targets.length], ['New callup', 'Training · P2012 · Sat 17 Oct 18:00', 0]);

  // 4. A shared phone: the token moves to the new account.
  await as(bo);
  await asRole('authenticated', () => db.query('select api.register_push_endpoint($1,$2)', ['android', tokenA]));
  const moved = await asRole('service_role', () => one('select api.push_message_for_outbox($1)', [callup]));
  assert.equal(moved.targets.length, 0, "Anna's notifications no longer reach the phone");
  assert.equal(await one("select count(*)::int from core.notification_endpoints where profile_id=$1 and state='active'", [anna]), 0);

  // 5. Signing out stops the device; FCM-rejected tokens are disabled.
  await asRole('authenticated', () => db.query('select api.register_push_endpoint($1,$2)', ['ios', tokenB]));
  await asRole('authenticated', () => db.query('select api.unregister_push_endpoint($1)', [tokenA]));
  assert.equal(await one("select count(*)::int from core.notification_endpoints where profile_id=$1 and state='active'", [bo]), 1);
  const iosEndpoint = await one("select id from core.notification_endpoints where profile_id=$1 and state='active'", [bo]);
  await asRole('service_role', () => db.query('select api.disable_push_endpoint($1)', [iosEndpoint]));
  assert.equal(await one('select count(*)::int from internal.push_endpoint_tokens'), 0);

  // 6. Permissions: users may only register; the worker functions are service-only.
  for (const fn of ['api.push_message_for_outbox(uuid)', 'api.disable_push_endpoint(uuid)']) {
    assert.equal(await one('select has_function_privilege($1,$2,$3)', ['authenticated', fn, 'execute']), false, fn);
    assert.equal(await one('select has_function_privilege($1,$2,$3)', ['service_role', fn, 'execute']), true, fn);
  }
  for (const fn of ['api.register_push_endpoint(text,text)', 'api.unregister_push_endpoint(text)']) {
    assert.equal(await one('select has_function_privilege($1,$2,$3)', ['anon', fn, 'execute']), false, fn);
  }
  assert.equal(await one("select has_table_privilege('authenticated','internal.push_endpoint_tokens','select')"), false);
  await as('');
  await reject(() => asRole('authenticated', () => db.query('select api.register_push_endpoint($1,$2)', ['android', tokenA])), /unauthenticated/);

  // 7. The minute schedule calls the worker with its token, once configured.
  assert.equal(await one("select count(*)::int from cron.job where jobname='notification-worker'"), 1);
  assert.equal(await one('select internal.invoke_notification_worker()'), null, 'skipped without a worker token');
  await db.query("insert into vault.secrets values('notification_worker_token','t0ken',null)");
  assert.equal(await one('select internal.invoke_notification_worker()'), 1);
  assert.equal(await one('select url from net.calls'), 'https://example.supabase.co/functions/v1/notification-worker');
  await db.exec(migration);
  assert.equal(await one("select count(*)::int from cron.job where jobname='notification-worker'"), 1, 'rerunning keeps one job');
  await db.exec('rollback');
  console.log('push delivery: ok');
} finally {
  await db.close();
}
