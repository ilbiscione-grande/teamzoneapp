// Medlemsregister (2026-11-10): everyone active in the club with teams,
// roles and guardians; players, leaders and functionaries are members by
// default, guardians only when set; categories follow the birth year.
// node supabase/tests/club_member_register.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const club = id(10), other = id(11), team = id(20);
const [admin, coach] = [id(1), id(2)];
const [adminP, coachP, kidP, parentP, endedP, otherP] = [id(41), id(42), id(43), id(44), id(45), id(46)];
const year = new Date().getFullYear();
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth; create schema audit;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key);
insert into core.clubs values ('${club}'),('${other}');
create table core.profiles(id uuid primary key);
insert into core.profiles values ('${admin}'),('${coach}');
create table core.club_people(id uuid primary key, club_id uuid, display_name text, status text default 'active', birth_year smallint, contact_email text, phone text, safeguarding_required boolean default false, revision bigint default 1,
  unique (id, club_id));
insert into core.club_people values
  ('${adminP}','${club}','Admin Adminsson','active',null),
  ('${coachP}','${club}','Tränaren','active',${year - 40}),
  ('${kidP}','${club}','Barnet','active',${year - 12}),
  ('${parentP}','${club}','Föräldern','active',${year - 42}),
  ('${endedP}','${club}','Slutat','ended',null),
  ('${otherP}','${other}','Annan klubb','active',null);
create table core.teams(id uuid primary key, club_id uuid, name text);
insert into core.teams values ('${team}','${club}','P2014');
create table core.person_account_links(club_id uuid, club_person_id uuid, profile_id uuid, state text);
insert into core.person_account_links values ('${club}','${adminP}','${admin}','active'),('${club}','${coachP}','${coach}','active');
create table core.assignments(id uuid primary key default gen_random_uuid(), club_id uuid, club_person_id uuid, team_id uuid,
  role_package text, state text, starts_at timestamptz, ends_at timestamptz);
insert into core.assignments(id, club_id, club_person_id, team_id, role_package, state, starts_at) values
  ('${id(51)}','${club}','${adminP}',null,'club_functionary','active', now() - interval '1 day'),
  ('${id(52)}','${club}','${coachP}','${team}','leader','active', now() - interval '1 day'),
  ('${id(53)}','${club}','${parentP}','${team}','guardian','active', now() - interval '1 day');
create table core.team_assignments(club_id uuid, team_id uuid, club_person_id uuid, state text);
insert into core.team_assignments values ('${club}','${team}','${kidP}','active');
create table core.guardian_relations(club_id uuid, guardian_person_id uuid, child_person_id uuid, state text, ends_at timestamptz);
insert into core.guardian_relations values ('${club}','${parentP}','${kidP}','active',null);
create table core.capability_grants(club_id uuid, assignment_id uuid, capability text, scope_type text, scope_id uuid,
  starts_at timestamptz, ends_at timestamptz);
insert into core.capability_grants values ('${club}','${id(51)}','club.memberships.manage','club','${club}', now() - interval '1 day', null);
create table internal.command_deduplication(actor_profile_id uuid, idempotency_key uuid, command_type text, result jsonb);
create table audit.command_events(club_id uuid, actor_profile_id uuid, command_type text, aggregate_type text, aggregate_id uuid,
  aggregate_revision bigint, metadata jsonb);
grant usage on schema api, internal, core, auth, audit to authenticated;`);
await db.exec(`create function internal.actor_has_capability(target_club_id uuid, target_team_id uuid, required_capability text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from core.person_account_links link
    join core.assignments assignment on assignment.club_person_id = link.club_person_id and assignment.club_id = link.club_id
    join core.capability_grants grant_row on grant_row.assignment_id = assignment.id and grant_row.club_id = assignment.club_id
    where link.profile_id = auth.uid() and link.state = 'active' and assignment.state = 'active'
      and assignment.club_id = target_club_id and grant_row.capability = required_capability
      and grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id) $$;`);
await db.exec(read('supabase/migrations/20270215090000_club_member_register.sql'));
await db.exec(`create function internal.normalized_contact(new_email text, new_phone text) returns jsonb language plpgsql immutable set search_path to '' as $$
declare email text:=nullif(lower(btrim(coalesce(new_email,''))),''); phone text:=nullif(btrim(coalesce(new_phone,'')),'');
begin
 if email is not null and (length(email)>254 or email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') then raise invalid_parameter_value using message='invalid_email'; end if;
 return jsonb_build_object('email',email,'phone',phone);
end$$;`);
const call = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  await db.exec('set role authenticated');
  try { return Object.values((await db.query(sql, params)).rows[0] ?? {})[0]; } finally { await db.exec('reset role'); }
};
const register = async () => (await call(admin, 'select api.get_club_member_register($1)', [club])).people;
const set = (person, member, category, revision) => call(admin,
  'select api.set_club_membership($1, $2, $3, $4, $5, gen_random_uuid())', [club, person, member, category, revision]);

// Everyone active in the club, not the ended one or another club's.
let people = await register();
assert.deepEqual(people.map(p => p.name), ['Admin Adminsson', 'Barnet', 'Föräldern', 'Tränaren']);
const byName = name => people.find(p => p.name === name);
assert.deepEqual(
  people.map(p => [p.name, p.is_member, p.category]),
  [['Admin Adminsson', true, null], ['Barnet', true, 'youth'], ['Föräldern', false, 'adult'], ['Tränaren', true, 'adult']]);
assert.deepEqual(byName('Barnet').teams, [{ team_id: team, name: 'P2014', role: 'player' }]);
assert.deepEqual(byName('Barnet').guardians, ['Föräldern']);
assert.deepEqual(byName('Föräldern').children, ['Barnet']);
assert.equal(byName('Admin Adminsson').club_role, true);
assert.equal(byName('Tränaren').has_account, true);
assert.equal(byName('Barnet').has_account, false);

// The parent becomes a supporting member; the coach is no longer one.
await set(parentP, true, 'supporter', 0);
await set(coachP, false, null, 0);
people = await register();
assert.deepEqual([byName('Föräldern').is_member, byName('Föräldern').category, byName('Föräldern').category_set], [true, 'supporter', true]);
assert.deepEqual([byName('Tränaren').is_member, byName('Tränaren').member_set, byName('Tränaren').category], [false, true, 'adult']);
// A stale view gets PT409, never 40001; unknown categories and people are refused.
await assert.rejects(set(parentP, false, null, 0), e => e.code === 'PT409' && /stale_revision/.test(e.message));
await assert.rejects(set(parentP, true, 'gold', 1), /invalid_membership/);
await assert.rejects(set(otherP, true, null, 0), /not_found/);
await assert.rejects(set(endedP, true, null, 0), /not_found/);
// Without members and teams: nothing to see or change.
await assert.rejects(call(coach, 'select api.get_club_member_register($1)', [club]), /not_found/);
await assert.rejects(call(coach, 'select api.set_club_membership($1,$2,true,null,1,gen_random_uuid())', [club, parentP]), /not_found/);
assert.equal((await db.query("select count(*)::int n from audit.command_events where command_type = 'club.membership.updated.v1'")).rows[0].n, 2);

// The address fee reminders go to: only for someone without an account.
await db.exec(read('supabase/migrations/20270223090000_register_fee_email.sql'));
const setEmail = (person, email) => call(admin, 'select api.set_club_person_email($1, $2, $3)', [club, person, email]);
assert.deepEqual(await setEmail(parentP, ' Foralder@Example.com '), { email: 'foralder@example.com' });
people = await register();
assert.deepEqual([byName('Föräldern').email, byName('Föräldern').email_editable], ['foralder@example.com', true]);
assert.deepEqual([byName('Tränaren').email, byName('Tränaren').email_editable], [null, false]);
await assert.rejects(setEmail(coachP, 'coach@example.com'), /not_found/);
await assert.rejects(setEmail(parentP, 'inte en adress'), /invalid_email/);
await assert.rejects(call(coach, 'select api.set_club_person_email($1, $2, $3)', [club, parentP, 'x@example.com']), /not_found/);
assert.deepEqual(await setEmail(parentP, ''), { email: null });
assert.doesNotMatch(read('supabase/migrations/20270215090000_club_member_register.sql'), /serialization_failure/);
// Roles in the person card (2026-11-11): the club admin gives and takes back
// the club-wide roles; a functionary's areas end with the role.
await db.exec(`alter table core.assignments add column revision bigint default 1, add column created_by uuid;
alter table core.capability_grants add column revision bigint default 1;
create function internal.actor_owns_club_person(target_club_id uuid, target_club_person_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$ select exists (select 1 from core.person_account_links l
  where l.club_id = target_club_id and l.club_person_id = target_club_person_id and l.profile_id = auth.uid() and l.state = 'active') $$;
create function internal.club_has_memberships_manager(target_club_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$ select exists (select 1 from core.capability_grants g
  join core.assignments a on a.id = g.assignment_id and a.state = 'active'
  where g.club_id = target_club_id and g.capability = 'club.memberships.manage'
    and (g.ends_at is null or g.ends_at > now())) $$;`);
await db.exec(read('supabase/migrations/20270225090000_club_roles.sql'));
const role = (who, person, r, on) => call(who, 'select api.set_club_role($1, $2, $3, $4, gen_random_uuid())', [club, person, r, on]);
people = await register();
assert.deepEqual([byName('Admin Adminsson').club_roles, byName('Admin Adminsson').is_self], [['club_functionary'], true]);
assert.deepEqual([byName('Tränaren').club_roles, byName('Tränaren').is_self], [[], false]);
// The coach becomes a functionary and gets members and teams there.
assert.deepEqual(await role(admin, coachP, 'club_functionary', true), { person_id: coachP, role: 'club_functionary', active: true });
await role(admin, coachP, 'club_functionary', true);
await role(admin, parentP, 'member', true);
people = await register();
assert.deepEqual([byName('Tränaren').club_roles, byName('Tränaren').club_role], [['club_functionary'], true]);
assert.deepEqual(byName('Föräldern').club_roles, ['member']);
assert.equal((await db.query("select count(*)::int n from core.assignments where club_person_id = $1 and team_id is null", [coachP])).rows[0].n, 1);
const coachRole = (await db.query("select id from core.assignments where club_person_id = $1 and team_id is null", [coachP])).rows[0].id;
await db.query("insert into core.capability_grants values ($1, $2, 'club.memberships.manage', 'club', $1, now() - interval '1 second', null)", [club, coachRole]);
// Not your own functionary role, nor the last one with members and teams.
await assert.rejects(role(admin, adminP, 'club_functionary', false), /own_club_role/);
await assert.rejects(role(admin, kidP, 'player', true), /invalid_role/);
await role(admin, parentP, 'member', false);
await role(admin, coachP, 'club_functionary', false);
people = await register();
assert.deepEqual([byName('Tränaren').club_roles, byName('Föräldern').club_roles], [[], []]);
assert.equal((await db.query("select count(*)::int n from core.capability_grants where assignment_id = $1 and ends_at is not null", [coachRole])).rows[0].n, 1);
// A functionary with members and teams again: not their own role, but the admin's.
await role(admin, coachP, 'club_functionary', true);
const coachRole2 = (await db.query("select id from core.assignments where club_person_id = $1 and team_id is null and state = 'active'", [coachP])).rows[0].id;
await db.query("insert into core.capability_grants values ($1, $2, 'club.memberships.manage', 'club', $1, now() - interval '1 second', null)", [club, coachRole2]);
await assert.rejects(role(coach, coachP, 'club_functionary', false), /own_club_role/);
await role(coach, adminP, 'club_functionary', false);
await assert.rejects(call(admin, 'select api.get_club_member_register($1)', [club]), /not_found/);
assert.equal((await db.query("select count(*)::int n from audit.command_events where command_type = 'club.role.set.v1'")).rows[0].n, 7);
assert.doesNotMatch(read('supabase/migrations/20270225090000_club_roles.sql'), /serialization_failure/);
console.log('club member register: ok');
