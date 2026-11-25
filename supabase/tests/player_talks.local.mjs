// Spelarsamtal (2026-11-25): a team's leaders with Säsongsplanering write
// down talks with a player; never shown to the player.
// node supabase/tests/player_talks.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), adaLogin = id(2), viewer = id(3), coach2 = id(4), club = id(10), team = id(20), other = id(21);
const [ada, bo, coachPerson, cia, coach2Person] = [id(50), id(51), id(52), id(53), id(54)];
await db.exec(`create role anon; create role authenticated; create role service_role;
create schema internal; create schema api; create schema core; create schema auth; create schema audit;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key, name text);
create table core.teams(id uuid primary key, club_id uuid, name text, status text default 'active');
insert into core.teams values ('${team}','${club}','P2012'),('${other}','${club}','F2013');
create table core.club_people(id uuid primary key, club_id uuid, display_name text, status text default 'active',
  phone text, contact_email text, provenance text default 'manual');
insert into core.club_people(id,club_id,display_name) values ('${ada}','${club}','Ada'),('${bo}','${club}','Bo'),
 ('${coachPerson}','${club}','Coach'),('${cia}','${club}','Cia'),('${coach2Person}','${club}','Dan');
create table core.profiles(id uuid primary key, phone text, contact_email text);
create table core.assignments(id uuid primary key default gen_random_uuid(), club_id uuid, team_id uuid, club_person_id uuid,
  role_package text, state text, starts_at timestamptz default now() - interval '1 day', ends_at timestamptz);
insert into core.assignments(club_id, team_id, club_person_id, role_package, state) values
  ('${club}','${team}','${ada}','player','active'),('${club}','${team}','${bo}','player','active'),
  ('${club}','${team}','${coachPerson}','leader','active'),('${club}','${team}','${coach2Person}','leader','active'),
  ('${club}','${other}','${cia}','player','active');
create table core.person_account_links(club_person_id uuid, profile_id uuid, state text, created_at timestamptz default now());
insert into core.person_account_links values ('${ada}','${adaLogin}','active'),('${coachPerson}','${coach}','active');
create table audit.command_events(club_id uuid, actor_profile_id uuid, command_type text, aggregate_type text,
  aggregate_id uuid, aggregate_revision int, metadata jsonb);
create function internal.actor_owns_club_person(c uuid, p uuid) returns boolean language sql stable security definer as $$
  select exists(select 1 from core.person_account_links l where l.club_person_id = p and l.profile_id = auth.uid() and l.state = 'active') $$;
create function internal.actor_leads_team(c uuid, t uuid) returns boolean language sql stable as $$ select true $$;
-- Ada's login also leads here, to check that a leader never reads a talk about oneself.
create function internal.tdp_team_club(t uuid) returns uuid language plpgsql stable as $$
begin
  if auth.uid() is null or auth.uid() not in ('${coach}','${coach2}','${viewer}','${adaLogin}') or t <> '${team}' then
    raise insufficient_privilege using message = 'not_found'; end if;
  return '${club}';
end$$;
create function internal.tdp_can_edit(c uuid) returns boolean language sql stable as $$ select auth.uid() <> '${viewer}'::uuid $$;
grant usage on schema api, internal, core, auth, audit to authenticated, service_role;`);
await db.exec(read('supabase/migrations/20270417090000_team_surveys.sql'));
await db.exec(read('supabase/migrations/20270418090002_team_survey_sharing.sql'));
await db.exec(read('supabase/migrations/20270425090000_player_talks.sql'));
await db.exec('begin');

const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0]?.v;
const asOwner = async sql => { await db.exec('reset role'); try { return (await db.query(sql)).rows; } finally { await db.exec('set role authenticated'); } };
const rejects = async (fn, message, code) => {
  await db.exec('savepoint r');
  try { await assert.rejects(fn, e => e.message === message && (!code || e.code === code), message); } finally { await db.exec('rollback to r'); }
};
const talk1 = id(100);
const list = (person = ada, t = team) => one('select api.list_player_talks($1,$2) v', [t, person]);
const save = (over = {}) => {
  const v = { team, person: ada, talk: talk1, revision: null, on: '2026-11-25', leaders: [coachPerson], response: null, notes: '', agreed: '', ...over };
  return one('select api.save_player_talk($1,$2,$3,$4,$5,$6::uuid[],$7,$8,$9) v',
    [v.team, v.person, v.talk, v.revision, v.on, v.leaders, v.response, v.notes, v.agreed]);
};
const adaResponse = id(200), boResponse = id(201);
await db.exec(`insert into core.team_surveys(id,club_id,team_id,title,state) values ('${id(30)}','${club}','${team}','Inför spelarsamtal','open');
insert into core.team_survey_invites(id,survey_id,club_person_id) values ('${id(40)}','${id(30)}','${ada}'),('${id(41)}','${id(30)}','${bo}');
insert into core.team_survey_responses(id,survey_id,invite_id,club_person_id,answers) values
 ('${adaResponse}','${id(30)}','${id(40)}','${ada}','{}'),('${boResponse}','${id(30)}','${id(41)}','${bo}','{}');`);

await db.exec('set role authenticated');
await as(coach);
let data = await list();
assert.equal(data.name, 'Ada');
assert.equal(data.can_edit, true);
assert.equal(data.is_player, true);
assert.deepEqual(data.leaders.map(l => [l.name, l.self]), [['Coach', true], ['Dan', false]]);
assert.deepEqual(data.talks, []);

// Writing.
let saved = await save({ notes: 'Vill spela mer centralt', response: adaResponse });
assert.equal(saved.revision, 1);
saved = await save({ notes: 'Vill spela mer centralt.', response: adaResponse });
assert.equal(saved.revision, 2, 'a create sent again updates its own talk');
assert.equal((await list()).talks.length, 1, 'and does not make a second');
await rejects(() => save({ notes: 'igen' }), 'stale_revision', 'PT409');
saved = await save({ revision: 2, notes: 'N', agreed: 'Träna vänsterfoten', response: adaResponse, leaders: [coachPerson, coach2Person, coachPerson] });
assert.equal(saved.revision, 3);
data = await list();
assert.equal(data.talks[0].leader_notes, 'N');
assert.equal(data.talks[0].agreed, 'Träna vänsterfoten');
assert.equal(data.talks[0].survey_title, 'Inför spelarsamtal');
assert.deepEqual(data.talks[0].leaders.map(l => l.name), ['Coach', 'Dan']);
await as(coach2);
await rejects(() => save({ revision: 2, notes: 'skriver över' }), 'stale_revision', 'PT409');
await rejects(() => save({ notes: 'annans nya' }), 'stale_revision', 'PT409');
await as(coach);

// What is refused.
await rejects(() => save({ talk: id(101), response: boResponse }), 'invalid_response');
await rejects(() => save({ talk: id(101), leaders: [bo] }), 'invalid_leaders');
await rejects(() => save({ talk: id(101), on: '1999-01-01' }), 'invalid_date');
await rejects(() => save({ talk: id(101), notes: 'x'.repeat(20001) }), 'text_too_long');
await rejects(() => save({ talk: id(101), person: cia }), 'talk_needs_player_role');
await rejects(() => save({ talk: id(101), team: other, person: cia }), 'not_found');
await rejects(() => save({ person: bo, revision: 3 }), 'not_found');
await rejects(() => list(id(99)), 'not_found');

// A leader who has left stays on the talk they were at.
await asOwner(`update core.assignments set state='ended' where club_person_id='${coach2Person}'`);
saved = await save({ revision: 3, notes: 'N', response: adaResponse, leaders: [coachPerson, coach2Person] });
assert.equal(saved.revision, 4);
await rejects(() => save({ talk: id(101), leaders: [coach2Person] }), 'invalid_leaders');

// A reader reads only; the player never sees it; outsiders nothing.
await as(viewer);
assert.equal((await list()).can_edit, false);
await rejects(() => save({ revision: 4 }), 'read_only');
await rejects(() => one('select api.delete_player_talk($1,4) v', [talk1]), 'read_only');
await as(adaLogin);
await rejects(() => list(), 'not_found');
await rejects(() => save({ revision: 4 }), 'not_found');
await rejects(() => one('select api.delete_player_talk($1,4) v', [talk1]), 'not_found');
await as(id(9));
await rejects(() => list(), 'not_found');
await as('');
await rejects(() => one('select api.delete_player_talk($1,4) v', [talk1]), 'unauthenticated');
await rejects(() => db.query('select * from core.player_talks'), 'permission denied for table player_talks');
await as(coach);

// The talk stays when the survey answer is deleted.
await asOwner(`delete from core.team_survey_responses where id='${adaResponse}'`);
data = await list();
assert.equal(data.talks[0].response_id, null);
assert.equal(data.talks[0].leader_notes, 'N');

// Deleting.
await rejects(() => one('select api.delete_player_talk($1,3) v', [talk1]), 'stale_revision', 'PT409');
await one('select api.delete_player_talk($1,4) v', [talk1]);
assert.deepEqual((await list()).talks, []);
await rejects(() => save({ revision: 4 }), 'stale_revision', 'PT409');
const events = await asOwner('select command_type, metadata::text m from audit.command_events');
assert.deepEqual(events.map(e => e.command_type).sort(), ['player.talk.created.v1', 'player.talk.deleted.v1']);
assert.ok(events.every(e => !e.m.includes('spela')), 'no notes in the audit trail');

// Erasure takes the person's talks, answers and links; others' stay.
await save({ talk: id(102), person: bo, notes: 'Bo', response: boResponse });
await save({ talk: id(103), notes: 'Ada igen' });
await asOwner(`update core.club_people set display_name='Bosse' where id='${bo}'`);
assert.equal((await list(bo)).talks.length, 1, 'a changed name deletes nothing');
await asOwner(`update core.club_people set display_name='Tidigare spelare', provenance='anonymized' where id='${bo}'`);
assert.deepEqual((await list(bo)).talks, []);
assert.equal((await asOwner(`select (select count(*) from core.team_survey_responses where club_person_id='${bo}')
 + (select count(*) from core.team_survey_invites where club_person_id='${bo}') n`))[0].n, 0);
assert.equal((await list()).talks.length, 1);
assert.equal((await asOwner('select count(*)::int n from core.team_survey_invites'))[0].n, 1);
console.log('player_talks: ok');
