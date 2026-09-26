// Run: node supabase/tests/pub07_personal_home.local.mjs --direct-result
// Real match tables/functions plus the existing public-projection fixture.
import assert from 'node:assert/strict';
export async function testDirectResult(db, read, segment) {
 await db.exec(`
 delete from core.match_projections; delete from core.match_workspaces;
 alter table core.events add column revision bigint default 1, add column updated_at timestamptz;
 alter table core.match_workspaces alter column state set default 'planning',
  add column club_id uuid,add column team_id uuid,add column revision bigint default 0,
  add column roster_revision bigint default 0,add column completed_at timestamptz,
  add column updated_at timestamptz,add column updated_by uuid,
  add column period_minutes integer[] default array[45,45];
 alter table core.match_projections alter column revision set default 0,
  alter column score_us set default 0,alter column score_opponent set default 0,
  add column stats jsonb default '{}',add column updated_at timestamptz;
 create table core.club_people(id uuid,club_id uuid,unique(id,club_id));
 create function internal.actor_can_manage_event(uuid) returns boolean language sql stable as
  $$select auth.uid()='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid$$;
 create table core.event_revisions(club_id uuid,event_id uuid,event_revision bigint,action text,scope text,snapshot jsonb,actor_profile_id uuid,reason text);
 alter table audit.command_events add column reason text;
 create table internal.domain_outbox(club_id uuid,event_type text,aggregate_type text,aggregate_id uuid,aggregate_revision bigint,payload jsonb);
 create function internal.event_snapshot(core.events) returns jsonb language sql stable as $$select to_jsonb($1)$$;
 update core.events set state='scheduled';
 `);
 const foundation=read('supabase/migrations/20260815074741_s07_match_v2_adapter_foundation.sql');
 await db.exec(segment(foundation,'create table audit.match_commands','create table core.match_roster_revisions'));
 await db.exec(segment(foundation,'create table core.match_facts','create table core.match_projections'));
 await db.exec(segment(foundation,'create function internal.reject_match_command_mutation','insert into internal.migration_provenance'));
 const engine=read('supabase/migrations/20260815075030_s07_command_roster_projection_engine.sql');
 await db.exec(segment(engine,'create or replace function internal.reject_match_command_mutation','create function internal.assert_frozen_match_member'));
 await db.exec(segment(engine,'create function internal.recompute_match_projection','create function internal.freeze_match_roster_for_actor'));
 await db.exec(segment(read('supabase/migrations/20260815075650_s07_v2_mutation_contract.sql'),
  'create table audit.match_fact_versions','create function internal.assert_match_roster_json'));
 await db.exec(segment(read('supabase/migrations/20260827072045_cal04_safe_event_lifecycle.sql'),
  'create or replace function internal.transition_event_for_actor','create function internal.delete_event_draft_for_actor'));
 await db.exec(read('supabase/migrations/20260926070459_match_direct_result_registration.sql'));
 const event='30000000-0000-4000-8000-000000000001',team='20000000-0000-4000-8000-000000000001';
 const id='50000000-0000-4000-8000-000000000001';
 const call=(command=id,revision=0,eventRevision=1,us=3,opponent=1,reason=null)=>
  db.query('select api.register_match_result($1,$2,$3,$4,$5,$6,$7) result',[command,event,revision,eventRevision,us,opponent,reason]);
 const reject=async (fn,code)=>{await db.exec('savepoint rejected');try{await assert.rejects(fn,e=>e.code===code);}finally{await db.exec('rollback to rejected');}};
 await reject(()=>call(),'42501');
 await db.exec("select set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true)");
 await reject(()=>call(),'42501');
 await db.exec("select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true)");
 await reject(()=>call(id,0,1,-1),'22023');
 await reject(()=>call(id,0,4),'40001');
 await db.exec(`update core.events set starts_at=now()+interval '1 day' where id='${event}'`);
 await reject(()=>call(),'23514');
 await db.exec(`update core.events set starts_at=now()-interval '1 day',state='cancelled' where id='${event}'`);
 await reject(()=>call(),'42501');
 await db.exec(`update core.events set state='scheduled',archived_at=now() where id='${event}'`);
 await reject(()=>call(),'42501');
 await db.exec(`update core.events set archived_at=null,event_type='training' where id='${event}'`);
 await reject(()=>call(),'42501');
 await db.exec(`update core.events set event_type='match' where id='${event}'`);
 await db.exec('savepoint fresh_result');
 const first=(await call()).rows[0].result;
 assert.deepEqual(first,{revision:1,event_revision:2,score_us:3,score_opponent:1,state:'completed'});
 assert.deepEqual((await call()).rows[0].result,first,'retry returns original receipt');
 assert.equal((await db.query('select count(*)::int n from core.match_facts')).rows[0].n,3);
 assert.equal((await db.query('select count(*)::int n from public_api.match_result_projections')).rows[0].n,0,'private until team opts in');
 await reject(()=>call(id,0,1,4),'23505');
 await reject(()=>call('50000000-0000-4000-8000-000000000002',1,2,0,0),'22023');
 await db.query('select api.set_team_event_visibility($1,true,false,0)',[team]);
 await call('50000000-0000-4000-8000-000000000002',1,2,0,0,'Rättat protokoll');
 const score=(await db.query('select score_us,score_opponent from public_api.match_result_projections')).rows[0];
 assert.deepEqual(score,{score_us:0,score_opponent:0});
 assert.equal((await db.query("select count(*)::int n from core.match_facts where fact_type='full_time'")).rows[0].n,1,'no duplicate full time');
 assert.equal((await db.query('select count(*)::int n from core.event_revisions')).rows[0].n,1,'event transition audited once');
 assert.equal((await db.query('select count(*)::int n from audit.match_fact_versions')).rows[0].n,5,'old facts retained and changes audited');
 await reject(()=>call('50000000-0000-4000-8000-000000000003',1,2,2,1,'Rättat igen'),'40001');
 assert.equal((await db.query("select has_function_privilege('anon','api.register_match_result(uuid,uuid,bigint,bigint,integer,integer,text)','execute') allowed")).rows[0].allowed,false);
 await db.exec('rollback to fresh_result');
 // A fresh 0–0 creates only full time, not fabricated player goals.
 await db.exec('savepoint zero_result');
 await call(id,0,1,0,0);
 assert.equal((await db.query('select count(*)::int n from core.match_facts')).rows[0].n,1);
 await db.exec('rollback to zero_result');
 // A live score may include scored shots and a raw negative adjustment.
 await db.query('select internal.ensure_match_workspace($1)',[event]);
 await db.exec(`update core.match_workspaces set state='live';
  insert into audit.match_commands(command_id,event_id,command_type,actor_profile_id)
  values('60000000-0000-4000-8000-000000000001','${event}','fixture','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
   ('60000000-0000-4000-8000-000000000002','${event}','fixture','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  insert into core.match_facts(event_id,minute,fact_type,side,club_id,detail,source_command_id,created_by,updated_by)
  values('${event}',12,'shot','us','10000000-0000-4000-8000-000000000001','{"result":"scored"}',
   '60000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  ('${event}',13,'score_adjustment','opponent','10000000-0000-4000-8000-000000000001','{"delta":-2}',
   '60000000-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');`);
 await call(id,0,1,3,1);
 assert.deepEqual((await db.query('select score_us,score_opponent from core.match_projections')).rows[0],{score_us:3,score_opponent:1});
 assert.equal((await db.query("select count(*)::int n from core.match_facts where minute in(12,13) and state='active'")).rows[0].n,2,'existing facts remain untouched');
 console.log('PASS: atomic score/event completion, zero score, retry, history, corrections, revisions, authorization and team publication');
 if (process.argv.includes('--written-reports')) {
  const { testWrittenReports } = await import('./match_written_reports.local.mjs');
  await testWrittenReports(db,read);
 }
}
