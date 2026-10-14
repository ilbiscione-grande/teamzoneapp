// Answering a callup from its notification: the real push migrations in
// isolated Postgres, with the app's callup answer stubbed (its rules are
// tested with the callup migrations).
// node supabase/tests/push_callup_response.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
import { pgcrypto } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/contrib/pgcrypto.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite({ extensions: { pgcrypto } });
const anna = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', parent = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const annaPerson = 'a0000000-0000-4000-8000-000000000001', parentPerson = 'c0000000-0000-4000-8000-000000000001';
const team = '20000000-0000-4000-8000-000000000001', event = '30000000-0000-4000-8000-000000000001';
const open = '60000000-0000-4000-8000-000000000001', answered = '60000000-0000-4000-8000-000000000002';
const expired = '60000000-0000-4000-8000-000000000003';
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
  insert into core.profiles values('${anna}','sv','Europe/Stockholm'),('${parent}','sv','Europe/Stockholm');
  create table core.teams(id uuid primary key,name text);
  insert into core.teams values('${team}','P2012');
  create table core.events(id uuid primary key,owning_team_id uuid,event_type text,title text,starts_at timestamptz,timezone text);
  insert into core.events values('${event}','${team}','training','Träning','2026-10-17 16:00+00','Europe/Stockholm');
  create table core.thread_scopes(thread_id uuid,club_id uuid,team_id uuid);
  create table core.notification_endpoints(id uuid primary key default gen_random_uuid(),profile_id uuid not null,
   channel text not null,endpoint_hash bytea not null,state text not null default 'active',created_at timestamptz default now(),
   unique(profile_id,channel,endpoint_hash));
  create table internal.notification_outbox(id uuid primary key default gen_random_uuid(),club_id uuid,domain_event_id uuid,
   event_type text,aggregate_type text,aggregate_id uuid,recipient_profile_id uuid,recipient_person_id uuid,payload_ref jsonb not null default '{}',
   state text default 'pending',created_at timestamptz default now());
  create function internal.notification_deep_link(outbox internal.notification_outbox) returns text language sql stable as $$
   select '/calendar/event/'||(outbox.payload_ref->>'event_id')$$;
  create table core.callups(id uuid primary key,event_id uuid,club_person_id uuid,state text,expires_at timestamptz,revision bigint not null default 1);
  insert into core.callups values('${open}','${event}','${annaPerson}','pending',now()+interval '3 days',4),
   ('${answered}','${event}','${annaPerson}','accepted',now()+interval '3 days',2),
   ('${expired}','${event}','${annaPerson}','pending',now()-interval '1 hour',1);
  -- Stub of the app's answer: records who answered, as which person.
  create table public.answers(actor uuid,callup uuid,response text,acting_as uuid,revision bigint,idempotency_key uuid);
  create function internal.respond_callup_for_actor(target_callup_id uuid,new_response text,acting_as_person_id uuid,
   decline_reason_code text,decline_reason_text text,expected_revision bigint,idempotency_key uuid)
  returns bigint language plpgsql security definer set search_path='' as $$
  declare callup core.callups%rowtype;
  begin
   if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
   select * into callup from core.callups where id=target_callup_id;
   if callup.state not in('pending','accepted','declined') or callup.expires_at<=now() then
    raise invalid_parameter_value using message='invalid_state'; end if;
   if callup.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
   insert into public.answers values(auth.uid(),target_callup_id,new_response,acting_as_person_id,expected_revision,idempotency_key);
   update core.callups set state=new_response,revision=revision+1 where id=target_callup_id;
   return callup.revision+1;
  end$$;
  insert into vault.secrets values('project_url','https://example.supabase.co',null);
  grant usage on schema api, internal, core, extensions to authenticated, service_role;
  grant usage on schema vault to service_role;`);
  const strip = sql => sql.replace(/notify pgrst[^;]*;/, '').replace(/create extension if not exists pg_(cron|net);/g, '');
  await db.exec(strip(read('supabase/migrations/20261023090000_push_delivery.sql')));
  await db.exec(strip(read('supabase/migrations/20261024090000_push_callup_response.sql')));
  await db.exec('begin');

  const outbox = (type, callup, profile = anna, person = annaPerson) => one(
    `insert into internal.notification_outbox(event_type,recipient_profile_id,recipient_person_id,payload_ref)
     values($1,$2,$3,$4) returning id`, [type, profile, person, { event_id: event, callup_id: callup }]);
  const push = async id => service('select api.push_message_for_outbox($1)', [id]);

  // 1. A callup waiting for an answer carries a single-use token; only its hash is stored.
  const sent = await push(await outbox('callup.callup.sent.v1', open));
  assert.equal(sent.response.callup_id, open);
  assert.match(sent.response.token, /^[0-9a-f]{64}$/);
  assert.equal(sent.language, 'sv');
  assert.equal(await one('select count(*)::int from internal.push_response_tokens'), 1);
  assert.equal(await one("select count(*)::int from internal.push_response_tokens where encode(token_hash,'hex')=$1", [sent.response.token]), 0,
    'the raw token is not stored');
  assert.equal(await one('select acting_as_person_id from internal.push_response_tokens'), null, 'own callup');
  assert.ok((await push(await outbox('callup.callup.reminded.v2', open))).response, 'reminders can be answered too');

  // 2. Nothing to answer: cancelled, already answered, expired.
  assert.equal((await push(await outbox('callup.callup.cancelled.v2', open))).response, null);
  assert.equal((await push(await outbox('callup.callup.sent.v1', answered))).response, null);
  assert.equal((await push(await outbox('callup.callup.sent.v1', expired))).response, null);

  // 3. A guardian's notification answers for the called child.
  const guardian = await push(await outbox('callup.callup.sent.v1', open, parent, parentPerson));
  assert.equal(await one('select acting_as_person_id from internal.push_response_tokens where recipient_profile_id=$1', [parent]), annaPerson);

  // 4. "Kommer" answers as the recipient, with the current revision, once.
  await db.query("select set_config('request.jwt.claim.sub','',false)");
  const key = '70000000-0000-4000-8000-000000000001';
  const answer = await service('select api.respond_callup_from_push($1,$2)', [sent.response.token, key]);
  assert.deepEqual(answer, { response: 'accepted', revision: 5 });
  const recorded = (await db.query('select * from public.answers')).rows;
  assert.deepEqual(recorded, [{ actor: anna, callup: open, response: 'accepted', acting_as: null, revision: 4, idempotency_key: key }]);
  assert.equal(await one("select coalesce(current_setting('request.jwt.claim.sub',true),'')"), '', 'claims are restored');
  assert.equal(await one('select consumed_at is not null from internal.push_response_tokens where recipient_profile_id=$1 and consumed_at is not null limit 1', [anna]), true);
  const repeated = await service('select api.respond_callup_from_push($1,$2)', [sent.response.token, key]);
  assert.deepEqual(repeated, { response: 'accepted', repeated: true });
  assert.equal(await one('select count(*)::int from public.answers'), 1, 'a second tap answers nothing new');

  // 5. Guardian answer goes through acting-as; a closed callup is refused.
  await service('select api.respond_callup_from_push($1,$2)', [guardian.response.token, '70000000-0000-4000-8000-000000000002']);
  assert.deepEqual(Object.values((await db.query('select actor, acting_as from public.answers order by revision desc limit 1')).rows[0]), [parent, annaPerson]);
  const late = await push(await outbox('callup.callup.sent.v1', open));
  assert.equal(late.response, null, 'the callup is no longer pending');
  await db.query("update core.callups set state='pending' where id=$1", [open]);
  const reopened = await push(await outbox('callup.callup.sent.v1', open));
  await db.query("update core.callups set state='cancelled' where id=$1", [open]);
  await reject(() => service('select api.respond_callup_from_push($1,$2)', [reopened.response.token, '70000000-0000-4000-8000-000000000003']), /invalid_state/);

  // 6. Unknown, malformed and expired tokens.
  await reject(() => service('select api.respond_callup_from_push($1,$2)', ['0'.repeat(64), key]), /invalid_or_expired_token/);
  await reject(() => service('select api.respond_callup_from_push($1,$2)', ['not-a-token', key]), /invalid_input/);
  await db.query("update core.callups set state='pending' where id=$1", [open]);
  const stale = await push(await outbox('callup.callup.sent.v1', open));
  await db.query("update internal.push_response_tokens set expires_at=now()-interval '1 second' where consumed_at is null");
  await reject(() => service('select api.respond_callup_from_push($1,$2)', [stale.response.token, key]), /invalid_or_expired_token/);

  // 7. Service role only; the table is not readable by users.
  for (const role of ['anon', 'authenticated']) {
    assert.equal(await one('select has_function_privilege($1,$2,$3)', [role, 'api.respond_callup_from_push(text,uuid)', 'execute']), false, role);
    assert.equal(await one('select has_table_privilege($1,$2,$3)', [role, 'internal.push_response_tokens', 'select']), false, role);
  }
  assert.equal(await one('select has_function_privilege($1,$2,$3)', ['service_role', 'api.respond_callup_from_push(text,uuid)', 'execute']), true);
  await db.exec('rollback');
  console.log('push callup response: ok');
} finally {
  await db.close();
}
