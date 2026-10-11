// The real share-at-creation migration in isolated Postgres. The CAL-03
// update_event_sharing_for_actor it delegates to is stubbed to record calls.
// node supabase/tests/share_event_at_creation.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const leader = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', outsider = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const club = '10000000-0000-4000-8000-000000000001', otherClub = '10000000-0000-4000-8000-000000000002';
const team = n => `20000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const ev = n => `30000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const series = '60000000-0000-4000-8000-000000000001';
const key = '70000000-0000-4000-8000-000000000001';
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
try {
  await db.exec(`create role anon;create role authenticated;
  create schema internal;create schema api;create schema core;create schema auth;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table core.teams(id uuid primary key,club_id uuid,name text,status text);
  create table core.events(id uuid primary key,club_id uuid,owning_team_id uuid,recurrence_id uuid,
   starts_at timestamptz,revision bigint);
  create table core.event_audiences(event_id uuid,audience_type text,team_id uuid);
  create table internal.sharing_calls(event_id uuid,shared jsonb,audiences jsonb,expected bigint,key uuid);
  create function internal.actor_has_capability(uuid,uuid,cap text) returns boolean language sql stable as $$select auth.uid()='${leader}' and cap='event.manage'$$;
  create function internal.actor_can_manage_event_sharing(uuid) returns boolean language sql stable as $$select auth.uid()='${leader}'$$;
  create function internal.update_event_sharing_for_actor(e uuid,s jsonb,a jsonb,r bigint,k uuid) returns bigint
   language sql as $$insert into internal.sharing_calls values(e,s,a,r,k);select r+1$$;`);
  await db.exec(read('supabase/migrations/20261018090000_share_event_at_creation.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec('begin');

  for (const [n, name, status, c] of [[1, 'P2012', 'active', club], [2, 'F2012', 'active', club],
    [3, 'A-lag', 'active', club], [4, 'Gamla', 'archived', club], [5, 'Annan klubb', 'active', otherClub]]) {
    await db.query('insert into core.teams values($1,$2,$3,$4)', [team(n), c, name, status]);
  }
  // A new weekly series of three (owned by P2012) and a single event.
  for (const n of [1, 2, 3]) {
    await db.query("insert into core.events values($1,$2,$3,$4,now()+($5||' days')::interval,1)", [ev(n), club, team(1), series, String(7 * n)]);
    await db.query("insert into core.event_audiences values($1,'players',$2),($1,'leaders',$2)", [ev(n), team(1)]);
  }
  await db.query("insert into core.events values($1,$2,$3,null,now(),4)", [ev(9), club, team(1)]);
  await db.query("insert into core.event_audiences values($1,'club',null),($1,'guardians',$2)", [ev(9), team(1)]);

  // 1. Shareable teams: the club's other active teams, by name.
  await as(leader);
  const teams = await one('select api.list_shareable_teams($1)', [team(1)]);
  assert.deepEqual(teams.map(t => t.name), ['A-lag', 'F2012'], 'other active teams in the same club only');
  await as(outsider);
  await reject(() => one('select api.list_shareable_teams($1)', [team(1)]), /not_found/);

  // 2. A new series is shared occurrence by occurrence.
  await reject(() => one('select api.share_new_event($1,$2,$3)', [ev(1), [team(2)], key]), /not_found/);
  await as(leader);
  assert.equal(await one('select api.share_new_event($1,$2,$3)', [ev(1), [team(2), team(3), team(2)], key]), 3);
  const calls = (await db.query('select * from internal.sharing_calls order by event_id')).rows;
  assert.deepEqual(calls.map(c => c.event_id), [ev(1), ev(2), ev(3)]);
  for (const call of calls) {
    assert.deepEqual(call.shared.map(s => s.team_id).sort(), [team(2), team(3)], 'duplicates collapse');
    assert.ok(call.shared.every(s => JSON.stringify(s.capabilities) === '["view"]'), 'shared teams can view');
    const audiences = call.audiences.map(a => `${a.type}:${a.team_id ?? '-'}`).sort();
    assert.deepEqual(audiences, [`leaders:${team(1)}`, `leaders:${team(2)}`, `leaders:${team(3)}`,
      `players:${team(1)}`, `players:${team(2)}`, `players:${team(3)}`], 'shared teams get the owner recipients');
    assert.equal(Number(call.expected), 1);
  }
  assert.equal(new Set(calls.map(c => c.key)).size, 3, 'one idempotency key per occurrence');

  // 3. A single event keeps club-wide recipients; nothing chosen does nothing.
  await db.exec('delete from internal.sharing_calls');
  assert.equal(await one('select api.share_new_event($1,$2,$3)', [ev(9), [team(3)], key]), 1);
  const single = (await db.query('select * from internal.sharing_calls')).rows[0];
  assert.deepEqual(single.audiences.map(a => `${a.type}:${a.team_id ?? '-'}`).sort(),
    ['club:-', `guardians:${team(1)}`, `guardians:${team(3)}`]);
  assert.equal(Number(single.expected), 4);
  assert.equal(await one('select api.share_new_event($1,$2,$3)', [ev(9), [], key]), 0);

  // 4. Grants.
  for (const fn of ['api.list_shareable_teams(uuid)', 'api.share_new_event(uuid,uuid[],uuid)']) {
    assert.equal(await one('select has_function_privilege($1,$2,$3)', ['authenticated', fn, 'execute']), true);
    assert.equal(await one('select has_function_privilege($1,$2,$3)', ['anon', fn, 'execute']), false);
  }
  await db.exec('rollback');
  console.log('share event at creation: ok');
} finally {
  await db.close();
}
