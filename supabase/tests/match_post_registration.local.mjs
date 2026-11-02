// The real command and note functions from 20270127090000 in isolated
// Postgres: after full time events can be recorded, corrected and removed,
// and goals are attributed to the result without changing it. The Match
// Space helpers around them are minimal stand-ins.
// node supabase/tests/match_post_registration.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const leader = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const club = '10000000-0000-4000-8000-000000000001';
const live = '30000000-0000-4000-8000-000000000001', later = '30000000-0000-4000-8000-000000000002';
const playerA = '40000000-0000-4000-8000-000000000001', playerB = '40000000-0000-4000-8000-000000000002';
let n = 0;
const cmd = () => `50000000-0000-4000-8000-${String(++n).padStart(12, '0')}`;
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
let match = live;
const run = (type, payload) => one('select internal.apply_match_command_v2($1,$2,null,$3,$4)', [cmd(), match, type, payload]);
const record = async (type, extra = {}) => (await run('record_event', { minute: 10, type, side: 'us', ...extra })).match_event_id;
const update = (id, extra = {}) => run('update_event', { match_event_id: id, minute: 12, side: 'us', detail: {}, ...extra });
const remove = id => run('void_event', { match_event_id: id });
const score = async () => {
  const row = (await db.query('select score_us,score_opponent from core.match_projections where event_id=$1', [match])).rows[0];
  return `${row.score_us}-${row.score_opponent}`;
};
const unattributed = side => one(`select coalesce(sum((detail->>'delta')::integer),0)::int from core.match_facts
  where event_id=$1 and state='active' and fact_type='score_adjustment' and side=$2`, [match, side]);
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
  create function internal.finish_match_command(p_command_id uuid,p_event_id uuid,p_result jsonb) returns jsonb language plpgsql as $$begin
   update audit.match_commands set result=p_result where command_id=p_command_id; return p_result;end$$;
  create function internal.assert_frozen_match_member(uuid,uuid) returns void language sql as $$select$$;
  create function internal.assert_match_roster_json(uuid,jsonb,jsonb) returns void language sql as $$select$$;
  create function internal.actor_has_capability(uuid,uuid,text) returns boolean language sql as $$select true$$;
  -- The score as the real projection counts it, adjustments included.
  create function internal.recompute_match_projection(p uuid) returns void language sql as $$
   insert into core.match_projections
   select p,
    coalesce(sum(case when side='us' then case when fact_type='score_adjustment' then (detail->>'delta')::integer
     when fact_type='goal' or (fact_type in('shot','penalty','free_kick','corner') and detail->>'result'='scored') then 1 else 0 end else 0 end),0),
    coalesce(sum(case when side='opponent' then case when fact_type='score_adjustment' then (detail->>'delta')::integer
     when fact_type='goal' or (fact_type in('shot','penalty','free_kick','corner') and detail->>'result'='scored') then 1 else 0 end else 0 end),0)
   from core.match_facts where event_id=p and state='active'
   on conflict(event_id) do update set score_us=excluded.score_us,score_opponent=excluded.score_opponent$$;`);
  await db.exec(read('supabase/migrations/20270126090000_match_corrections_after_full_time.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec(read('supabase/migrations/20270127090000_match_post_registration.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec('begin');

  // A match registered live, 2–0.
  await db.query("insert into core.match_workspaces(event_id,club_id,state) values($1,$2,'live')", [live, club]);
  const goal = await record('goal', { player_id: playerA });
  const penalty = await record('penalty', { player_id: playerA, detail: { result: 'scored' } });
  await run('complete_match', { minute: 60 });
  assert.equal(await score(), '2-0');

  const shot = await record('shot', { minute: 30, player_id: playerB, detail: { result: 'on_target' } });
  await record('card', { minute: 40, player_id: playerB, detail: { color: 'yellow' } });
  await update(shot, { player_id: playerA, detail: { result: 'missed' } });
  const note = await one('select internal.record_match_note_for_actor($1,$2,$3,$4)', [cmd(), match, 50, 'Bra press']);
  assert.ok(note.match_event_id);
  assert.equal(await score(), '2-0');
  console.log('PASS: after full time events and notes are recorded and corrected, the result stands');

  await reject(() => record('goal', { player_id: playerB }), /result_locked/);
  await remove(goal);
  assert.equal(await score(), '2-0');
  assert.equal(await unattributed('us'), 1);
  await record('goal', { minute: 15, player_id: playerB, secondary_player_id: playerA });
  assert.equal(await score(), '2-0');
  assert.equal(await unattributed('us'), 0);
  console.log('PASS: a removed goal leaves the result unattributed, and a new goal takes it back');

  await update(penalty, { player_id: playerA, detail: { result: 'saved' } });
  assert.equal(await score(), '2-0');
  assert.equal(await unattributed('us'), 1);
  await reject(() => update(shot, { player_id: playerA, detail: { result: 'scored' } }).then(() => update(shot, { side: 'opponent', detail: { result: 'scored' } })), /result_locked/);
  await update(penalty, { player_id: playerA, detail: { result: 'scored' } });
  assert.equal(await unattributed('us'), 0);
  await reject(() => update(penalty, { side: 'opponent', detail: { result: 'scored' } }), /result_locked/);
  assert.equal(await score(), '2-0');
  console.log('PASS: a goal cannot go to a side that has no goal left in its result');

  // A match registered with its result only, 3–1, then filled in.
  match = later;
  await db.query("insert into core.match_workspaces(event_id,club_id,state) values($1,$2,'completed')", [later, club]);
  await db.query(`insert into core.match_facts(id,event_id,minute,fact_type,side,club_id,detail) values
   (gen_random_uuid(),$1,60,'score_adjustment','us',$2,'{"delta":3,"source":"registered_result"}'),
   (gen_random_uuid(),$1,60,'score_adjustment','opponent',$2,'{"delta":1,"source":"registered_result"}'),
   (gen_random_uuid(),$1,60,'full_time',null,$2,'{}')`, [later, club]);
  await run('record_event', { minute: 5, type: 'substitution', side: 'us', player_id: playerA, secondary_player_id: playerB });
  assert.equal(await score(), '3-1');
  await record('goal', { minute: 8, player_id: playerA });
  await record('penalty', { minute: 20, player_id: playerB, detail: { result: 'scored' } });
  await record('goal', { minute: 33, side: 'opponent' });
  await record('goal', { minute: 50 });
  assert.equal(await score(), '3-1');
  await reject(() => record('goal', { minute: 55, player_id: playerA }), /result_locked/);
  await reject(() => record('goal', { minute: 56, side: 'opponent' }), /result_locked/);
  assert.equal(await one("select count(*)::int from core.match_facts where event_id=$1 and detail->>'source'='post_registration'", [later]), 4);
  console.log('PASS: a match with only its result is filled in goal by goal up to its result');

  await db.query("update core.match_workspaces set state='planning' where event_id=$1", [later]);
  await reject(() => record('shot', { detail: { result: 'missed' } }), /match_not_live/);
  await reject(() => one('select internal.record_match_note_for_actor($1,$2,$3,$4)', [cmd(), later, 5, 'Tidigt']), /match_not_live/);
  console.log('PASS: before the match nothing is recorded');
  await db.exec('rollback');
} finally {
  await db.close();
}
