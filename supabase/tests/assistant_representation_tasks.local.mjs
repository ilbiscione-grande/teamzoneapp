import fs from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const db = new PGlite();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const club = id(1), leader = id(2), other = id(3);
const homeTeam = id(10), targetTeam = id(11), thirdTeam = id(12);
const leaderPerson = id(20), playerA = id(21), playerB = id(22), playerC = id(23);
const tasks = async () =>
  (await db.query('select api.list_my_representation_tasks() value')).rows[0].value;
try {
  await db.exec(`create schema core; create schema internal; create schema api; create schema auth; create schema audit;
  create role anon; create role authenticated;
  create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.actor',true),'')::uuid $$;
  create table core.teams(id uuid primary key, club_id uuid, status text, name text);
  create table core.club_people(id uuid primary key, club_id uuid, status text, display_name text,
    representation_available boolean not null default false, revision bigint not null default 1);
  create table core.person_account_links(club_id uuid, club_person_id uuid, profile_id uuid, state text);
  create table core.assignments(club_id uuid, team_id uuid, club_person_id uuid, role_package text, state text,
    starts_at timestamptz, ends_at timestamptz);
  create table core.team_assignments(club_id uuid, team_id uuid, club_person_id uuid, state text,
    starts_at timestamptz, ends_at timestamptz);
  create table core.play_eligibilities(id uuid default gen_random_uuid(), club_id uuid, team_id uuid, home_team_id uuid,
    club_person_id uuid, state text, ends_at timestamptz, review_due_at timestamptz);
  create table audit.command_events(command_type text, aggregate_id uuid, metadata jsonb, occurred_at timestamptz default now());
  create table core.profiles(id uuid primary key);
  create table internal.assistant_task_preferences(profile_id uuid primary key, hidden_kinds text[] not null default '{}',
    revision bigint not null default 0, current_team_only boolean not null default false,
    welcome_message_visible boolean not null default true,
    constraint assistant_task_preferences_hidden_kinds_check check (hidden_kinds <@ array['pending_callups']::text[]));
  create function internal.get_assistant_task_preferences_for_actor() returns jsonb language sql as
    $$ select to_jsonb(p.hidden_kinds) from internal.assistant_task_preferences p where p.profile_id=auth.uid() $$;
  -- Leaders manage their own teams; nobody manages the third team.
  create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql as
    $$ select t in ('${homeTeam}','${targetTeam}') $$;
  insert into core.teams values ('${homeTeam}','${club}','active','P2014'),('${targetTeam}','${club}','active','P2013'),
    ('${thirdTeam}','${club}','active','P2012');
  insert into core.club_people(id,club_id,status,display_name) values ('${leaderPerson}','${club}','active','Ledare'),
    ('${playerA}','${club}','active','A'),('${playerB}','${club}','active','B'),('${playerC}','${club}','active','C');
  insert into core.person_account_links values ('${club}','${leaderPerson}','${leader}','active');
  insert into core.assignments values ('${club}','${homeTeam}','${leaderPerson}','leader','active',now()-interval '1 year',null),
    ('${club}','${targetTeam}','${leaderPerson}','leader','active',now()-interval '1 year',null);
  insert into core.team_assignments values ('${club}','${homeTeam}','${playerA}','active',now()-interval '1 year',null),
    ('${club}','${homeTeam}','${playerB}','active',now()-interval '1 year',null),
    ('${club}','${thirdTeam}','${playerC}','active',now()-interval '1 year',null);
  -- Player C was made available long ago, before the column existed.
  update core.club_people set representation_available = true where id = '${playerC}';
  insert into audit.command_events values ('roster.person.representation_available.set.v1','${playerC}',
    '{"available":true}', now() - interval '30 days');
  select set_config('test.actor','${leader}',false);`);
  await db.exec(fs.readFileSync('supabase/migrations/20270412090000_assistant_representation_tasks.sql', 'utf8'));

  const c = (await db.query(`select representation_available_at at from core.club_people where id='${playerC}'`)).rows[0].at;
  assert.ok(Date.now() - new Date(c).getTime() > 29 * 864e5, 'backfill from the audit log');
  assert.deepEqual(await tasks(), [], 'nothing new');

  await db.exec(`update core.club_people set representation_available = true where id in ('${playerA}','${playerB}')`);
  assert.deepEqual(await tasks(), [
    { club_id: club, team_id: targetTeam, kind: 'available', count: 2 },
  ], 'the home team itself is not told; the old availability is not repeated');

  await db.exec(`insert into core.play_eligibilities(club_id,team_id,home_team_id,club_person_id,state,ends_at)
    values ('${club}','${targetTeam}','${homeTeam}','${playerA}','pending',now()+interval '30 days')`);
  assert.deepEqual(await tasks(), [
    { club_id: club, team_id: homeTeam, kind: 'decide', count: 1 },
    { club_id: club, team_id: targetTeam, kind: 'available', count: 1 },
  ].sort((a, b) => a.team_id.localeCompare(b.team_id)), 'a request leaves the pool and waits for the home team');

  await db.exec(`update core.play_eligibilities set state='active'`);
  await db.exec(`update core.club_people set representation_available = false where id='${playerB}'`);
  assert.equal((await db.query(`select representation_available_at at from core.club_people where id='${playerB}'`)).rows[0].at, null);
  assert.deepEqual(await tasks(), [], 'approved and withdrawn');

  await db.query("select set_config('test.actor',$1,false)", [other]);
  assert.deepEqual(await tasks(), [], 'not a leader');
  await db.query("select set_config('test.actor','',false)");
  await assert.rejects(tasks(), /unauthenticated/);

  await db.exec(`insert into core.profiles values ('${leader}')`);
  await db.query("select set_config('test.actor',$1,false)", [leader]);
  const save = (hidden, revision) => db.query(
    'select internal.set_assistant_task_preferences_v3_for_actor($1,$2,false,true) value', [hidden, revision]);
  await save(['inbox_messages', 'team_representation_available'], 0);
  assert.deepEqual((await db.query('select hidden_kinds from internal.assistant_task_preferences')).rows[0].hidden_kinds,
    ['inbox_messages', 'team_representation_available']);
  await assert.rejects(save(['unknown'], 1), /invalid_preferences/);
  await assert.rejects(save(['inbox_notices'], 0), (error) => error.code === 'PT409');
  console.log('assistant representation tasks: ok');
} finally {
  await db.close();
}
