// The club functionary's Home and recipient names (UX review 2026-10-20),
// in isolated Postgres with a reduced schema.
// node supabase/tests/club_home_and_recipient_names.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const chair = id(1), coach = id(2), player = id(3);
const club = id(10), team = id(20), team2 = id(21), clubCtx = id(30), teamCtx = id(31);
const pChair = id(51), pCoach = id(52), pPlayer = id(53);
const aChair = id(61), aCoach = id(62), aPlayer = id(63);
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
const user = (who, sql, params = []) => as(who).then(() => asRole('authenticated', () => db.query(sql, params))).then(r => r.rows);
await db.exec(`create role anon;create role authenticated;
create schema internal;create schema api;create schema core;create schema auth;
set check_function_bodies = off;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.profiles(id uuid primary key,display_name text);
insert into core.profiles values('${chair}',''),('${coach}','Coach Konto'),('${player}',null);
create table core.teams(id uuid primary key,club_id uuid,name text,status text default 'active');
insert into core.teams values('${team}','${club}','P2012'),('${team2}','${club}','F2013');
create table core.club_people(id uuid primary key,club_id uuid,display_name text);
insert into core.club_people values('${pChair}','${club}','Benjamin'),('${pCoach}','${club}','Lena'),('${pPlayer}','${club}','Anna');
create table core.person_account_links(profile_id uuid,club_id uuid,club_person_id uuid,state text);
insert into core.person_account_links values('${chair}','${club}','${pChair}','active'),('${coach}','${club}','${pCoach}','active'),('${player}','${club}','${pPlayer}','active');
create table core.assignments(id uuid primary key,club_id uuid,team_id uuid,club_person_id uuid,role_package text,state text default 'active',
 starts_at timestamptz default now()-interval '1 year',ends_at timestamptz);
insert into core.assignments values('${aChair}','${club}',null,'${pChair}','club_functionary'),
 ('${aCoach}','${club}','${team}','${pCoach}','leader'),('${aPlayer}','${club}','${team}','${pPlayer}','player'),
 ('${id(64)}','${club}','${team2}','${pPlayer}','player');
create table core.board_mandates(club_id uuid,assignment_id uuid,office text,state text,starts_at timestamptz,ends_at timestamptz);
insert into core.board_mandates values('${club}','${aChair}','chair','active',now()-interval '1 month',now()+interval '1 year');
create table core.board_mandate_changes(club_id uuid,state text);insert into core.board_mandate_changes values('${club}','pending');
create table core.economy_accounts(club_id uuid,state text);
create table core.economy_ledger_entries(club_id uuid,state text);
create table core.membership_applications(club_id uuid,status text);insert into core.membership_applications values('${club}','pending');
create table core.team_creation_requests(club_id uuid,state text);
create table core.event_locations(id uuid primary key,name text);insert into core.event_locations values('${id(70)}','Demovallen');
create table core.events(id uuid primary key,club_id uuid,title text,event_type text,state text,starts_at timestamptz,ends_at timestamptz,
 all_day boolean default false,archived_at timestamptz,location_id uuid);
insert into core.events values('${id(80)}','${club}','Träning','training','scheduled',now()+interval '1 day',now()+interval '1 day 1 hour',false,null,'${id(70)}'),
 ('${id(81)}','${club}','Gammal','training','scheduled',now()-interval '2 day',now()-interval '2 day'+interval '1 hour',false,null,null),
 ('${id(82)}','${club}','Utkast','match','draft',now()+interval '2 day',now()+interval '2 day 1 hour',false,null,null);
create table core.event_teams(event_id uuid,club_id uuid,team_id uuid);
insert into core.event_teams values('${id(80)}','${club}','${team}'),('${id(81)}','${club}','${team}'),('${id(82)}','${club}','${team}');
create table core.contact_controls(control_type text,state text,requester_profile_id uuid,target_profile_id uuid);
create function internal.get_my_contexts_for_actor() returns table(context_id uuid,club_id uuid,team_id uuid) language sql stable as $$
 select '${clubCtx}'::uuid,'${club}'::uuid,null::uuid where auth.uid()='${chair}'::uuid
 union all select '${teamCtx}'::uuid,'${club}'::uuid,'${team}'::uuid where auth.uid()='${coach}'::uuid$$;
create function internal.actor_has_capability(c uuid,t uuid,cap text) returns boolean language sql stable as
 $$select auth.uid()='${chair}'::uuid and cap in ('board.read','club.messaging.manage')$$;
-- Everyone may message everyone here; the predicate is tested elsewhere.
create function internal.messaging_relationship_allowed(a uuid,t uuid,c uuid,tm uuid) returns boolean language sql stable as $$select a<>t$$;
grant usage on schema api, internal, core to authenticated;`);
await db.exec(read('supabase/migrations/20261114090000_club_home_and_recipient_names.sql'));
await db.exec('grant execute on all functions in schema api, internal to authenticated');

const [{ home }] = await user(chair, 'select api.get_club_home($1) home', [clubCtx]);
assert.equal(home.own_name, 'Benjamin');
assert.deepEqual(home.own_offices, ['chair']);
assert.deepEqual(home.board, { active_mandates: 1, pending_changes: 1 });
assert.equal(home.economy, null, 'economy only with economy.read');
assert.equal(home.members, null, 'applications only for club admins');
assert.equal(home.can_announce, true);
assert.deepEqual(home.teams.map(t => t.name), ['F2013', 'P2012']);
const p2012 = home.teams.find(t => t.name === 'P2012');
assert.equal(p2012.member_count, 2);
assert.deepEqual(p2012.upcoming.map(e => e.title), ['Träning'], 'scheduled, coming events only');
assert.equal(p2012.upcoming[0].location_name, 'Demovallen');

await assert.rejects(user(coach, 'select api.get_club_home($1)', [teamCtx]), /not_found/, 'a team context has no club home');
await assert.rejects(user(coach, 'select api.get_club_home($1)', [clubCtx]), /not_found/, 'not your context');

const rows = await user(chair, 'select * from api.resolve_allowed_recipients($1)', [clubCtx]);
const byId = Object.fromEntries(rows.map(r => [r.profile_id, r]));
assert.equal(byId[coach].display_name, 'Coach Konto', "the account's name first");
assert.equal(byId[player].display_name, 'Anna', "else the person's name in the club");
assert.equal(byId[player].team_names, 'F2013, P2012', 'one row with both teams');
assert.equal(byId[coach].team_names, 'P2012');
assert.equal(byId[chair], undefined, 'not yourself');
const search = await user(chair, 'select * from api.resolve_allowed_recipients($1,$2)', [clubCtx, 'ann']);
assert.deepEqual(search.map(r => r.display_name), ['Anna'], "search matches the person's name");
console.log('club home and recipient names: ok');
