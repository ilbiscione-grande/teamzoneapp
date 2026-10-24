// Club permissions (2026-10-24): the club's administrators give the club's
// areas to functionaries, only what they hold, never leaving the club
// without members and teams. node supabase/tests/club_permissions.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const club = id(10), [admin, chair, coach] = [id(1), id(2), id(3)];
const [adminPerson, chairPerson, coachPerson] = [id(41), id(42), id(43)];
const [adminRole, chairRole, coachRole] = [id(51), id(52), id(53)];
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth; create schema audit;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.club_people(id uuid primary key, club_id uuid, display_name text, status text default 'active');
insert into core.club_people values ('${adminPerson}','${club}','Thomas','active'),('${chairPerson}','${club}','Ordföranden','active'),('${coachPerson}','${club}','Tränaren','active');
create table core.person_account_links(club_id uuid, club_person_id uuid, profile_id uuid, state text);
insert into core.person_account_links values ('${club}','${adminPerson}','${admin}','active'),('${club}','${chairPerson}','${chair}','active'),('${club}','${coachPerson}','${coach}','active');
create table core.assignments(id uuid primary key, club_id uuid, club_person_id uuid, team_id uuid, role_package text, state text,
  starts_at timestamptz, ends_at timestamptz);
insert into core.assignments values
  ('${adminRole}','${club}','${adminPerson}',null,'club_functionary','active', now() - interval '1 day', null),
  ('${chairRole}','${club}','${chairPerson}',null,'club_functionary','active', now() - interval '1 day', null),
  ('${coachRole}','${club}','${coachPerson}','${id(20)}','leader','active', now() - interval '1 day', null);
create table core.capability_grants(id uuid primary key default gen_random_uuid(), club_id uuid, assignment_id uuid, capability text,
  scope_type text, scope_id uuid, starts_at timestamptz, ends_at timestamptz, created_by uuid, revision bigint default 1,
  unique (assignment_id, capability, scope_type, scope_id));
insert into core.capability_grants(club_id, assignment_id, capability, scope_type, scope_id, starts_at) values
  ('${club}','${adminRole}','club.memberships.manage','club','${club}', now() - interval '1 day'),
  ('${club}','${adminRole}','publication.manage','club','${club}', now() - interval '1 day'),
  ('${club}','${adminRole}','club.messaging.manage','club','${club}', now() - interval '1 day');
create table internal.command_deduplication(actor_profile_id uuid, idempotency_key uuid, command_type text, result jsonb);
create table audit.command_events(club_id uuid, actor_profile_id uuid, command_type text, aggregate_type text, aggregate_id uuid,
  aggregate_revision bigint, metadata jsonb);
create function internal.actor_owns_club_person(c uuid, p uuid) returns boolean language sql stable as $$
  select exists(select 1 from core.person_account_links where club_id = c and club_person_id = p and profile_id = auth.uid()) $$;
grant usage on schema api, internal, core, auth, audit to authenticated;`);
// The real capability check, as the database has it.
await db.exec(`create function internal.actor_has_capability(target_club_id uuid, target_team_id uuid, required_capability text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from core.person_account_links link
    join core.assignments assignment on assignment.club_person_id = link.club_person_id and assignment.club_id = link.club_id
    join core.capability_grants grant_row on grant_row.assignment_id = assignment.id and grant_row.club_id = assignment.club_id
    where link.profile_id = auth.uid() and link.state = 'active' and assignment.state = 'active'
      and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
      and assignment.club_id = target_club_id and grant_row.capability = required_capability
      and grant_row.starts_at <= now() and (grant_row.ends_at is null or grant_row.ends_at > now())
      and ((grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id)
        or (grant_row.scope_type = 'team' and grant_row.scope_id = target_team_id))) $$;`);
await db.exec(read('supabase/migrations/20261208090000_club_permissions.sql'));
const call = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  await db.exec('set role authenticated');
  try { return Object.values((await db.query(sql, params)).rows[0] ?? {})[0]; } finally { await db.exec('reset role'); }
};
const fails = async (who, sql, params, pattern) => {
  await assert.rejects(call(who, sql, params), pattern);
};
const set = (who, person, wanted, expected) => call(who,
  'select api.set_club_permissions($1, $2, $3::text[], $4::text[], gen_random_uuid())', [club, person, wanted, expected]);
const canChair = async cap => call(chair, 'select internal.actor_has_capability($1, null, $2)', [club, cap]);

// Thomas sees the functionaries (not the coach) and may give what he holds.
const view = await call(admin, 'select api.get_club_permissions($1)', [club]);
assert.deepEqual(view.grantable, ['publication.manage', 'club.memberships.manage', 'club.messaging.manage']);
assert.deepEqual(view.people.map(p => [p.name, p.capabilities, p.is_self]),
  [['Ordföranden', [], false], ['Thomas', ['club.memberships.manage', 'club.messaging.manage', 'publication.manage'], true]]);
await fails(chair, 'select api.get_club_permissions($1)', [club], /not_found/);

// The chair gets publication: she may now decide team pages.
assert.equal(await canChair('publication.manage'), false);
await set(admin, chairPerson, ['publication.manage'], []);
assert.equal(await canChair('publication.manage'), true);
// Not what Thomas lacks; not with a stale view; not to a team leader.
await fails(admin, 'select api.set_club_permissions($1, $2, $3::text[], $4::text[], gen_random_uuid())',
  [club, chairPerson, ['publication.manage', 'club.referees.manage'], ['publication.manage']], /not_grantable/);
await fails(admin, 'select api.set_club_permissions($1, $2, $3::text[], $4::text[], gen_random_uuid())',
  [club, chairPerson, [], []], /stale_permissions/);
await fails(admin, 'select api.set_club_permissions($1, $2, $3::text[], $4::text[], gen_random_uuid())',
  [club, coachPerson, ['publication.manage'], []], /not_found/);
await fails(admin, 'select api.set_club_permissions($1, $2, $3::text[], $4::text[], gen_random_uuid())',
  [club, chairPerson, ['board.manage'], ['publication.manage']], /invalid_permissions/);

// Thomas cannot leave the club without members and teams; with the chair holding it, he can.
await fails(admin, 'select api.set_club_permissions($1, $2, $3::text[], $4::text[], gen_random_uuid())',
  [club, adminPerson, ['publication.manage'], ['club.memberships.manage', 'club.messaging.manage', 'publication.manage']], /last_memberships_manager/);
await set(admin, chairPerson, ['club.memberships.manage', 'publication.manage'], ['publication.manage']);
await set(admin, adminPerson, ['publication.manage'], ['club.memberships.manage', 'club.messaging.manage', 'publication.manage']);
assert.equal(await call(admin, 'select internal.actor_has_capability($1, null, $2)', [club, 'club.memberships.manage']), false);
// Taken back from the chair: it ends; given again, it starts again.
await set(chair, chairPerson, ['club.memberships.manage'], ['club.memberships.manage', 'publication.manage']);
assert.equal(await canChair('publication.manage'), false);
const ended = (await db.query("select count(*)::int n from core.capability_grants where capability = 'publication.manage' and ends_at is not null")).rows[0].n;
assert.equal(ended >= 1, true, 'taken back is ended, not deleted');
assert.equal((await db.query("select count(*)::int n from audit.command_events where command_type = 'club.permissions.updated.v1'")).rows[0].n, 4);
console.log('club permissions: ok');
