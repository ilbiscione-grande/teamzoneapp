// Webtools Bokningshanterare (2026-10-20), in isolated Postgres with a
// reduced schema. node supabase/tests/booking_manager.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const owner = id(1), friend = id(2), coach = id(3), clubAdmin = id(4), stranger = id(5);
const club = id(10), team = id(20), otherTeam = id(21), event = id(30), otherEvent = id(31);
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who ?? '']);
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
const call = async (who, sql, params = []) => { await as(who); return asRole('authenticated', async () => Object.values((await db.query(sql, params)).rows[0] ?? {})[0]); };
const fails = async (who, sql, params, pattern) => {
  await db.exec('savepoint s');
  // No finally: in an aborted transaction it would hide the real error. The
  // rollback also undoes the role set inside the call.
  await assert.rejects(call(who, sql, params), pattern);
  await db.exec('rollback to s');
};
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
set check_function_bodies = off;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table auth.users(id uuid primary key, email text);
insert into auth.users values ('${owner}','olle@example.se'),('${friend}','frida@example.se'),('${coach}','coach@example.se'),('${clubAdmin}','admin@example.se'),('${stranger}','sten@example.se');
create table core.profiles(id uuid primary key, display_name text);
insert into core.profiles values ('${owner}','Olle'),('${friend}',''),('${coach}','Coach'),('${clubAdmin}','Adam'),('${stranger}','Sten');
create table core.clubs(id uuid primary key, name text); insert into core.clubs values ('${club}','Demoklubben IF');
create table core.teams(id uuid primary key, club_id uuid, name text, status text default 'active');
insert into core.teams values ('${team}','${club}','P2012'),('${otherTeam}','${club}','F2013');
create table core.club_people(id uuid primary key, club_id uuid, display_name text);
insert into core.club_people values ('${id(50)}','${club}','Coach Person'),('${id(51)}','${club}','Adam Admin');
create table core.person_account_links(profile_id uuid, club_id uuid, club_person_id uuid, state text);
insert into core.person_account_links values ('${coach}','${club}','${id(50)}','active'),('${clubAdmin}','${club}','${id(51)}','active');
create table core.assignments(id uuid primary key default gen_random_uuid(), club_id uuid, team_id uuid, club_person_id uuid, role_package text, state text default 'active',
  starts_at timestamptz default now()-interval '1 year', ends_at timestamptz);
insert into core.assignments(id, club_id, team_id, club_person_id, role_package) values (gen_random_uuid(),'${club}','${team}','${id(50)}','leader'),
  ('${id(61)}','${club}',null,'${id(51)}','club_functionary');
create table core.capability_grants(club_id uuid, assignment_id uuid, capability text, scope_type text, scope_id uuid, starts_at timestamptz default now()-interval '1 day', ends_at timestamptz);
insert into core.capability_grants(club_id, assignment_id, capability, scope_type, scope_id) values ('${club}','${id(61)}','club.memberships.manage','club','${club}');
create table internal.notification_outbox(id uuid primary key default gen_random_uuid(), club_id uuid, domain_event_id uuid, event_type text,
  aggregate_type text, aggregate_id uuid, recipient_profile_id uuid, recipient_person_id uuid, payload_ref jsonb, state text default 'pending',
  unique(domain_event_id, recipient_person_id));
create table core.events(id uuid primary key, title text, event_type text, state text, starts_at timestamptz, ends_at timestamptz, archived_at timestamptz, home_away text, opponent_name text);
insert into core.events values ('${event}','Bortamatch','match','scheduled',now()+interval '3 days',now()+interval '3 days 2 hours',null,'away','Aneby SK'),
  ('${otherEvent}','F-träning','training','scheduled',now()+interval '3 days',now()+interval '3 days 1 hour',null,null,null);
create table core.event_teams(event_id uuid, club_id uuid, team_id uuid);
insert into core.event_teams values ('${event}','${club}','${team}'),('${otherEvent}','${club}','${otherTeam}');
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as
  $$select auth.uid() = '${clubAdmin}'::uuid and cap = 'club.memberships.manage'$$;
create function internal.actor_can_read_event(e uuid) returns boolean language sql stable as $$select auth.uid() in ('${coach}'::uuid, '${clubAdmin}'::uuid)$$;
grant usage on schema api, internal, core, auth to authenticated;`);
await db.exec(read('supabase/migrations/20261115090000_booking_manager.sql'));
await db.exec(read('supabase/migrations/20261115100000_booking_team_events_venue.sql'));
await db.exec(read('supabase/migrations/20261116090000_booking_notifications.sql'));
await db.exec('begin');

// Standalone: anyone signed in creates an organisation and becomes admin.
const org = await call(owner, "select api.create_booking_organization('Bollklubben','club','Fotboll')");
const orgs = await call(owner, 'select api.list_booking_organizations()');
assert.deepEqual(orgs.map(o => [o.name, o.role]), [['Bollklubben', 'admin']]);
assert.deepEqual(await call(stranger, 'select api.list_booking_organizations()'), []);
await fails(stranger, 'select api.get_booking_organization($1)', [org], /not_found/);

const pitch = await call(owner, "select api.save_booking_resource($1,null,'Plan 1','pitch',null,'Demovallen',null,false,true)", [org]);
const bus = await call(owner, "select api.save_booking_resource($1,null,'Minibuss','vehicle','9 platser',null,9,true,true)", [org]);
await fails(stranger, "select api.save_booking_resource($1,null,'X','other',null,null,null,false,true)", [org], /not_admin/);

// Invitation by link: the token works once, for one account.
const token = await call(owner, "select api.create_booking_invitation($1,'booker')", [org]);
assert.match(token, /^[0-9a-f]{64}$/);
assert.equal(await call(friend, 'select api.accept_booking_invitation($1)', [token]), org);
await fails(stranger, 'select api.accept_booking_invitation($1)', [token], /invitation_invalid/);
await fails(stranger, 'select api.accept_booking_invitation($1)', ['0'.repeat(64)], /invitation_invalid/);
const details = await call(owner, 'select api.get_booking_organization($1)', [org]);
assert.deepEqual(details.members.map(m => [m.name, m.role]), [['Olle', 'admin'], ['frida', 'booker']], 'no name: the address before @');
assert.equal((await call(friend, 'select api.get_booking_organization($1)', [org])).members, null, 'members for admins only');

// Booking: a direct resource confirms, an approval resource waits.
const t = h => new Date(Date.now() + h * 3600e3).toISOString();
const confirmed = await call(friend, 'select api.create_booking($1,$2,$3,$4,null,null,null)', [pitch, t(24), t(26), 'Träning']);
assert.equal(confirmed.status, 'confirmed');
await fails(friend, 'select api.create_booking($1,$2,$3,null,null,null,null)', [pitch, t(25), t(27)], /resource_busy/);
const back = await call(friend, 'select api.create_booking($1,$2,$3,null,null,null,null)', [pitch, t(26), t(27)]);
assert.equal(back.status, 'confirmed', 'touching ends do not clash');
const request = await call(friend, 'select api.create_booking($1,$2,$3,$4,null,null,null)', [bus, t(48), t(52), 'Cup']);
assert.equal(request.status, 'pending');
assert.equal(request.can_decide, false);
const inbox = async who => call(who, 'select api.list_booking_notifications()');
assert.deepEqual((await inbox(owner)).items.map(n => [n.kind, n.resource_name, n.read]), [['requested', 'Minibuss', false]]);
assert.equal((await inbox(friend)).unread, 0, 'not the one who asked');
const pending = await call(owner, 'select api.list_pending_bookings($1)', [org]);
assert.deepEqual(pending.map(b => [b.resource_name, b.can_decide]), [['Minibuss', true]]);
await fails(friend, 'select api.decide_booking($1,true)', [request.id], /not_admin/);
await call(owner, 'select api.decide_booking($1,true)', [request.id]);
assert.deepEqual((await inbox(friend)).items.map(n => n.kind), ['approved']);
await fails(owner, 'select api.create_booking($1,$2,$3,null,null,null,null)', [bus, t(50), t(51)], /resource_busy/);
await fails(friend, 'select api.create_booking($1,$2,$3,null,null,null,null)', [pitch, t(-3), t(-2)], /in_the_past/);
const list = await call(stranger === friend ? owner : friend, 'select api.list_bookings($1,$2,$3)', [org, t(0), t(72)]);
assert.equal(list.length, 3);
// Only the booker or an admin cancels.
const ownerBooking = await call(owner, 'select api.create_booking($1,$2,$3,null,null,null,null)', [pitch, t(30), t(31)]);
await fails(friend, 'select api.cancel_booking($1)', [ownerBooking.id], /not_allowed/);
await call(friend, 'select api.cancel_booking($1)', [back.id]);
assert.equal((await inbox(friend)).unread, 1, 'cancelling your own booking tells nobody');
await call(owner, 'select api.cancel_booking($1)', [confirmed.id]);
assert.deepEqual((await inbox(friend)).items.map(n => n.kind), ['cancelled', 'approved']);
await call(friend, 'select api.mark_booking_notifications_read()');
assert.equal((await inbox(friend)).unread, 0);
assert.equal(Number((await db.query('select count(*) from internal.notification_outbox')).rows[0].count), 0, 'no push without a club');
assert.equal((await call(owner, 'select api.list_bookings($1,$2,$3)', [org, t(0), t(72)])).length, 2);

// TeamZone: only a club admin links; then the club's leaders book, for
// their own team and its activities.
await fails(owner, 'select api.set_booking_organization_club($1,$2)', [org, club], /not_club_admin/);
assert.deepEqual(await call(coach, 'select api.list_booking_organizations()'), []);
const clubOrg = await call(clubAdmin, "select api.create_booking_organization('Demoklubben IF','club',null)");
await call(clubAdmin, 'select api.set_booking_organization_club($1,$2)', [clubOrg, club]);
await fails(clubAdmin, 'select api.set_booking_organization_club($1,$2)', [org, club], /not_admin|club_already_linked/);
const coachOrgs = await call(coach, 'select api.list_booking_organizations()');
assert.deepEqual(coachOrgs.map(o => [o.name, o.role, o.teamzone_club_name]), [['Demoklubben IF', 'booker', 'Demoklubben IF']]);
const locker = await call(clubAdmin, "select api.save_booking_resource($1,null,'Omklädningsrum 2','locker_room',null,null,null,false,true)", [clubOrg]);
const clubBus = await call(clubAdmin, "select api.save_booking_resource($1,null,'Minibuss','vehicle',null,null,9,true,true)", [clubOrg]);
const coachView = await call(coach, 'select api.get_booking_organization($1)', [clubOrg]);
assert.deepEqual(coachView.teams, [{ team_id: team, name: 'P2012' }]);
const events = await call(coach, 'select api.list_booking_team_events($1,$2)', [clubOrg, team]);
assert.deepEqual(events.map(e => [e.title, e.home_away, e.opponent_name]), [['Bortamatch', 'away', 'Aneby SK']]);
await fails(coach, 'select api.list_booking_team_events($1,$2)', [clubOrg, otherTeam], /not_team_leader/);
const busForMatch = await call(coach, 'select api.create_booking($1,$2,$3,$4,null,$5,$6)', [clubBus, t(70), t(76), 'Bortamatch', team, event]);
assert.equal(busForMatch.status, 'pending');
assert.equal(busForMatch.team_name, 'P2012');
assert.equal(busForMatch.event_title, 'Bortamatch');
// The club's admin hears of it in Webtools and as a push opening the match.
assert.deepEqual((await inbox(clubAdmin)).items.map(n => [n.kind, n.organization_name]), [['requested', 'Demoklubben IF']]);
const pushes = (await db.query('select event_type, aggregate_type, aggregate_id, recipient_person_id from internal.notification_outbox')).rows;
assert.deepEqual(pushes, [{ event_type: 'booking.requested.v1', aggregate_type: 'event', aggregate_id: event, recipient_person_id: id(51) }]);
await fails(coach, 'select api.create_booking($1,$2,$3,null,null,$4,null)', [locker, t(70), t(71), otherTeam], /not_team_leader/);
await fails(coach, 'select api.create_booking($1,$2,$3,null,null,$4,$5)', [locker, t(70), t(71), team, otherEvent], /event_not_found/);
await fails(coach, 'select api.create_booking($1,$2,$3,null,null,null,$4)', [locker, t(70), t(71), event], /event_needs_team/);
// The app: the activity lists its bookings for those who see it.
const onEvent = await call(coach, 'select api.list_event_bookings($1)', [event]);
assert.deepEqual(onEvent.map(b => [b.resource_name, b.status, b.organization_name]), [['Minibuss', 'pending', 'Demoklubben IF']]);
await fails(stranger, 'select api.list_event_bookings($1)', [event], /not_found/);
// Members can be turned off for the club.
await call(clubAdmin, "select api.update_booking_organization($1,'Demoklubben IF','club',null,false)", [clubOrg]);
assert.deepEqual(await call(coach, 'select api.list_booking_organizations()'), []);
console.log('booking manager: ok');
