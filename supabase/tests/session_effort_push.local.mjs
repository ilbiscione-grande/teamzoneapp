// The effort question as a notification (2026-11-02): queued when a
// training ends for the players who were there, with a token for the
// answers 1–10 in the notification, answered through that token.
// node supabase/tests/session_effort_push.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const club = id(10), team = id(20), open = id(30), called = id(31);
const [ada, bo, cy, dan, eve, fia] = [id(50), id(51), id(52), id(53), id(54), id(55)];
const login = person => person.replace('-8000-0000000000', '-9000-0000000000');
const year = new Date().getFullYear();
await db.exec(`create role anon; create role authenticated; create role service_role;
create schema internal; create schema api; create schema core; create schema auth; create schema extensions;
create function auth.uid() returns uuid language sql stable as $$select null::uuid$$;
create function extensions.digest(value text, kind text) returns bytea language sql immutable as $$select sha256(convert_to(value,'UTF8'))$$;
create function extensions.gen_random_bytes(n integer) returns bytea language sql volatile as
  $$select decode(replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-',''),'hex')$$;
create function extensions.pgp_sym_decrypt(value bytea, key text) returns text language sql immutable as $$select convert_from(value,'UTF8')$$;
create function internal.push_token_key() returns text language sql as $$select 'key'$$;
create function internal.push_local_time(at timestamptz, zone text, swedish boolean) returns text language sql as $$select '17:30'$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key, display_name text not null default '', locale text, timezone text);
create table core.teams(id uuid primary key, club_id uuid, name text); insert into core.teams values ('${team}','${club}','P2012');
create table core.club_people(id uuid primary key, club_id uuid, display_name text, status text default 'active',
  birth_date date, birth_year smallint);
create table core.person_account_links(profile_id uuid, club_id uuid, club_person_id uuid, state text);
create table core.assignments(id uuid primary key default gen_random_uuid(), club_id uuid, team_id uuid, club_person_id uuid,
  role_package text, state text);
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, starts_at timestamptz, ends_at timestamptz,
  event_type text default 'training', archived_at timestamptz, state text default 'scheduled',
  timezone text default 'Europe/Stockholm', title text default 'Träning', callups_required boolean default false);
insert into core.events(id, club_id, owning_team_id, starts_at, ends_at, callups_required) values
  ('${open}','${club}','${team}', now() - interval '95 minutes', now() - interval '5 minutes', false),
  ('${called}','${club}','${team}', now() - interval '100 minutes', now() - interval '10 minutes', true);
create table core.attendance_facts(event_id uuid, club_person_id uuid, status text, minutes integer);
create table core.callups(id uuid primary key default gen_random_uuid(), event_id uuid, club_person_id uuid, state text);
create table core.event_absence_notices(event_id uuid, club_person_id uuid, withdrawn_at timestamptz);
create table core.development_plans(id uuid primary key, club_id uuid, team_id uuid);
create table core.club_entitlements(club_id uuid, entitlement_key text, access_mode text, expires_at timestamptz);
create function internal.actor_has_club_access(target uuid) returns boolean language sql stable as $$ select true $$;
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$ select false $$;
create table internal.notification_outbox(id uuid primary key default gen_random_uuid(), club_id uuid, domain_event_id uuid,
  event_type text, aggregate_type text, aggregate_id uuid, recipient_profile_id uuid, recipient_person_id uuid,
  payload_ref jsonb default '{}', state text default 'pending', created_at timestamptz default now(),
  unique(domain_event_id, recipient_person_id));
create function internal.notification_deep_link(outbox internal.notification_outbox) returns text language sql as
  $$select '/calendar/event/' || outbox.aggregate_id$$;
create table core.message_threads(id uuid primary key, state text, thread_type text);
create table core.notification_endpoints(id uuid primary key default gen_random_uuid(), profile_id uuid, channel text, state text);
create table internal.push_endpoint_tokens(endpoint_id uuid primary key, platform text, token_ciphertext bytea);`);
// Ada 14, Bo 12, Cy 14 reported absent, Dan 14 answered, Eve 14 opted
// out, Fia 14 without an account.
const people = [[ada, 'Ada', 14], [bo, 'Bo', 12], [cy, 'Cy', 14], [dan, 'Dan', 14], [eve, 'Eve', 14], [fia, 'Fia', 14]];
for (const [person, name, age] of people) {
  await db.exec(`insert into core.club_people(id, club_id, display_name, birth_year) values ('${person}','${club}','${name}',${year - age});
    insert into core.assignments(club_id, team_id, club_person_id, role_package, state) values ('${club}','${team}','${person}','player','active');`);
  if (person !== fia) {
    await db.exec(`insert into core.profiles(id) values ('${login(person)}');
      insert into core.person_account_links values ('${login(person)}','${club}','${person}','active');`);
  }
}
const endpoint = id(90);
await db.exec(`insert into core.notification_endpoints values ('${endpoint}','${login(ada)}','push','active');
insert into internal.push_endpoint_tokens values ('${endpoint}','android', convert_to('fcm-token','UTF8'));
insert into core.event_absence_notices values ('${open}','${cy}',null);`);
for (const name of ['20261202090000_module_foundation', '20270131090000_team_development_load', '20270201090000_session_effort', '20270202090000_session_effort_push']) {
  await db.exec(read(`supabase/migrations/${name}.sql`));
}
await db.exec(`insert into core.session_effort_ratings(club_id, event_id, club_person_id, rating) values ('${club}','${open}','${dan}',5);
insert into core.session_effort_opt_outs(club_person_id, club_id) values ('${eve}','${club}');
insert into core.callups(event_id, club_person_id, state) values ('${called}','${ada}','accepted'),('${called}','${cy}','declined'),
  ('${called}','${dan}','pending');
insert into core.attendance_facts values ('${called}','${cy}','present',null);`);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0] ?? {})[0];
const queued = async () => (await db.query(`select aggregate_id, recipient_person_id, recipient_profile_id from internal.notification_outbox
  where event_type = 'effort.asked.v1' order by aggregate_id, recipient_person_id`)).rows;

assert.equal(await one('select internal.enqueue_session_effort_pushes()'), 0, 'off until the leaders turn it on');
await db.exec(`insert into core.team_development_load_settings(team_id, club_id, effort_push) values ('${team}','${club}',true)`);
assert.equal(await one('select internal.enqueue_session_effort_pushes()'), 3);
assert.equal(await one('select internal.enqueue_session_effort_pushes()'), 0, 'once per training and player');
assert.deepEqual((await queued()).map(r => [r.aggregate_id, r.recipient_person_id]),
  [[open, ada], [called, ada], [called, cy]]);
assert.equal((await queued())[0].recipient_profile_id, login(ada), 'to the player\'s own account');
assert.equal((await one('select internal.tdp_load_settings($1)', [team])).effort_push, true);
console.log('PASS: queued, once the leaders turned it on, for those who were there: no absence, an accepted callup, or attendance taken');

const outbox = await one(`select id from internal.notification_outbox where aggregate_id = $1 and recipient_person_id = $2`, [open, ada]);
const message = await one('select internal.push_message_for_outbox($1)', [outbox]);
assert.equal(message.title, 'Hur kändes träningen?');
assert.equal(message.body, 'Träning · P2012 · 17:30');
assert.equal(message.route, `/calendar/event/${open}`);
assert.equal(message.effort.event_id, open);
assert.match(message.effort.token, /^[0-9a-f]{64}$/);
assert.deepEqual(message.targets.map(t => t.token), ['fcm-token']);
assert.equal(await one('select internal.notification_title($1)', ['effort.asked.v1']), 'Hur kändes träningen?');
console.log('PASS: the notification asks with a token for the answers in it');

const token = message.effort.token;
assert.deepEqual(await one('select api.respond_effort_from_push($1,$2)', [token, 7]), { rating: 7 });
assert.deepEqual(await one('select api.respond_effort_from_push($1,$2)', [token, 9]), { rating: 9 });
assert.equal(await one('select rating from core.session_effort_ratings where event_id = $1 and club_person_id = $2', [open, ada]), 9,
  'the last answer counts');
await assert.rejects(db.query('select api.respond_effort_from_push($1,$2)', ['0'.repeat(64), 5]), /invalid_or_expired_token/);
await assert.rejects(db.query('select api.respond_effort_from_push($1,$2)', [token, 11]), /invalid_input/);
assert.equal(await one('select internal.push_message_for_outbox($1)', [outbox]), null, 'not sent once answered');
console.log('PASS: the answer from the notification is saved through the token');

await db.exec(`insert into core.session_effort_opt_outs(club_person_id, club_id) values ('${ada}','${club}')`);
await assert.rejects(db.query('select api.respond_effort_from_push($1,$2)', [token, 4]), /invalid_state/);
await db.exec(`update internal.push_effort_tokens set expires_at = now() - interval '1 minute'`);
await assert.rejects(db.query('select api.respond_effort_from_push($1,$2)', [token, 4]), /invalid_or_expired_token/);
console.log('PASS: no answer after opting out or once the token has expired');
