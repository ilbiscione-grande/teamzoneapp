// Webtools Turneringsplanerare (2026-10-21), in isolated Postgres with a
// reduced schema. node supabase/tests/tournament_planner.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const host = id(1), coach = id(2), other = id(3), helper = id(4);
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who ?? '']);
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
const call = async (who, sql, params = []) => { await as(who); return asRole('authenticated', async () => Object.values((await db.query(sql, params)).rows[0] ?? {})[0]); };
const fails = async (who, sql, params, pattern) => {
  await db.exec('savepoint s');
  // No finally: in an aborted transaction it would hide the real error.
  await assert.rejects(call(who, sql, params), pattern);
  await db.exec('rollback to s');
};
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
set check_function_bodies = off;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table auth.users(id uuid primary key, email text);
insert into auth.users values ('${host}','hanna@example.se'),('${coach}','coach@example.se'),('${other}','otto@example.se'),('${helper}','helga@example.se');
create table core.profiles(id uuid primary key, display_name text);
insert into core.profiles values ('${host}','Hanna'),('${coach}','Coach'),('${other}','Otto'),('${helper}','Helga');
create table core.clubs(id uuid primary key, name text);
create table core.teams(id uuid primary key, club_id uuid, name text);
create table core.club_people(id uuid primary key, display_name text);
create table core.person_account_links(profile_id uuid, club_id uuid, club_person_id uuid, state text);
create function internal.booking_person_name(p uuid) returns text language sql stable as $$select display_name from core.profiles where id = p$$;
grant usage on schema api, internal, core, auth to authenticated;`);
await db.exec(read('supabase/migrations/20261119090000_tournament_planner.sql'));
await db.exec('begin');

// The organiser creates a draft; nobody else sees it.
const cup = await call(host, "select api.create_tournament('Höstcupen',' Fotboll ','Demovallen','2026-11-14','2026-11-15')");
await fails(host, "select api.create_tournament('Fel','Fotboll',null,'2026-11-15','2026-11-14')", [], /invalid_dates/);
await fails(coach, 'select api.get_tournament($1)', [cup], /not_found/);
const p12 = await call(host, "select api.save_tournament_class($1,null,'P12','Födda 2014','groups_playoff',2,1500,15,1)", [cup]);
const knatte = await call(host, "select api.save_tournament_class($1,null,'Knatte','Födda 2019','pool',null,null,10,2)", [cup]);
await fails(host, "select api.save_tournament_class($1,null,'p12',null,'pool',null,null,null,3)", [cup], /class_name_taken/);
await fails(coach, "select api.save_tournament_class($1,null,'F13',null,'pool',null,null,null,3)", [cup], /not_organizer/);

// Published but closed: seen, no registration yet.
const update = (status, open) => call(host, "select api.update_tournament($1,'Höstcupen','Fotboll','Demovallen','2026-11-14','2026-11-15','Välkomna!','cup@example.se','Swish 123 456 78 90',$2,$3,null)", [cup, status, open]);
await update('published', false);
const seen = await call(coach, 'select api.get_tournament($1)', [cup]);
assert.equal(seen.registration_is_open, false);
assert.equal(seen.staff, null, 'only the organiser sees the staff');
assert.deepEqual(seen.classes.map(c => [c.name, c.fee_sek, c.approved]), [['P12', 1500, 0], ['Knatte', null, 0]]);
const register = (who, cls, team) => call(who, "select api.register_tournament_team($1,$2,'Demoklubben','Coach Carl','coach@example.se',null,null)", [cls, team]);
await fails(coach, "select api.register_tournament_team($1,'Demo P12',null,'Carl','coach@example.se',null,null)", [p12], /registration_closed/);

// Open: teams register, one name per class, the e-mail checked.
await update('published', true);
const first = await register(coach, p12, 'Demo P12');
assert.equal(first.status, 'pending');
await fails(other, "select api.register_tournament_team($1,' demo p12 ',null,'Otto','otto@example.se',null,null)", [p12], /team_name_taken/);
await fails(other, "select api.register_tournament_team($1,'Aneby',null,'Otto','inte-en-adress',null,null)", [p12], /invalid_email/);
const second = await register(other, p12, 'Aneby SK');
const third = await register(other, p12, 'Eksjö FF');
await register(other, knatte, 'Aneby Knatte');
assert.deepEqual((await call(coach, 'select api.list_my_tournaments()')).map(t => [t.name, t.role, t.pending]), [['Höstcupen', 'participant', null]]);
assert.equal((await call(host, 'select api.list_my_tournaments()'))[0].pending, 4);
await fails(coach, 'select api.list_tournament_registrations($1)', [cup], /not_found/);

// The organiser approves until the class is full, and ticks off fees.
await call(host, 'select api.decide_tournament_registration($1,true)', [first.id]);
await call(host, 'select api.decide_tournament_registration($1,true)', [second.id]);
await fails(host, 'select api.decide_tournament_registration($1,true)', [third.id], /class_full/);
await fails(other, "select api.register_tournament_team($1,'Vetlanda',null,'Otto','otto@example.se',null,null)", [p12], /class_full/);
await call(host, 'select api.decide_tournament_registration($1,false)', [third.id]);
await fails(host, 'select api.decide_tournament_registration($1,true)', [third.id], /not_pending/);
await call(host, 'select api.set_tournament_registration_paid($1,true)', [first.id]);
const all = await call(host, 'select api.list_tournament_registrations($1)', [cup]);
assert.deepEqual(all.map(r => [r.class_name, r.team_name, r.status, r.paid, r.registered_by_name]), [
  ['P12', 'Demo P12', 'approved', true, 'Coach'], ['P12', 'Aneby SK', 'approved', false, 'Otto'],
  ['P12', 'Eksjö FF', 'declined', false, 'Otto'], ['Knatte', 'Aneby Knatte', 'pending', false, 'Otto']]);
const mine = (await call(coach, 'select api.get_tournament($1)', [cup])).my_registrations;
assert.deepEqual(mine.map(r => [r.team_name, r.status, r.paid, r.registered_by_name]), [['Demo P12', 'approved', true, null]]);

// A team withdraws; its place opens. Others cannot withdraw it.
await fails(other, 'select api.withdraw_tournament_registration($1)', [first.id], /not_found/);
await call(coach, 'select api.withdraw_tournament_registration($1)', [first.id]);
await fails(coach, 'select api.withdraw_tournament_registration($1)', [first.id], /not_active/);
assert.equal((await register(coach, p12, 'Demo P12')).status, 'pending', 'the name is free again');

// A class with teams stays; an empty one goes. Back to draft is refused.
await fails(host, 'select api.delete_tournament_class($1)', [p12], /has_registrations/);
const empty = await call(host, "select api.save_tournament_class($1,null,'F13',null,'pool',null,null,null,3)", [cup]);
await call(host, 'select api.delete_tournament_class($1)', [empty]);
await fails(host, "select api.update_tournament($1,'Höstcupen',null,null,'2026-11-14','2026-11-15',null,null,null,'draft',false,null)", [cup], /has_registrations/);

// Staff by link: an official, then the last organiser stays.
const token = await call(host, "select api.create_tournament_staff_invitation($1,'official')", [cup]);
assert.equal(await call(helper, 'select api.accept_tournament_staff_invitation($1)', [token]), cup);
await fails(other, 'select api.accept_tournament_staff_invitation($1)', [token], /invitation_invalid/);
assert.equal((await call(helper, 'select api.get_tournament($1)', [cup])).role, 'official');
assert.equal((await call(helper, 'select api.list_tournament_registrations($1)', [cup])).length, 5);
await fails(helper, 'select api.decide_tournament_registration($1,true)', [second.id], /not_organizer/);
assert.deepEqual((await call(host, 'select api.get_tournament($1)', [cup])).staff.map(s => [s.name, s.role]), [['Hanna', 'organizer'], ['Helga', 'official']]);
await fails(host, 'select api.remove_tournament_staff($1,$2)', [cup, host], /last_organizer/);
await call(host, 'select api.remove_tournament_staff($1,$2)', [cup, helper]);
await fails(helper, 'select api.list_tournament_registrations($1)', [cup], /not_found/);

console.log('tournament planner: ok');
