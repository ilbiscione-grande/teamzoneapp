// Team page requests are heard (2026-10-24): a request tells the club's
// publication managers, the decision tells the one who asked, and the club
// home counts what waits. node supabase/tests/team_page_request_notifications.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), admin = id(2), club = id(10), team = id(20);
const [coachPerson, adminPerson] = [id(41), id(42)], adminAssignment = id(51);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth; create schema audit; create schema extensions;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key, timezone text, language text);
create table core.teams(id uuid primary key, club_id uuid, name text, status text default 'active');
insert into core.teams values ('${team}','${club}','P2012','active');
create table core.club_people(id uuid primary key, club_id uuid, display_name text);
insert into core.club_people values ('${coachPerson}','${club}','Hugo'),('${adminPerson}','${club}','Thomas');
create table core.person_account_links(club_id uuid, club_person_id uuid, profile_id uuid, state text);
insert into core.person_account_links values ('${club}','${coachPerson}','${coach}','active'),('${club}','${adminPerson}','${admin}','active');
create table core.assignments(id uuid primary key, club_id uuid, club_person_id uuid, state text, starts_at timestamptz, ends_at timestamptz, team_id uuid);
insert into core.assignments values ('${adminAssignment}','${club}','${adminPerson}','active', now() - interval '1 day', null, null);
create table core.capability_grants(club_id uuid, assignment_id uuid, capability text, scope_type text, scope_id uuid, starts_at timestamptz, ends_at timestamptz);
insert into core.capability_grants values ('${club}','${adminAssignment}','publication.manage','club','${club}', now() - interval '1 day', null);
create table core.team_publication_requests(id uuid primary key default gen_random_uuid(), club_id uuid, team_id uuid, requested_by uuid,
  message text, status text default 'pending', decided_by uuid, decided_at timestamptz, decision_note text, created_at timestamptz default now());
create table audit.command_events(club_id uuid, actor_profile_id uuid, command_type text, aggregate_type text, aggregate_id uuid,
  aggregate_revision bigint, metadata jsonb);
create table internal.notification_outbox(id uuid primary key default gen_random_uuid(), club_id uuid, domain_event_id uuid, event_type text,
  aggregate_type text, aggregate_id uuid, recipient_profile_id uuid, recipient_person_id uuid, payload_ref jsonb, state text default 'pending',
  unique (domain_event_id, recipient_person_id));
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$
  select (auth.uid() = '${coach}'::uuid and cap = 'team.roster.manage') or (auth.uid() = '${admin}'::uuid and cap = 'publication.manage') $$;
-- The club home's other parts, as far as it reads them.
create type internal.my_context as (context_id uuid, club_id uuid, team_id uuid);
create function internal.get_my_contexts_for_actor() returns setof internal.my_context language sql stable as $$
  select '${id(90)}'::uuid, '${club}'::uuid, null::uuid $$;
create table core.board_mandates(club_id uuid, office text, state text, starts_at timestamptz, ends_at timestamptz, assignment_id uuid);
create table core.board_mandate_changes(club_id uuid, state text);
create table core.economy_accounts(club_id uuid, state text);
create table core.economy_ledger_entries(club_id uuid, state text);
create table core.membership_applications(club_id uuid, status text);
create table core.team_creation_requests(club_id uuid, state text);
create table core.team_memberships(team_id uuid);
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, title text, starts_at timestamptz, state text,
  event_type text, location_id uuid, timezone text, archived_at timestamptz, ends_at timestamptz, all_day boolean);
create table core.event_teams(event_id uuid, club_id uuid, team_id uuid);
create table core.event_locations(id uuid primary key, name text);
create table core.callups(id uuid primary key, club_id uuid, club_person_id uuid, expires_at timestamptz);
create table core.message_threads(id uuid primary key, state text, thread_type text);
grant usage on schema api, internal, core, auth, audit to authenticated;`);
// A request from before the notifications, waiting.
await db.query("insert into core.team_publication_requests(club_id, team_id, requested_by, message) values ($1, $2, $3, 'gammal')", [club, id(21), coach]);
await db.query("insert into core.teams values ($1, $2, 'F2013', 'active')", [id(21), club]);
const migration = read('supabase/migrations/20261207110000_team_page_request_notifications.sql');
// The whole migration loads; the push text itself is the existing one plus a branch.
await db.exec(migration);
const call = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  const rows = (await db.query(sql, params)).rows;
  return Object.values(rows[0] ?? {})[0];
};
const outbox = async () => (await db.query(
  'select event_type, recipient_profile_id, payload_ref from internal.notification_outbox order by event_type')).rows;

// The one already waiting was told to Thomas when the migration ran.
assert.deepEqual((await outbox()).map(row => [row.event_type, row.recipient_profile_id, row.payload_ref.team_id]),
  [['publication.team_page.requested.v1', admin, id(21)]]);
await db.exec('delete from internal.notification_outbox');
await db.query("update core.team_publication_requests set status = 'approved'");

// Hugo asks for P2012's page: Thomas hears of it, Hugo does not.
const request = await call(coach, "select internal.request_team_publication_for_actor($1,$2,'Vi vill visa våra matcher')", [club, team]);
assert.equal(request.status, 'pending');
let sent = await outbox();
assert.deepEqual(sent.map(row => [row.event_type, row.recipient_profile_id]), [['publication.team_page.requested.v1', admin]]);
assert.equal(sent[0].payload_ref.team_id, team);
assert.equal(JSON.stringify(sent[0].payload_ref).includes('matcher'), false, 'the message stays out');
assert.equal(await call(coach, "select (internal.request_team_publication_for_actor($1,$2,'igen'))->>'status'", [club, team]), 'pending');
assert.equal((await outbox()).length, 1, 'asking again while pending tells no one again');

// The titles, previews and the link to Public pages.
assert.equal(await call(admin, "select internal.notification_title('publication.team_page.requested.v1')"), 'Ansökan om lagsida');
assert.match(await call(admin, "select internal.notification_preview('publication.team_page.approved.v1')"), /godkänt/);
assert.equal(await call(admin, "select internal.notification_deep_link(o) from internal.notification_outbox o limit 1"), '/publication');

// The club home counts it for Thomas, not for Hugo.
const home = await call(admin, 'select internal.get_club_home_for_actor($1)', [id(90)]);
assert.equal(home.publication.pending_team_pages, 1);
assert.equal((await call(coach, 'select internal.get_club_home_for_actor($1)', [id(90)])).publication, null);

// Thomas approves: Hugo hears of it.
await call(admin, 'select internal.decide_team_publication_for_actor($1, true, null)', [request.id]);
sent = await outbox();
assert.deepEqual(sent.map(row => [row.event_type, row.recipient_profile_id]),
  [['publication.team_page.approved.v1', coach], ['publication.team_page.requested.v1', admin]]);
console.log('team page request notifications: ok');
