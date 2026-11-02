// The real command function from 20270126090000 in isolated Postgres: after
// full time events can be corrected and removed, but not so the result
// changes. The Match Space helpers around it are minimal stand-ins.
// node supabase/tests/match_corrections_after_full_time.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const leader = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const club = '10000000-0000-4000-8000-000000000001';
const match = '30000000-0000-4000-8000-000000000001';
const playerA = '40000000-0000-4000-8000-000000000001', playerB = '40000000-0000-4000-8000-000000000002';
let n = 0;
const cmd = () => `50000000-0000-4000-8000-${String(++n).padStart(12, '0')}`;
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
const run = (type, payload) => one('select internal.apply_match_command_v2($1,$2,null,$3,$4)', [cmd(), match, type, payload]);
const record = async (type, extra = {}) => (await run('record_event', { minute: 10, type, side: 'us', ...extra })).match_event_id;
const update = (id, extra = {}) => run('update_event', { match_event_id: id, minute: 12, side: 'us', detail: {}, ...extra });
const remove = id => run('void_event', { match_event_id: id });
const score = async () => (await db.query('select score_us,score_opponent from core.match_projections')).rows[0];
try {
  await db.exec(`create role anon;create role authenticated;
  create schema internal;create schema api;create schema core;create schema auth;create schema audit;
  create function auth.uid() returns uuid language sql stable as $$select '${leader}'::uuid$$;
  create table core.match_workspaces(event_id uuid primary key,club_id uuid,state text,revision bigint default 0,roster_revision integer default 1,
   match_started_at timestamptz,match_paused_at timestamptz,paused_seconds integer default 0,completed_at timestamptz,unlocked_at timestamptz,
   updated_at timestamptz,updated_by uuid);
  create table core.match_plans(event_id uuid primary key,revision bigint,formation text,starting_xi jsonb,substitution_checklist jsonb,
   set_pieces_notes text,tactics_notes text,match_kpis text,key_opponents_notes text,kpi_review text,board_background text,board_strokes jsonb,
   kpi_buttons jsonb,enabled_quick_actions jsonb,updated_at timestamptz,updated_by uuid);
  create table core.match_projections(event_id uuid primary key,score_us integer,score_opponent integer);
  create table core.match_facts(id uuid primary key,event_id uuid,minute integer,fact_type text,side text,club_person_id uuid,
   secondary_club_person_id uuid,club_id uuid,detail jsonb,state text default 'active',voided_at timestamptz,voided_by uuid,void_reason text,
   fact_revision integer default 1,source_command_id uuid,created_by uuid,updated_by uuid,created_at timestamptz default clock_timestamp(),updated_at timestamptz);
  create table audit.match_fact_versions(fact_id uuid,event_id uuid,fact_revision integer,snapshot jsonb,action text,actor_profile_id uuid,reason text);
  create table audit.match_commands(command_id uuid primary key,event_id uuid,command_type text,payload jsonb,result jsonb);
  create function internal.ensure_match_workspace(p uuid) returns core.match_workspaces language sql as $$select * from core.match_workspaces where event_id=p$$;
  create function internal.register_match_command(p_command_id uuid,p_event_id uuid,p_expected bigint,p_type text,p_payload jsonb)
   returns boolean language plpgsql as $$declare n integer;begin
   insert into audit.match_commands values(p_command_id,p_event_id,p_type,p_payload,null) on conflict do nothing;
   get diagnostics n=row_count; return n=1;end$$;
  create function internal.assert_frozen_match_member(uuid,uuid) returns void language sql as $$select$$;
  create function internal.assert_match_roster_json(uuid,jsonb,jsonb) returns void language sql as $$select$$;
  create function internal.actor_has_capability(uuid,uuid,text) returns boolean language sql as $$select true$$;
  -- The score as the real projection counts it.
  create function internal.recompute_match_projection(p uuid) returns void language sql as $$
   insert into core.match_projections
   select p,
    count(*) filter (where side='us' and (fact_type='goal' or (fact_type in('shot','penalty','free_kick','corner') and detail->>'result'='scored'))),
    count(*) filter (where side='opponent' and (fact_type='goal' or (fact_type in('shot','penalty','free_kick','corner') and detail->>'result'='scored')))
   from core.match_facts where event_id=p and state='active'
   on conflict(event_id) do update set score_us=excluded.score_us,score_opponent=excluded.score_opponent$$;`);
  await db.exec(read('supabase/migrations/20270126090000_match_corrections_after_full_time.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec('begin');
  await db.query("insert into core.match_workspaces(event_id,club_id,state) values($1,$2,'live')", [match, club]);

  const goal = await record('goal', { player_id: playerA });
  const penalty = await record('penalty', { player_id: playerA, detail: { result: 'scored' } });
  const shot = await record('shot', { player_id: playerB, detail: { result: 'missed' } });
  const sub = await record('substitution', { player_id: playerA, secondary_player_id: playerB });
  const card = await record('card', { player_id: playerB, detail: { color: 'yellow' } });
  assert.deepEqual(await score(), { score_us: 2, score_opponent: 0 });
  await run('complete_match', { minute: 60 });
  assert.equal(await one('select state from core.match_workspaces'), 'completed');
  console.log('PASS: a match with a goal and a penalty goal ends 2–0');

  await reject(() => record('shot', { detail: { result: 'missed' } }), /match_not_live/);
  console.log('PASS: no new events after full time');

  await update(shot, { player_id: playerA, detail: { result: 'on_target' } });
  await update(sub, { minute: 45, player_id: playerA, secondary_player_id: playerB });
  await update(card, { player_id: playerB, detail: { color: 'red' } });
  await remove(shot);
  assert.equal(await one("select state from core.match_facts where id=$1", [shot]), 'voided');
  assert.equal(await one("select minute from core.match_facts where id=$1", [sub]), 45);
  assert.equal(await one("select detail->>'color' from core.match_facts where id=$1", [card]), 'red');
  assert.deepEqual(await score(), { score_us: 2, score_opponent: 0 });
  console.log('PASS: shots, substitutions and cards can be corrected and removed after full time');

  await update(penalty, { player_id: playerB, detail: { result: 'scored', comment: 'Säker' } });
  assert.equal(await one("select club_person_id from core.match_facts where id=$1", [penalty]), playerB);
  console.log('PASS: a penalty goal can get another taker and still count');

  await reject(() => remove(goal), /result_locked/);
  await reject(() => remove(penalty), /result_locked/);
  await reject(() => update(penalty, { player_id: playerB, detail: { result: 'saved' } }), /result_locked/);
  await reject(() => update(penalty, { side: 'opponent', detail: { result: 'scored' } }), /result_locked/);
  assert.deepEqual(await score(), { score_us: 2, score_opponent: 0 });
  console.log('PASS: after full time nothing can change the result');

  await db.query("update core.match_workspaces set state='planning'");
  await reject(() => update(card, { detail: { color: 'yellow' } }), /match_not_live/);
  console.log('PASS: before the match nothing is corrected');
  await db.exec('rollback');
} finally {
  await db.close();
}
