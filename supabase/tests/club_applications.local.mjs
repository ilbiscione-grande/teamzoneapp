// Applying to the club itself (2026-11-11): a member or functionary without
// a team, by search or by a club code; reviewed by the club admin; approval
// gives a club-wide assignment and, for a member, a member of the register.
// node supabase/tests/club_applications.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const club = id(10), team = id(20), admin = id(1), member = id(2), board = id(3), coder = id(4), adminP = id(41);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth; create schema audit;
create schema extensions; create schema vault;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function extensions.digest(value text, kind text) returns bytea language sql immutable as $$select convert_to(value,'UTF8')$$;
create function vault.create_secret(secret text, name text, description text) returns uuid language sql as $$select gen_random_uuid()$$;
create table auth.users(id uuid primary key, email text);
insert into auth.users values ('${member}','m@example.com'),('${board}','b@example.com'),('${coder}','c@example.com');
create table core.clubs(id uuid primary key, name text, slug text, status text default 'active', verification_status text default 'official');
insert into core.clubs values ('${club}','IF Eksjö Fotboll','eksjo','active','official');
create table core.profiles(id uuid primary key, display_name text);
insert into core.profiles values ('${admin}','Admin'),('${member}','Mia Medlem'),('${board}','Bo Styrelse'),('${coder}','Cia Kod');
create table core.teams(id uuid primary key, club_id uuid, name text, status text default 'active', unique (id, club_id));
insert into core.teams values ('${team}','${club}','A','active');
create table core.persons(id uuid primary key default gen_random_uuid(), created_by uuid);
create table core.club_people(id uuid primary key default gen_random_uuid(), club_id uuid, person_id uuid, display_name text,
  status text default 'active', birth_year smallint, created_by uuid, unique (id, club_id));
insert into core.club_people(id, club_id, display_name) values ('${adminP}','${club}','Admin');
create table core.person_account_links(club_id uuid, club_person_id uuid, profile_id uuid, state text,
  verified_at timestamptz, created_by uuid);
insert into core.person_account_links(club_id, club_person_id, profile_id, state) values ('${club}','${adminP}','${admin}','active');
create table core.assignments(id uuid primary key default gen_random_uuid(), club_id uuid, team_id uuid, club_person_id uuid,
  role_package text, state text, starts_at timestamptz, ends_at timestamptz, created_by uuid,
  constraint assignments_role_package_check check (role_package in
    ('player','leader','guardian','club_functionary','guest','referee','referee_assigner')));
insert into core.assignments(id, club_id, club_person_id, role_package, state, starts_at)
  values ('${id(51)}','${club}','${adminP}','club_functionary','active', now() - interval '1 day');
create table core.team_assignments(club_id uuid, team_id uuid, club_person_id uuid, starts_at timestamptz, created_by uuid,
  state text default 'active');
create table core.club_memberships(club_person_id uuid primary key, is_member boolean, category text);
create table core.membership_applications(id uuid primary key default gen_random_uuid(), applicant_profile_id uuid, club_id uuid,
  team_id uuid not null, requested_role text not null, status text not null default 'pending', created_at timestamptz default clock_timestamp(),
  decided_at timestamptz, decided_by uuid, withdrawn_at timestamptz, revision bigint not null default 1, approved_role text,
  constraint membership_applications_requested_role_check check (requested_role in ('player','leader','guardian','club_functionary')),
  constraint membership_applications_approved_role_check check (approved_role is null
    or approved_role in ('player','leader','guardian','club_functionary')));
create unique index membership_applications_one_pending_target
  on core.membership_applications(applicant_profile_id, team_id, requested_role) where status='pending';
create table core.team_join_codes(id uuid primary key default gen_random_uuid(), club_id uuid not null, team_id uuid not null,
  token_hash bytea not null unique, vault_secret_id uuid, requested_role text not null, state text not null default 'issued',
  expires_at timestamptz not null, max_uses integer not null default 100, use_count integer not null default 0,
  created_at timestamptz default now(), created_by uuid, revision bigint default 1,
  constraint team_join_codes_requested_role_check check (requested_role in ('player','leader','guardian','club_functionary')));
create table internal.command_deduplication(actor_profile_id uuid, idempotency_key uuid, command_type text, result jsonb);
create table audit.command_events(club_id uuid, actor_profile_id uuid, command_type text, aggregate_type text, aggregate_id uuid,
  aggregate_revision bigint, metadata jsonb);
create function internal.club_member_default_category(birth_year smallint) returns text language sql as $$select null::text$$;
create function internal.actor_has_capability(target_club_id uuid, target_team_id uuid, required_capability text)
returns boolean language sql stable as $$ select auth.uid() = '${admin}'::uuid and required_capability = 'club.memberships.manage' $$;
grant usage on schema api, internal, core, auth, audit, extensions, vault to authenticated;`);
// The live first decision step, which creates the person, link and assignment.
await db.exec(read('supabase/tests/fixtures/decide_membership_application_v1.sql'));
await db.exec(read('supabase/migrations/20270220090000_club_applications.sql'));
await db.exec(read('supabase/migrations/20270221090000_application_placement.sql'));
const rows = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  await db.exec('set role authenticated');
  try { return (await db.query(sql, params)).rows; } finally { await db.exec('reset role'); }
};
const call = async (who, sql, params = []) => Object.values((await rows(who, sql, params))[0] ?? {})[0];
const apply = (who, role) => call(who, 'select api.request_club_membership($1, $2, gen_random_uuid())', [club, role]);
const issue = (role, token) => call(admin,
  "select internal.issue_team_join_code_for_actor($1, null, $2, $3, now() + interval '30 days', 10, gen_random_uuid())",
  [club, role, token]);
const decide = (application, role) => call(admin,
  "select internal.decide_membership_application_v2($1, 'approved', $2, gen_random_uuid())", [application, role]);

// The search finds the club itself before its teams.
const found = await rows(member, "select * from internal.search_joinable_club_teams_for_actor('eksjö')");
assert.deepEqual(found.map(r => [r.club_name, r.team_name]), [['IF Eksjö Fotboll', null], ['IF Eksjö Fotboll', 'A']]);

// A member and a board member apply to the club; again is the same one.
const asMember = await apply(member, 'member');
const asBoard = await apply(board, 'club_functionary');
await assert.rejects(apply(member, 'player'), /invalid_role/);
assert.equal(await apply(member, 'member'), asMember);

// A club code: no team; member or functionary only.
const code = await issue('member', 'k'.repeat(32));
await assert.rejects(issue('player', 'p'.repeat(32)), /invalid_input/);
assert.deepEqual((await call(admin, 'select api.list_club_join_codes($1)', [club])).map(c => [c.code_id, c.requested_role]),
  [[code, 'member']]);
assert.equal(typeof await call(coder, 'select internal.claim_team_join_code_for_actor($1, gen_random_uuid())', ['k'.repeat(32)]),
  'string');

const queue = await rows(admin, 'select * from internal.list_pending_membership_applications_for_actor($1)', [club]);
assert.deepEqual(queue.map(r => [r.applicant_display_name, r.team_name, r.requested_role, r.source]), [
  ['Mia Medlem', '', 'member', 'search'],
  ['Bo Styrelse', '', 'club_functionary', 'search'],
  ['Cia Kod', '', 'member', 'team_code'],
]);

// A club application cannot become a team role.
await assert.rejects(decide(asMember, 'player'), /invalid_role/);
await decide(asMember, null);
await decide(asBoard, null);
const assignments = (await db.query(`select p.display_name, a.role_package, a.team_id from core.assignments a
  join core.club_people p on p.id = a.club_person_id where p.display_name <> 'Admin' order by p.display_name`)).rows;
assert.deepEqual(assignments.map(a => [a.display_name, a.role_package, a.team_id]),
  [['Bo Styrelse', 'club_functionary', null], ['Mia Medlem', 'member', null]]);

// The member counts as a member; a member is never tied to a team.
const mia = (await db.query("select id from core.club_people where display_name = 'Mia Medlem'")).rows[0].id;
assert.equal((await db.query('select internal.club_person_is_default_member($1, $2) m', [club, mia])).rows[0].m, true);
await assert.rejects(db.exec(`insert into core.assignments(club_id, team_id, club_person_id, role_package, state, starts_at)
  values ('${club}','${team}','${mia}','member','active',now())`), /assignments_member_club_wide/);
await assert.rejects(db.exec(`insert into core.membership_applications(applicant_profile_id, club_id, team_id, requested_role)
  values ('${coder}','${club}','${team}','member')`), /membership_applications_scope_check/);
const mine = await rows(coder, 'select * from internal.list_my_membership_applications_for_actor()');
assert.deepEqual(mine.map(r => [r.club_name, r.team_name, r.requested_role, r.status]),
  [['IF Eksjö Fotboll', '', 'member', 'pending']]);

// Placing on approval: the club member by code becomes a leader in team A.
assert.deepEqual(await call(admin, 'select api.list_club_teams_for_review($1)', [club]), [{ team_id: team, name: 'A' }]);
const ciaApp = mine[0].application_id;
const place = (who, role, teamId, toClub) => call(who,
  "select internal.decide_membership_application_v3($1, 'approved', $2, $3, $4, gen_random_uuid())",
  [ciaApp, role, teamId, toClub]);
await assert.rejects(place(admin, 'member', team, false), /invalid_role/);
await assert.rejects(place(coder, 'leader', team, false), /not_found/);
assert.equal(await place(admin, 'leader', team, false), 'approved');
const cia = (await db.query(`select a.role_package, a.team_id from core.assignments a
  join core.club_people p on p.id = a.club_person_id where p.display_name = 'Cia Kod'`)).rows;
assert.deepEqual(cia.map(a => [a.role_package, a.team_id]), [['leader', team]]);
const placed = (await db.query('select * from core.membership_applications where id = $1', [ciaApp])).rows[0];
assert.deepEqual([placed.status, placed.team_id, placed.requested_role, placed.approved_team_id, placed.approved_role],
  ['approved', null, 'member', team, 'leader']);
assert.equal((await db.query("select count(*)::int n from audit.command_events where command_type = 'membership.application.placed.v1'"))
  .rows[0].n, 1);
assert.doesNotMatch(read('supabase/migrations/20270220090000_club_applications.sql'), /serialization_failure/);
assert.doesNotMatch(read('supabase/migrations/20270221090000_application_placement.sql'), /serialization_failure/);
console.log('club applications: ok');
