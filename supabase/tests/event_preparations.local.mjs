// Isolated PostgreSQL tests for Förberedelser v1 and Matchläge v1: no hosted
// database connection. Runs the real Match Space v2 migration chain on top
// of minimal event/roster/storage/realtime stubs.
// Run: node supabase/tests/event_preparations.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');
const db=new PGlite();
const leader='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',player1='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 player2='cccccccc-cccc-4ccc-8ccc-cccccccccccc',guardian='dddddddd-dddd-4ddd-8ddd-dddddddddddd',
 outsider='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const club='10000000-0000-4000-8000-000000000001',team='20000000-0000-4000-8000-000000000001';
const event='30000000-0000-4000-8000-000000000001',earlier='30000000-0000-4000-8000-000000000002';
const p1='40000000-0000-4000-8000-000000000001',p2='40000000-0000-4000-8000-000000000002',
 pLeader='40000000-0000-4000-8000-000000000003',pGuardian='40000000-0000-4000-8000-000000000004',
 pForeign='40000000-0000-4000-8000-000000000005';
const id=n=>'90000000-0000-4000-8000-'+String(n).padStart(12,'0');
const as=async profile=>{await db.query("select set_config('request.jwt.claim.sub',$1,false)",[profile]);};
const q=async(sql,params=[])=>(await db.query(sql,params)).rows;
const one=async(sql,params=[])=>(await q(sql,params))[0];
const rejects=async(fn,code,message)=>{
 await db.exec('savepoint rejected');
 try{await assert.rejects(fn,e=>e.code===code,message);}finally{await db.exec('rollback to rejected');}
};
try {
 await db.exec(`
 create role anon;create role authenticated;create role service_role;
 create schema core;create schema internal;create schema api;create schema audit;create schema auth;create schema storage;create schema realtime;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
 create table core.profiles(id uuid primary key,display_name text default '');
 create table core.events(id uuid primary key,club_id uuid,owning_team_id uuid,event_type text,state text,archived_at timestamptz,
  starts_at timestamptz default now(),ends_at timestamptz default now()+interval '2 hours',unique(id,club_id),unique(id,club_id,owning_team_id));
 create table core.event_teams(event_id uuid,club_id uuid,team_id uuid,relation text,capabilities text[] default '{}');
 create table core.club_people(id uuid primary key,club_id uuid,display_name text,unique(id,club_id));
 create table core.person_account_links(club_id uuid,club_person_id uuid,profile_id uuid,state text);
 create table core.assignments(club_id uuid,team_id uuid,club_person_id uuid,role_package text,state text,starts_at timestamptz,ends_at timestamptz);
 create table core.callups(id uuid primary key default gen_random_uuid(),club_id uuid,event_id uuid,squad_revision_id uuid,
  club_person_id uuid,state text,sent_at timestamptz,unique(id,club_id));
 create table core.attendance_facts(club_id uuid,event_id uuid,club_person_id uuid,status text);
 create table core.guardian_relations(club_id uuid,guardian_person_id uuid,child_person_id uuid,state text,starts_at timestamptz,ends_at timestamptz);
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(bucket_id text,name text,owner_id text,metadata jsonb);
 alter table storage.objects enable row level security;
 create table realtime.messages(extension text,topic text);
 create function realtime.topic() returns text language sql stable as $$select current_setting('realtime.topic',true)$$;
 create table realtime.sent(payload jsonb,event text,topic text,private boolean);
 create function realtime.send(payload jsonb,event text,topic text,private boolean) returns void language sql as
  $$insert into realtime.sent values(payload,event,topic,private)$$;
 -- Event visibility/management stubs: the leader manages; team members and
 -- the guardian read; the outsider sees nothing.
 create function internal.actor_can_read_event(uuid) returns boolean language sql stable as
  $$select auth.uid() in('${leader}','${player1}','${player2}','${guardian}')$$;
 create function internal.actor_can_manage_event(uuid) returns boolean language sql stable as $$select auth.uid()='${leader}'::uuid$$;
 create function internal.actor_can_manage_event_roster(uuid) returns boolean language sql stable as $$select auth.uid()='${leader}'::uuid$$;
 create function internal.actor_has_capability(uuid,uuid,text) returns boolean language sql stable as $$select auth.uid()='${leader}'::uuid$$;
 create function internal.actor_owns_club_person(target_club_id uuid,target_club_person_id uuid) returns boolean language sql stable as
  $$select exists(select 1 from core.person_account_links link where link.profile_id=auth.uid() and link.club_id=target_club_id
   and link.club_person_id=target_club_person_id and link.state='active')$$;
 insert into core.profiles(id) values('${leader}'),('${player1}'),('${player2}'),('${guardian}'),('${outsider}');
 insert into core.events values('${event}','${club}','${team}','match','scheduled',null),('${earlier}','${club}','${team}','training','scheduled',null);
 insert into core.event_teams values('${event}','${club}','${team}','primary'),('${earlier}','${club}','${team}','primary');
 insert into core.club_people values('${p1}','${club}','Erik Andersson'),('${p2}','${club}','Johan Lind'),
  ('${pLeader}','${club}','Thomas Emilson'),('${pGuardian}','${club}','Förälder Andersson'),('${pForeign}','10000000-0000-4000-8000-000000000009','Annan klubb');
 insert into core.person_account_links values('${club}','${p1}','${player1}','active'),('${club}','${p2}','${player2}','active'),
  ('${club}','${pLeader}','${leader}','active'),('${club}','${pGuardian}','${guardian}','active');
 insert into core.assignments values('${club}','${team}','${p1}','player','active',now()-interval '1 year',null),
  ('${club}','${team}','${p2}','player','active',now()-interval '1 year',null),('${club}','${team}','${pLeader}','leader','active',now()-interval '1 year',null);
 insert into core.guardian_relations values('${club}','${pGuardian}','${p1}','active',now()-interval '1 year',null);
 grant usage on schema api,internal,auth,core,storage,realtime to authenticated;
 grant select on storage.objects to authenticated;
 `);
 for (const file of ['20260815074741_s07_match_v2_adapter_foundation','20260815075030_s07_command_roster_projection_engine',
  '20260815075322_s07_fix_roster_result_binding','20260815075428_s07_fix_snapshot_cursor','20260815075650_s07_v2_mutation_contract',
  '20260815080102_s07_fix_reset_fact_versioning','20260815091054_s07_halftime_clock_anchor',
  '20260928150000_event_preparations_v1','20260928150100_match_mode_v1']) {
  await db.exec(read(`supabase/migrations/${file}.sql`));
 }
 await db.exec('begin');

 // --- Förberedelser: items ---------------------------------------------
 const save=(itemId,kind,label,assignee=null,rev=0,target=event)=>
  one('select api.save_event_preparation_item($1,$2,$3,$4,$5,$6) v',[target,itemId,kind,label,assignee,rev]);
 await as(leader);
 const focus=(await save(id(1),'focus','Speluppbyggnad')).v;
 assert.equal(focus.revision,1);
 assert.deepEqual((await save(id(1),'focus','Speluppbyggnad')).v,focus,'retry after success returns the stored item');
 await save(id(2),'material','Bollar');
 const task=(await save(id(3),'task','Ta fram material',p1)).v;
 assert.equal(task.assignee_name,'Erik Andersson');
 await rejects(()=>save(id(4),'task','Okänd',pForeign),'22023','assignee must belong to the event');
 await rejects(()=>save(id(5),'focus','Med ansvarig',p1),'22023','only tasks have assignees');
 await rejects(()=>save(id(6),'focus','Försvunnen',null,3),'40001','editing a deleted item is a conflict');
 const renamed=(await save(id(3),'task','Ta fram koner',p2,1)).v;
 assert.equal(renamed.revision,2);
 await rejects(()=>save(id(3),'task','Gammal ändring',null,1),'40001','stale edit is rejected');
 const done=(await one('select api.set_event_preparation_item_done($1,true) v',[id(3)])).v;
 assert.equal(done.done,true);
 assert.equal((await one('select api.set_event_preparation_item_done($1,true) v',[id(3)])).v.revision,done.revision,'second tick is a no-op');
 await rejects(()=>q('select api.set_event_preparation_item_done($1,true)',[id(1)]),'22023','focus cannot be done');
 for (const [n,label] of [[10,'Föregående möte'],[11,'Träningsupplägg'],[12,'Övriga frågor']]) await save(id(n),'agenda',label);
 await q('select api.reorder_event_preparation_items($1,$2,$3)',[event,'agenda',[id(12),id(10),id(11)]]);
 assert.deepEqual((await q("select label from core.event_preparation_items where kind='agenda' order by position")).map(r=>r.label),
  ['Övriga frågor','Föregående möte','Träningsupplägg']);
 await rejects(()=>q('select api.reorder_event_preparation_items($1,$2,$3)',[event,'agenda',[id(12),id(2)]]),'22023','foreign kind in order');
 await q('select api.delete_event_preparation_item($1,$2)',[event,id(11)]);
 await q('select api.delete_event_preparation_item($1,$2)',[event,id(11)]);
 assert.equal((await one("select count(*)::int n from core.event_preparation_items where kind='agenda'")).n,2,'delete is idempotent');
 // Previously used material on another event of the same team is suggested.
 await save(id(20),'material','Koner',null,0,earlier);
 await save(id(21),'material','bollar',null,0,earlier);
 const suggestions=(await one('select api.list_event_preparation_suggestions($1,$2) v',[event,'material'])).v;
 assert.equal(suggestions.length,2,'labels are deduplicated case-insensitively');
 assert.ok(suggestions.includes('Koner'));
 // Note
 const note=(await one('select api.save_event_preparation_note($1,$2,0) v',[event,'Samling 12:30.\nVitt matchställ.'])).v;
 assert.equal(note.revision,1);
 assert.equal((await one('select api.save_event_preparation_note($1,$2,0) v',[event,'Samling 12:30.\nVitt matchställ.'])).v.revision,1,'identical retry');
 await rejects(()=>q('select api.save_event_preparation_note($1,$2,0)',[event,'Annan text']),'40001','stale note');
 // Read-only and outsider
 await as(player1);
 const view=(await one('select api.get_event_preparation($1) v',[event])).v;
 assert.equal(view.can_edit,false);
 assert.equal(view.items.length,5);
 assert.equal(view.note.body,'Samling 12:30.\nVitt matchställ.');
 await rejects(()=>save(id(30),'focus','Spelare'),'42501','read-only user cannot edit');
 await rejects(()=>q('select api.set_event_preparation_item_done($1,false)',[id(3)]),'42501','read-only user cannot tick');
 await rejects(()=>q('select api.list_event_preparation_suggestions($1,$2)',[event,'focus']),'42501');
 await as(outsider);
 await rejects(()=>q('select api.get_event_preparation($1)',[event]),'42501','outsider cannot read');
 await as(leader);
 await db.exec(`update core.events set archived_at=now() where id='${event}'`);
 await rejects(()=>save(id(31),'focus','Arkiverat'),'42501','archived event is read-only');
 await db.exec(`update core.events set archived_at=null where id='${event}'`);

 // --- Files and per-file visibility --------------------------------------
 const stage=(fileId,name,visibility,people=null)=>one('select api.stage_event_file($1,$2,$3,$4,$5,$6,$7) v',
  [event,fileId,name,'application/pdf',1000,visibility,people]);
 const upload=async fileId=>{
  const staged=await one('select object_key from core.event_files where id=$1',[fileId]);
  await db.query("insert into storage.objects values('event-files',$1,$2,'{\"size\":1000}')",[staged.object_key,leader]);
  return (await one('select api.finalize_event_file($1) v',[fileId])).v;
 };
 const leadersFile=id(100),allFile=id(101),selectedFile=id(102);
 const staged=(await stage(leadersFile,'Matchplan.pdf','leaders')).v;
 assert.deepEqual((await stage(leadersFile,'Matchplan.pdf','leaders')).v,staged,'stage retry returns same key');
 await rejects(()=>stage(leadersFile,'Annan.pdf','leaders'),'23505','file id cannot be reused for another file');
 await rejects(()=>q('select api.finalize_event_file($1)',[leadersFile]),'22023','finalize requires the uploaded object');
 await upload(leadersFile);
 await stage(allFile,'Träningsplan.pdf','participants');await upload(allFile);
 await rejects(()=>stage(id(103),'Tom.pdf','selected',[]),'22023','selected needs people');
 await rejects(()=>stage(id(103),'Fel.pdf','selected',[pForeign]),'22023','selected people must belong to the event');
 await stage(selectedFile,'Rehab.pdf','selected',[p1]);
 const beforeFinalize=async()=>{await as(player1);const n=(await one('select api.get_event_preparation($1) v',[event])).v.files.length;await as(leader);return n;};
 assert.equal(await beforeFinalize(),1,'staged files are invisible');
 await upload(selectedFile);
 const visible=async profile=>{await as(profile);const v=(await one('select api.get_event_preparation($1) v',[event])).v;await as(leader);return v.files.map(f=>f.name).sort();};
 const storageCount=async(profile,fileId)=>{
  const key=(await one('select object_key from core.event_files where id=$1',[fileId])).object_key;
  await as(profile);await db.exec('set role authenticated');
  try{return (await one('select count(*)::int n from storage.objects where name=$1',[key])).n;}
  finally{await db.exec('reset role');await as(leader);}
 };
 assert.deepEqual(await visible(leader),['Matchplan.pdf','Rehab.pdf','Träningsplan.pdf']);
 assert.deepEqual(await visible(player1),['Rehab.pdf','Träningsplan.pdf']);
 assert.deepEqual(await visible(player2),['Träningsplan.pdf']);
 assert.deepEqual(await visible(guardian),['Rehab.pdf','Träningsplan.pdf'],'guardian sees files selected for their child');
 assert.equal(await storageCount(player1,leadersFile),0,'storage RLS hides leader-only object');
 assert.equal(await storageCount(player2,selectedFile),0,'storage RLS hides unselected object');
 assert.equal(await storageCount(player1,selectedFile),1,'storage RLS allows selected person');
 assert.equal(await storageCount(outsider,allFile),0,'storage RLS hides from non-readers');
 await as(player2);
 await rejects(()=>q('select api.authorize_event_file($1)',[leadersFile]),'42501','known id does not grant access');
 assert.equal((await one('select api.authorize_event_file($1) v',[allFile])).v.expires_in_seconds,120);
 await rejects(()=>q("select api.set_event_file_visibility($1,'participants',null,2)",[leadersFile]),'42501');
 await as(leader);
 const leaderView=(await one('select api.get_event_preparation($1) v',[event])).v;
 assert.deepEqual(leaderView.files.find(f=>f.id===selectedFile).viewer_ids,[p1]);
 await as(player1);
 assert.deepEqual((await one('select api.get_event_preparation($1) v',[event])).v.files.find(f=>f.id===selectedFile).viewer_ids,[],'viewer list is leader-only');
 await as(leader);
 const moved=(await one("select api.set_event_file_visibility($1,'selected',$2,2) v",[selectedFile,[p2]])).v;
 assert.equal(moved.revision,3);
 await rejects(()=>q("select api.set_event_file_visibility($1,'leaders',null,2)",[selectedFile]),'40001','stale visibility change');
 assert.deepEqual(await visible(player1),['Träningsplan.pdf']);
 assert.deepEqual(await visible(player2),['Rehab.pdf','Träningsplan.pdf']);
 await q('select api.delete_event_file($1)',[allFile]);
 assert.deepEqual(await visible(player2),['Rehab.pdf']);
 assert.equal(await storageCount(player2,allFile),0,'deleted file object is unreadable');
 assert.equal((await one("select internal.actor_can_delete_event_file_object('event-files',object_key) v from core.event_files where id=$1",[allFile])).v,true);
 assert.ok((await one("select count(*)::int n from realtime.sent where topic=$1",['event:live:'+event])).n>0,'changes broadcast invalidations');
 for (const fn of ['api.get_event_preparation(uuid)','api.stage_event_file(uuid,uuid,text,text,bigint,text,uuid[])','api.authorize_event_file(uuid)'])
  assert.equal((await one(`select has_function_privilege('anon','${fn}','execute') v`)).v,false);
 console.log('PASS: preparation items, idempotent retries, conflicts, reorder, suggestions, note, read-only/outsider/archived, file staging, per-file visibility in RPC and storage RLS, guardian, deletion and realtime');

 // --- Matchläge on Match Space v2 ---------------------------------------
 await as(player1);
 await rejects(()=>q('select api.configure_match_periods_v2($1,$2,$3)',[id(200),event,[30,30,30]]),'42501','read-only cannot configure');
 await as(leader);
 await rejects(()=>q('select api.configure_match_periods_v2($1,$2,$3)',[id(201),event,[45,45,45,45,45,45,45,45,45]]),'22023');
 await q('select api.configure_match_periods_v2($1,$2,$3)',[id(202),event,[30,30,30]]);
 await db.exec(`insert into core.attendance_facts values('${club}','${event}','${p1}','present'),('${club}','${event}','${p2}','absent')`);
 const frozen=(await one("select api.freeze_match_roster($1,$2,'initial') v",[id(203),event])).v;
 assert.equal(frozen.member_count,1,'walk-in attendance forms the squad without callups');
 await q("select api.transition_match_clock_v2($1,$2,'start')",[id(204),event]);
 const goal=()=>one("select api.record_match_event_v2($1,$2,10,'goal','us',$3,null,'{}') v",[id(205),event,p1]);
 const goalId=(await goal()).v;
 assert.equal((await goal()).v,goalId,'retrying the same command does not duplicate the goal');
 await rejects(()=>q("select api.record_match_event_v2($1,$2,11,'goal','us',$3,null,'{}')",[id(206),event,p2]),'22023','scorer must be in squad');
 await q("select api.record_match_event_v2($1,$2,17,'goal','opponent',null,null,'{}')",[id(207),event]);
 let snap=(await one('select api.get_match_v2_snapshot($1) v',[event])).v;
 assert.deepEqual([snap.projection.score_us,snap.projection.score_opponent],[1,1]);
 assert.deepEqual(snap.roster.map(r=>r.name),['Erik Andersson']);
 assert.equal(snap.people[p1],'Erik Andersson');
 assert.deepEqual(snap.clock.period_minutes,[30,30,30]);
 assert.equal(snap.can_manage,true);
 await q('select api.correct_match_event_v2($1,$2,12,$3,null,null)',[id(208),goalId,p1]);
 await rejects(()=>q('select api.correct_match_event_v2($1,$2,12,$3,null,null)',[id(209),goalId,p2]),'22023','corrected scorer must be in squad');
 const opponentGoal=(await one("select id from core.match_facts where side='opponent' and fact_type='goal'")).id;
 await rejects(()=>q('select api.correct_match_event_v2($1,$2,18,$3,null,null)',[id(210),opponentGoal,p1]),'22023','opponent goals have no scorer');
 await q('select api.adjust_match_clock_v2($1,$2,600)',[id(211),event]);
 const elapsed=(await one('select extract(epoch from now()-match_started_at)::int-paused_seconds v from core.match_workspaces')).v;
 assert.ok(Math.abs(elapsed-600)<=1,'clock correction sets the displayed time');
 await q("select api.record_match_note_v2($1,$2,20,'Domarbyte')",[id(212),event]);
 await rejects(()=>q("select api.record_match_note_v2($1,$2,20,'  ')",[id(213),event]),'22023');
 await q('select api.void_match_event_v2($1,$2)',[id(214),opponentGoal]);
 snap=(await one('select api.get_match_v2_snapshot($1) v',[event])).v;
 assert.deepEqual([snap.projection.score_us,snap.projection.score_opponent],[1,0],'score follows active goals');
 assert.equal(snap.facts.find(f=>f.id===goalId).minute,12);
 await q("select api.transition_match_period_v2($1,$2,'end')",[id(215),event]);
 await q("select api.adjust_match_clock_v2($1,$2,1800)",[id(216),event]);
 await q("select api.transition_match_period_v2($1,$2,'resume')",[id(217),event]);
 await rejects(()=>q('select api.configure_match_periods_v2($1,$2,$3)',[id(218),event,[45]]),'23514','cannot shrink below current period');
 await q('select api.complete_match_v2($1,$2,90)',[id(219),event]);
 await q('select api.correct_match_event_v2($1,$2,14,$3,null,null)',[id(220),goalId,p1]);
 await rejects(()=>q('select api.void_match_event_v2($1,$2)',[id(221),goalId]),'23514','voiding after full time changes the result');
 assert.equal((await one("select count(*)::int n from audit.match_fact_versions where fact_id=$1 and action='edited'",[goalId])).n,2);
 await as(player1);
 assert.equal((await one('select api.get_match_v2_snapshot($1) v',[event])).v.can_manage,false);
 await rejects(()=>q('select api.adjust_match_clock_v2($1,$2,60)',[id(222),event]),'42501');
 await as(leader);
 assert.ok((await one("select count(*)::int n from realtime.sent where topic=$1 and payload->>'event_id'=$2",['event:live:'+event,event])).n>10);
 console.log('PASS: match format, walk-in squad freeze, idempotent goals, squad validation, corrections incl. after full time, clock correction, notes, void, periods and permissions');
} finally {await db.close();}
