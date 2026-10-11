// The real event match settings migration in isolated Postgres, on top of the
// team match format migration. Minimal fixtures.
// node supabase/tests/event_match_settings.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const leader = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', player = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const club = '10000000-0000-4000-8000-000000000001', team = '20000000-0000-4000-8000-000000000001';
const series = '60000000-0000-4000-8000-000000000001';
const ev = n => `30000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const key = n => `70000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
const settings = n => one('select api.get_event_match_settings($1)', [ev(n)]);
const set = (n, format, periods, scope, k) => one('select api.set_event_match_settings($1,$2,$3,$4,$5)', [ev(n), format, periods, scope, key(k)]);
try {
  await db.exec(`create role anon;create role authenticated;
  create schema internal;create schema api;create schema core;create schema auth;create schema audit;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table internal.command_deduplication(actor_profile_id uuid,idempotency_key uuid,command_type text,result jsonb);
  create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,aggregate_id uuid,aggregate_revision bigint,metadata jsonb);
  create table core.teams(id uuid primary key,club_id uuid,name text,status text,revision bigint not null default 1);
  insert into core.teams(id,club_id,name,status) values('${team}','${club}','P2012','active');
  create function internal.actor_has_capability(uuid,uuid,text) returns boolean language sql stable as $$select auth.uid()='${leader}'$$;
  create table core.events(id uuid primary key,club_id uuid,owning_team_id uuid,event_type text,recurrence_id uuid,
   occurrence_number integer,starts_at timestamptz,revision bigint not null default 1);
  create table core.match_workspaces(event_id uuid primary key,club_id uuid,team_id uuid,updated_by uuid,
   state text not null default 'planning',revision bigint not null default 0,
   period_minutes integer[] not null default array[45,45]);
  create table core.match_projections(event_id uuid primary key);
  create function internal.assert_match_manager(e uuid) returns core.events language sql as $$select * from core.events where id=e$$;
  create function internal.actor_can_read_event(uuid) returns boolean language sql stable as $$select auth.uid() is not null$$;
  create function internal.actor_can_manage_event(uuid) returns boolean language sql stable as $$select auth.uid()='${leader}'$$;`);
  await db.exec(read('supabase/migrations/20261020090000_team_match_format.sql').replace(/notify pgrst[^;]*;/, ''));
  const migration = read('supabase/migrations/20261021090000_event_match_settings.sql').replace(/notify pgrst[^;]*;/, '');
  await db.exec(migration);
  await db.exec('begin');
  // A weekly series of three matches, a single match and a training.
  for (const n of [1, 2, 3]) {
    await db.query("insert into core.events values($1,$2,$3,'match',$4,$5::int,now()+make_interval(weeks=>$5::int))", [ev(n), club, team, series, n]);
  }
  await db.query("insert into core.events values($1,$2,$3,'match',null,null,now())", [ev(4), club, team]);
  await db.query("insert into core.events values($1,$2,$3,'training',null,null,now())", [ev(5), club, team]);
  await db.query("update core.teams set match_format='7v7'");

  // 1. Without a choice: the team format and its periods.
  await as(player);
  assert.deepEqual(await settings(4), { match_format: '7v7', period_minutes: [20, 20, 20], is_set: false, locked: false });
  await reject(() => set(4, '5v5', [15, 15, 15], 'one', 1), /not_found/);

  // 2. One match gets 9v9 with 3×25; a planned workspace follows.
  await as(leader);
  await db.query('select internal.ensure_match_workspace($1)', [ev(4)]);
  assert.equal(await set(4, '9v9', [25, 25, 25], 'one', 2), 1);
  assert.deepEqual(await settings(4), { match_format: '9v9', period_minutes: [25, 25, 25], is_set: true, locked: false });
  assert.deepEqual(await one('select period_minutes from core.match_workspaces where event_id=$1', [ev(4)]), [25, 25, 25]);

  // 3. A started match keeps its clock and reports itself locked.
  await db.query("update core.match_workspaces set state='live' where event_id=$1", [ev(4)]);
  assert.equal(await set(4, '11v11', [45, 45], 'one', 3), 1);
  assert.deepEqual(await one('select period_minutes from core.match_workspaces where event_id=$1', [ev(4)]), [25, 25, 25]);
  const locked = await settings(4);
  assert.equal(locked.locked, true);
  assert.deepEqual(locked.period_minutes, [25, 25, 25], 'the workspace periods are shown');

  // 4. Scope: this and following occurrences of the series.
  assert.equal(await set(2, '5v5', [15, 15, 15], 'forward', 4), 2);
  assert.equal((await settings(1)).is_set, false);
  assert.equal((await settings(3)).match_format, '5v5');
  assert.equal(await set(1, '11v11', [40, 40], 'all', 5), 3);
  assert.deepEqual((await settings(2)).period_minutes, [40, 40]);
  // The same command again is not applied twice.
  assert.equal(await set(1, '11v11', [40, 40], 'all', 5), 3);

  // 5. New workspaces start with the event's periods.
  assert.deepEqual((await db.query('select (internal.ensure_match_workspace($1)).period_minutes p', [ev(3)])).rows[0].p, [40, 40]);

  // 6. Refused: a training, bad periods, unknown format or scope.
  await reject(() => set(5, '5v5', [15], 'one', 6), /not_found/);
  await reject(() => set(4, '5v5', [0, 15], 'one', 7), /invalid_match_settings/);
  await reject(() => set(4, '5v5', [121], 'one', 8), /invalid_match_settings/);
  await reject(() => set(4, '6v6', [15], 'one', 9), /invalid_match_settings/);
  await reject(() => set(4, '5v5', [15], 'later', 10), /invalid_match_settings/);

  // 7. Grants; the table only through the functions; reruns cleanly.
  for (const fn of ['api.get_event_match_settings(uuid)', 'api.set_event_match_settings(uuid,text,integer[],text,uuid)']) {
    assert.equal(await one('select has_function_privilege($1,$2,$3)', ['authenticated', fn, 'execute']), true);
    assert.equal(await one('select has_function_privilege($1,$2,$3)', ['anon', fn, 'execute']), false);
  }
  assert.equal(await one("select has_table_privilege('authenticated','core.event_match_settings','select')"), false);
  await db.exec(migration);
  await db.exec('rollback');
  console.log('event match settings: ok');
} finally {
  await db.close();
}
