// The real team match format migration in isolated Postgres. Minimal fixtures.
// node supabase/tests/team_match_format.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const leader = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', player = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', outsider = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const club = '10000000-0000-4000-8000-000000000001', team = '20000000-0000-4000-8000-000000000001';
const key = n => `70000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const ev = n => `30000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
try {
  await db.exec(`create role anon;create role authenticated;
  create schema internal;create schema api;create schema core;create schema auth;create schema audit;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table internal.command_deduplication(actor_profile_id uuid,idempotency_key uuid,command_type text,result jsonb);
  create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,aggregate_id uuid,aggregate_revision bigint,metadata jsonb);
  create table core.teams(id uuid primary key,club_id uuid,name text,status text,revision bigint not null default 1);
  insert into core.teams(id,club_id,name,status) values('${team}','${club}','P2012','active');
  -- The leader manages the roster; the player can only see it.
  create function internal.actor_has_capability(uuid,team uuid,cap text) returns boolean language sql stable as $$
   select team is not null and ((auth.uid()='${leader}' and cap in ('team.roster.view','team.roster.manage','event.manage'))
    or (auth.uid()='${player}' and cap='team.roster.view'))$$;
  create table core.events(id uuid primary key,club_id uuid,owning_team_id uuid);
  create table core.match_workspaces(event_id uuid primary key,club_id uuid,team_id uuid,updated_by uuid,
   period_minutes integer[] not null default array[45,45]);
  create table core.match_projections(event_id uuid primary key);
  create function internal.assert_match_manager(e uuid) returns core.events language sql as $$select * from core.events where id=e$$;`);
  const migration = read('supabase/migrations/20261020090000_team_match_format.sql').replace(/notify pgrst[^;]*;/, '');
  await db.exec(migration);
  await db.exec('begin');

  // 1. Unset means 11v11.
  await as(player);
  assert.deepEqual(await one('select api.get_team_match_format($1)', [team]),
    { match_format: null, effective: '11v11', can_edit: false });
  await reject(() => one('select api.set_team_match_format($1,$2,$3)', [team, '7v7', key(1)]), /not_found/);
  await as(outsider);
  await reject(() => one('select api.get_team_match_format($1)', [team]), /not_found/);

  // 2. The leader sets 7v7; the same command again is a no-op.
  await as(leader);
  assert.equal((await one('select api.get_team_match_format($1)', [team])).can_edit, true);
  assert.equal(await one('select api.set_team_match_format($1,$2,$3)', [team, '7v7', key(2)]), '7v7');
  assert.equal(await one('select api.set_team_match_format($1,$2,$3)', [team, '7v7', key(2)]), '7v7');
  assert.equal(await one('select count(*)::int from audit.command_events'), 1);
  assert.equal(await one('select revision::int from core.teams where id=$1', [team]), 2);
  await as(player);
  assert.equal((await one('select api.get_team_match_format($1)', [team])).effective, '7v7');

  // 3. Unknown formats are refused, also directly in the table.
  await as(leader);
  await reject(() => one('select api.set_team_match_format($1,$2,$3)', [team, '6v6', key(3)]), /invalid_match_format/);
  await reject(() => db.query("update core.teams set match_format='6v6'"), /teams_match_format_check/);

  // 4. A new match workspace starts with the team format's periods.
  for (const n of [1, 2]) await db.query('insert into core.events values($1,$2,$3)', [ev(n), club, team]);
  const periods = async n => (await db.query('select (internal.ensure_match_workspace($1)).period_minutes p', [ev(n)])).rows[0].p;
  assert.deepEqual(await periods(1), [20, 20, 20], '7v7');
  await db.query('update core.teams set match_format=null');
  assert.deepEqual(await periods(2), [45, 45], 'unset is 11v11');
  assert.deepEqual(await periods(1), [20, 20, 20], 'an existing workspace keeps its periods');
  for (const [format, expected] of [['3v3', [10, 10, 10]], ['5v5', [15, 15, 15]], ['9v9', [35, 35]], ['11v11', [45, 45]]]) {
    assert.deepEqual(await one('select internal.match_format_period_minutes($1)', [format]), expected);
  }

  // 5. Grants; and the migration can run twice.
  for (const fn of ['api.get_team_match_format(uuid)', 'api.set_team_match_format(uuid,text,uuid)']) {
    assert.equal(await one('select has_function_privilege($1,$2,$3)', ['authenticated', fn, 'execute']), true);
    assert.equal(await one('select has_function_privilege($1,$2,$3)', ['anon', fn, 'execute']), false);
  }
  assert.equal(await one('select has_function_privilege($1,$2,$3)', ['authenticated', 'internal.ensure_match_workspace(uuid)', 'execute']), false);
  await db.exec(migration);
  assert.equal(await one("select count(*)::int from internal.migration_provenance"), 1);
  await db.exec('rollback');
  console.log('team match format: ok');
} finally {
  await db.close();
}
