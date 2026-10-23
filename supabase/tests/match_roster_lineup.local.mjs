// The match squad takes the event's line-up (2026-10-23): without callups or
// attendance the frozen squad was empty and no player could be chosen.
// node supabase/tests/match_roster_lineup.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const club = id(10), match = id(30), [a, b, c, d] = [id(41), id(42), id(43), id(44)], stranger = id(49);
await db.exec(`create schema internal; create schema core; create schema audit; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select null::uuid$$;
create table core.events(id uuid primary key, club_id uuid);
insert into core.events values ('${match}','${club}');
create table core.club_people(id uuid primary key, club_id uuid, display_name text, person_id uuid);
insert into core.club_people values ('${a}','${club}','A',null),('${b}','${club}','B',null),('${c}','${club}','C',null),('${d}','${club}','D',null),('${stranger}',gen_random_uuid(),'X',null);
create table core.callups(id uuid primary key, event_id uuid, club_person_id uuid, club_id uuid, state text, squad_revision_id uuid, sent_at timestamptz);
create table core.attendance_facts(event_id uuid, club_person_id uuid, club_id uuid, status text);
create table core.event_lineups(event_id uuid primary key, starters jsonb not null default '[]', substitutes jsonb not null default '[]');
create table core.match_roster_revisions(id uuid primary key, event_id uuid, revision bigint, reason_code text, source_squad_revision_id uuid, created_by uuid, state text default 'frozen');
create table core.match_roster_members(roster_revision_id uuid, club_person_id uuid, club_id uuid, source_callup_id uuid, source_state text,
  primary key(roster_revision_id, club_person_id), constraint match_roster_members_source_state_check check(source_state in ('accepted','leader_added')));
create table core.match_workspaces(event_id uuid primary key, roster_revision bigint, revision bigint default 0, updated_at timestamptz, updated_by uuid);
insert into core.match_workspaces values ('${match}', 0, 0, now(), null);
create table audit.match_commands(command_id uuid primary key, result jsonb);
create function internal.register_match_command(c uuid, e uuid, r bigint, t text, p jsonb) returns boolean language plpgsql as $$
begin insert into audit.match_commands values (c, null) on conflict do nothing; return found; end $$;
create function internal.recompute_match_projection(e uuid) returns void language sql as $$ select $$;`);
await db.exec(read('supabase/migrations/20261205090000_match_roster_lineup.sql'));
const freeze = async (reason) => (await db.query(
  'select internal.freeze_match_roster_for_actor(gen_random_uuid(), $1, $2) v', [match, reason])).rows[0].v;
const members = async () => (await db.query(`select club_person_id id, source_state s from core.match_roster_members m
  join core.match_roster_revisions r on r.id = m.roster_revision_id where r.state = 'frozen' order by 1`)).rows.map(r => [r.id, r.s]);

// No callups, no attendance, no line-up: an empty squad, as before.
assert.equal((await freeze('initial')).member_count, 0);
// The line-up set afterwards: updating the squad brings its players, not someone from another club.
await db.query("insert into core.event_lineups values ($1, $2::jsonb, $3::jsonb)",
  [match, JSON.stringify([{ person_id: a }, { person_id: b }, { person_id: stranger }]), JSON.stringify([{ person_id: c }])]);
assert.equal((await freeze('manual_correction')).member_count, 3);
assert.deepEqual(await members(), [[a, 'lineup'], [b, 'lineup'], [c, 'lineup']]);
// An accepted callup and attendance keep their own source; the line-up adds only who is missing.
await db.query("insert into core.callups values (gen_random_uuid(), $1, $2, $3, 'accepted', null, now())", [match, a, club]);
await db.query("insert into core.attendance_facts values ($1, $2, $3, 'present')", [match, d, club]);
assert.equal((await freeze('late_callup')).member_count, 4);
assert.deepEqual(await members(), [[a, 'accepted'], [b, 'lineup'], [c, 'lineup'], [d, 'leader_added']]);
console.log('match roster lineup: ok');
