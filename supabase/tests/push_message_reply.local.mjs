// Replying to a message from its notification: the real push migrations in
// isolated Postgres, with the app's message sending stubbed (its rules are
// tested with the messaging migrations).
// node supabase/tests/push_message_reply.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
import { pgcrypto } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/contrib/pgcrypto.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite({ extensions: { pgcrypto } });
const anna = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const club = '10000000-0000-4000-8000-000000000001', team = '20000000-0000-4000-8000-000000000001';
const thread = '40000000-0000-4000-8000-000000000001', announcement = '40000000-0000-4000-8000-000000000002';
const closed = '40000000-0000-4000-8000-000000000003';
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
const service = (sql, params) => asRole('service_role', () => one(sql, params));
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
  create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds int) returns bigint language sql as $$select 1::bigint$$;
  create table core.profiles(id uuid primary key,locale text,timezone text);
  insert into core.profiles values('${anna}','sv','Europe/Stockholm');
  create table core.teams(id uuid primary key,name text);
  insert into core.teams values('${team}','P2012');
  create table core.events(id uuid primary key,owning_team_id uuid,event_type text,title text,starts_at timestamptz,timezone text);
  create table core.callups(id uuid primary key,event_id uuid,club_person_id uuid,state text,expires_at timestamptz,revision bigint not null default 1);
  create function internal.respond_callup_for_actor(uuid,text,uuid,text,text,bigint,uuid) returns bigint language sql as $$select 1::bigint$$;
  create table core.thread_scopes(thread_id uuid,club_id uuid,team_id uuid);
  insert into core.thread_scopes values('${thread}','${club}','${team}');
  create table core.message_threads(id uuid primary key,thread_type text,state text);
  create table core.messages(thread_id uuid,sender_profile_id uuid,created_at timestamptz);
  insert into core.message_threads values('${thread}','team','active'),('${announcement}','announcement','active'),
   ('${closed}','team','closed');
  create table core.notification_endpoints(id uuid primary key default gen_random_uuid(),profile_id uuid not null,
   channel text not null,endpoint_hash bytea not null,state text not null default 'active',created_at timestamptz default now(),
   unique(profile_id,channel,endpoint_hash));
  create table internal.notification_outbox(id uuid primary key default gen_random_uuid(),club_id uuid,domain_event_id uuid,
   event_type text,aggregate_type text,aggregate_id uuid,recipient_profile_id uuid,recipient_person_id uuid,payload_ref jsonb not null default '{}',
   state text default 'pending',created_at timestamptz default now());
  create function internal.notification_deep_link(outbox internal.notification_outbox) returns text language sql stable as $$
   select '/inbox?thread='||(outbox.payload_ref->>'thread_id')$$;
  -- Stub of the app's sending: records who sent what where.
  create table public.sent(actor uuid,thread uuid,body text,idempotency_key uuid);
  create function internal.send_message_for_actor(target_thread_id uuid,new_body text,idempotency_key uuid)
  returns jsonb language plpgsql security definer set search_path='' as $$
  begin
   if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
   if not exists(select 1 from core.message_threads where id=target_thread_id and state='active') then
    raise insufficient_privilege using message='not_found'; end if;
   insert into public.sent values(auth.uid(),target_thread_id,new_body,idempotency_key);
   return jsonb_build_object('message_id','80000000-0000-4000-8000-000000000001','thread_revision',2);
  end$$;
  insert into vault.secrets values('project_url','https://example.supabase.co',null);
  grant usage on schema api, internal, core, extensions to authenticated, service_role;
  grant usage on schema vault to service_role;`);
  const strip = sql => sql.replace(/notify pgrst[^;]*;/, '').replace(/create extension if not exists pg_(cron|net);/g, '');
  for (const name of ['20261023090000_push_delivery', '20261024090000_push_callup_response', '20261025090000_push_message_reply',
    '20261028090000_push_token_fixes', '20261029090000_push_token_two_days']) {
    await db.exec(strip(read(`supabase/migrations/${name}.sql`)));
  }
  await db.exec('begin');
  // Anna has a phone; reply tokens are only for someone with a device.
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [anna]);
  await asRole('authenticated', () => db.query('select api.register_push_endpoint($1,$2)', ['android', 'fcm-token-anna-device-0123456789:APA91b_x']));
  await db.query("select set_config('request.jwt.claim.sub','',false)");

  const push = async target => service('select api.push_message_for_outbox($1)', [await one(
    `insert into internal.notification_outbox(event_type,recipient_profile_id,payload_ref) values('message.message.sent.v1',$1,$2) returning id`,
    [anna, { thread_id: target, message_id: '80000000-0000-4000-8000-000000000009' }])]);

  // 1. A message in a thread one can write in carries a single-use reply token.
  const message = await push(thread);
  assert.deepEqual([message.title, message.body], ['Nytt meddelande', 'P2012']);
  assert.equal(message.reply.thread_id, thread);
  assert.match(message.reply.token, /^[0-9a-f]{64}$/);
  assert.equal(await one("select bool_and(expires_at <= now() + interval '2 days') from internal.push_reply_tokens"), true,
    'valid for two days');
  assert.equal(message.response, null);
  assert.equal(await one("select count(*)::int from internal.push_reply_tokens where encode(token_hash,'hex')=$1", [message.reply.token]), 0,
    'the raw token is not stored');

  // 1b. No token for a recipient without a device.
  const noDevice = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  await db.query("insert into core.profiles values($1,'sv','Europe/Stockholm')", [noDevice]);
  const tokensBefore = await one('select count(*)::int from internal.push_reply_tokens');
  const silent = await service('select api.push_message_for_outbox($1)', [await one(
    `insert into internal.notification_outbox(event_type,recipient_profile_id,payload_ref) values('message.message.sent.v1',$1,$2) returning id`,
    [noDevice, { thread_id: thread, message_id: '80000000-0000-4000-8000-000000000009' }])]);
  assert.equal(silent.reply, null);
  assert.equal(await one('select count(*)::int from internal.push_reply_tokens'), tokensBefore);

  // 2. No reply button for announcements or closed threads.
  assert.equal((await push(announcement)).reply, null);
  assert.equal((await push(closed)).reply, null);

  // 3. The reply is sent as the recipient, trimmed, once.
  await db.query("select set_config('request.jwt.claim.sub','',false)");
  const key = '70000000-0000-4000-8000-000000000001';
  const sent = await service('select api.reply_from_push($1,$2,$3)', [message.reply.token, '  Jag kommer!  ', key]);
  assert.deepEqual(sent, { sent: true, message_id: '80000000-0000-4000-8000-000000000001' });
  assert.deepEqual((await db.query('select * from public.sent')).rows, [{ actor: anna, thread, body: 'Jag kommer!', idempotency_key: key }]);
  assert.equal(await one("select coalesce(current_setting('request.jwt.claim.sub',true),'')"), '', 'claims are restored');
  assert.deepEqual(await service('select api.reply_from_push($1,$2,$3)', [message.reply.token, 'igen', key]),
    { sent: true, repeated: true });
  assert.equal(await one('select count(*)::int from public.sent'), 1, 'one reply per notification');

  // 4. Empty, oversized and malformed input; unknown and expired tokens; a thread closed meanwhile.
  const fresh = await push(thread);
  await reject(() => service('select api.reply_from_push($1,$2,$3)', [fresh.reply.token, '   ', key]), /invalid_input/);
  await reject(() => service('select api.reply_from_push($1,$2,$3)', [fresh.reply.token, 'x'.repeat(4001), key]), /invalid_input/);
  await reject(() => service('select api.reply_from_push($1,$2,$3)', ['nope', 'hej', key]), /invalid_input/);
  await reject(() => service('select api.reply_from_push($1,$2,$3)', ['0'.repeat(64), 'hej', key]), /invalid_or_expired_token/);
  await db.query("update core.message_threads set state='closed' where id=$1", [thread]);
  await reject(() => service('select api.reply_from_push($1,$2,$3)', [fresh.reply.token, 'hej', key]), /not_found/);
  await db.query("update core.message_threads set state='active' where id=$1", [thread]);
  await db.query("update internal.push_reply_tokens set expires_at=now()-interval '1 second' where consumed_at is null");
  await reject(() => service('select api.reply_from_push($1,$2,$3)', [fresh.reply.token, 'hej', key]), /invalid_or_expired_token/);

  // 5. Service role only; the table is not readable by users.
  for (const role of ['anon', 'authenticated']) {
    assert.equal(await one('select has_function_privilege($1,$2,$3)', [role, 'api.reply_from_push(text,text,uuid)', 'execute']), false, role);
    assert.equal(await one('select has_table_privilege($1,$2,$3)', [role, 'internal.push_reply_tokens', 'select']), false, role);
  }
  assert.equal(await one('select has_function_privilege($1,$2,$3)', ['service_role', 'api.reply_from_push(text,text,uuid)', 'execute']), true);
  await db.exec('rollback');
  console.log('push message reply: ok');
} finally {
  await db.close();
}
