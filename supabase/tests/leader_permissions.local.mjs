// Isolated PostgreSQL tests for TEAM-10 per-leader permissions: no hosted
// database. Real capability checks, leader bundle and player sync triggers,
// the Match Space v2 chain, Förberedelser, roles, titles and the permission
// migration; only event visibility and two long read functions are stubbed.
// Run: node supabase/tests/leader_permissions.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');
const segment=(text,from,to)=>{const a=text.indexOf(from),b=to?text.indexOf(to,a):text.length;
 if(a<0||b<0)throw new Error('segment '+from);return text.slice(a,b);};
const db=new PGlite();
const club='10000000-0000-4000-8000-000000000001',team='20000000-0000-4000-8000-000000000001';
const match='30000000-0000-4000-8000-000000000001',training='30000000-0000-4000-8000-000000000002';
const G='a0000000-0000-4000-8000-000000000007',pG='40000000-0000-4000-8000-000000000007';
const F='a0000000-0000-4000-8000-000000000001',H='a0000000-0000-4000-8000-000000000002',
 M='a0000000-0000-4000-8000-000000000003',A='a0000000-0000-4000-8000-000000000004',
 O='a0000000-0000-4000-8000-000000000005',X='a0000000-0000-4000-8000-000000000006';
const pF='40000000-0000-4000-8000-000000000001',pH='40000000-0000-4000-8000-000000000002',
 pM='40000000-0000-4000-8000-000000000003',pA='40000000-0000-4000-8000-000000000004',
 pO='40000000-0000-4000-8000-000000000005',pP='40000000-0000-4000-8000-000000000006';
let n=0;const key=()=>'90000000-0000-4000-8000-'+String(++n).padStart(12,'0');
const as=id=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
const one=async(sql,params=[])=>(await db.query(sql,params)).rows[0];
const val=async(sql,params=[])=>(await one(sql,params)).v;
const rejects=async(fn,code,message)=>{await db.exec('savepoint r');
 try{await assert.rejects(fn,e=>e.code===code&&(!message||e.message===message),`${code} ${message??''}`);}
 finally{await db.exec('rollback to r');}};
const catalog=['development.manage','event.attendance.correct_late','event.attendance.manage','event.logistics',
 'event.manage','event.squad.manage','match.live','match.plan','publication.manage','team.leaders.manage',
 'team.roster.manage','training.plan'];
const standard=['event.attendance.correct_late','event.attendance.manage','event.logistics','event.manage',
 'event.squad.manage','match.live','match.plan','team.roster.manage','training.plan'];
const teamManager=['event.attendance.correct_late','event.attendance.manage','event.logistics','event.manage',
 'event.squad.manage','match.live','publication.manage','team.roster.manage'];
const assistant=['development.manage','event.attendance.manage','event.logistics','match.live','match.plan','training.plan'];
try {
 await db.exec(`
 create role anon;create role authenticated;
 create schema core;create schema internal;create schema api;create schema audit;create schema auth;create schema storage;create schema realtime;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
 create table internal.command_deduplication(actor_profile_id uuid,idempotency_key uuid,command_type text,result jsonb,unique(actor_profile_id,idempotency_key,command_type));
 create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,aggregate_id uuid,aggregate_revision bigint,metadata jsonb);
 create table core.profiles(id uuid primary key);
 create table core.teams(id uuid primary key,club_id uuid,name text,status text default 'active',revision bigint not null default 1,unique(id,club_id));
 create table core.club_people(id uuid primary key,club_id uuid,display_name text,status text default 'active',unique(id,club_id));
 create table core.person_account_links(club_id uuid,club_person_id uuid,profile_id uuid,state text);
 create table core.assignments(id uuid primary key default gen_random_uuid(),club_id uuid not null,team_id uuid,club_person_id uuid not null,
  role_package text not null,state text not null default 'pending',starts_at timestamptz not null,ends_at timestamptz,created_at timestamptz default now(),
  created_by uuid,revision bigint not null default 1,check(ends_at is null or ends_at>starts_at));
 create table core.capability_grants(id uuid primary key default gen_random_uuid(),club_id uuid,assignment_id uuid references core.assignments(id),
  capability text,scope_type text,scope_id uuid,starts_at timestamptz,ends_at timestamptz,created_by uuid,revision bigint not null default 1,
  unique(assignment_id,capability,scope_type,scope_id),check(ends_at is null or ends_at>starts_at));
 create table core.team_assignments(id uuid primary key default gen_random_uuid(),club_id uuid,team_id uuid,club_person_id uuid,
  state text not null default 'active',starts_at timestamptz not null,ends_at timestamptz,created_by uuid,ended_by uuid,revision bigint not null default 1);
 create table core.guardian_relations(club_id uuid,guardian_person_id uuid,child_person_id uuid,state text,starts_at timestamptz,ends_at timestamptz);
 create table core.events(id uuid primary key,club_id uuid,owning_team_id uuid,event_type text,state text,archived_at timestamptz,
  starts_at timestamptz default now(),ends_at timestamptz default now()+interval '2 hours',unique(id,club_id),unique(id,club_id,owning_team_id));
 create table core.event_teams(event_id uuid,club_id uuid,team_id uuid,relation text,capabilities text[] default '{}');
 create table core.callups(id uuid primary key default gen_random_uuid(),club_id uuid,event_id uuid,squad_revision_id uuid,
  club_person_id uuid,state text,sent_at timestamptz,unique(id,club_id));
 create table core.attendance_facts(club_id uuid,event_id uuid,club_person_id uuid,status text);
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(bucket_id text,name text,owner_id text,metadata jsonb);
 create table realtime.messages(extension text,topic text);
 create function realtime.topic() returns text language sql stable as $$select ''$$;
 create function realtime.send(payload jsonb,event text,topic text,private boolean) returns void language sql as $$select$$;
 create function internal.actor_can_read_event(uuid) returns boolean language sql stable as $$select auth.uid() is not null$$;
 create function internal.actor_owns_club_person(target_club_id uuid,target_club_person_id uuid) returns boolean language sql stable as
  $$select exists(select 1 from core.person_account_links link where link.profile_id=auth.uid() and link.club_id=target_club_id
   and link.club_person_id=target_club_person_id and link.state='active')$$;
 grant usage on schema api,internal,auth,core to authenticated;
 `);
 const cap=read('supabase/migrations/20260831153810_team_leader_scoped_roster_management.sql');
 await db.exec(segment(cap,'create or replace function internal.actor_has_capability(','revoke all on function internal.actor_has_capability'));
 await db.exec(segment(read('supabase/migrations/20260807224555_s03_event_calendar.sql'),
  'create function internal.actor_can_manage_event(','create function internal.assert_event_primary_team'));
 await db.exec(segment(read('supabase/migrations/20260827070512_cal03_shared_event_access.sql'),
  'create function internal.actor_can_manage_event_roster(','create or replace function internal.get_event_details_for_actor'));
 await db.exec(segment(read('supabase/migrations/20260920172500_auth04_materialize_leader_capability_bundle.sql'),
  'create or replace function internal.materialize_leader_capabilities_from_assignment','insert into internal.migration_provenance'));
 await db.exec(segment(read('supabase/migrations/20260920163500_team08_sync_player_context_with_roster.sql'),
  'create or replace function internal.sync_player_context_from_team_assignment','-- Reconcile pre-trigger data'));
 // Stand-ins for two long read functions; they carry the exact fragments the
 // migration patches, so a changed contract still fails the migration.
 await db.exec(`
 create function internal.get_match_report_for_actor(p_event_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
 begin return jsonb_build_object('can_edit',internal.actor_can_manage_event(p_event_id)); end$$;
 create function internal.get_event_details_for_actor(target_event_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
 declare event_row core.events%rowtype;actions text[]:=array[]::text[];
 begin
  select * into event_row from core.events where id=target_event_id;
  if internal.actor_can_manage_event(event_row.id) then actions:=actions||array['revise','cancel','complete'];end if;
  if internal.actor_can_manage_event_roster(event_row.id) then actions:=actions||array['manage_roster'];end if;
  return jsonb_build_object('caller_actions',to_jsonb(actions));
 end$$;
 insert into core.profiles values('${F}'),('${H}'),('${M}'),('${A}'),('${O}'),('${X}');
 insert into core.teams(id,club_id,name) values('${team}','${club}','F2012');
 insert into core.club_people(id,club_id,display_name) values('${pF}','${club}','Frida Funktionär'),('${pH}','${club}','Hanna Huvudtränare'),
  ('${pM}','${club}','Mats Lagledare'),('${pA}','${club}','Anna Assistent'),('${pO}','${club}','Olle Ledare'),('${pP}','${club}','Pelle Spelare');
 insert into core.person_account_links values('${club}','${pF}','${F}','active'),('${club}','${pH}','${H}','active'),
  ('${club}','${pM}','${M}','active'),('${club}','${pA}','${A}','active'),('${club}','${pO}','${O}','active');
 insert into core.assignments(id,club_id,team_id,club_person_id,role_package,state,starts_at)
 values('50000000-0000-4000-8000-000000000001','${club}','${team}','${pF}','club_functionary','active',now()-interval '1 day');
 insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at)
 values('${club}','50000000-0000-4000-8000-000000000001','club.memberships.manage','club','${club}',now()-interval '1 day'),
  ('${club}','50000000-0000-4000-8000-000000000001','event.manage','club','${club}',now()-interval '1 day');
 insert into core.assignments(club_id,team_id,club_person_id,role_package,state,starts_at)
 values('${club}','${team}','${pO}','leader','active',now()-interval '1 day');
 insert into core.profiles values('${G}');
 insert into core.club_people(id,club_id,display_name) values('${pG}','${club}','Gustav Funktionär');
 insert into core.person_account_links values('${club}','${pG}','${G}','active');
 insert into core.assignments(id,club_id,team_id,club_person_id,role_package,state,starts_at)
 values('50000000-0000-4000-8000-000000000009','${club}','${team}','${pG}','club_functionary','active',now()-interval '1 day');
 insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at)
 values('${club}','50000000-0000-4000-8000-000000000009','club.memberships.manage','club','${club}',now()-interval '1 day'),
  ('${club}','50000000-0000-4000-8000-000000000009','event.manage','team','${team}',now()-interval '1 day');
 insert into core.team_assignments(club_id,team_id,club_person_id,starts_at) values('${club}','${team}','${pP}',now()-interval '1 day');
 insert into core.events(id,club_id,owning_team_id,event_type,state) values('${match}','${club}','${team}','match','scheduled'),
  ('${training}','${club}','${team}','training','scheduled');
 insert into core.event_teams values('${match}','${club}','${team}','primary','{}'),('${training}','${club}','${team}','primary','{}');
 `);
 for (const file of ['20260815074741_s07_match_v2_adapter_foundation','20260815075030_s07_command_roster_projection_engine',
  '20260815075322_s07_fix_roster_result_binding','20260815075428_s07_fix_snapshot_cursor','20260815075650_s07_v2_mutation_contract',
  '20260815080102_s07_fix_reset_fact_versioning','20260815091054_s07_halftime_clock_anchor',
  '20260928150000_event_preparations_v1','20260928150100_match_mode_v1','20260929090000_team09_team_roles',
  '20260929101319_team_person_functions_positions','20260929140000_team_titles_positions_by_sport',
  '20260929160000_team_leader_permissions','20260929170000_club_admins_manage_leaders']) {
  await db.exec(read(`supabase/migrations/${file}.sql`));
 }
 await db.exec('begin');
 // A functionary whose event.manage is per team still administers leaders,
 // without event rights being widened to the whole club.
 await as(G);
 assert.equal(await val('select internal.actor_has_capability($1,$2,$3) v',[club,team,'team.leaders.manage']),true);
 assert.equal(await val('select internal.actor_has_capability($1,$2,$3) v',[club,'20000000-0000-4000-8000-000000000099','event.manage']),false);
 assert.equal((await val('select api.list_team_roles($1,$2) v',[club,team])).can_manage,true);
 const caps=person=>val('select internal.leader_panel_capabilities($1,$2,$3) v',[club,team,person]);
 const setPerms=(person,next,expected,template)=>val('select api.set_leader_permissions($1,$2,$3,$4,$5,$6,$7) v',
  [club,team,person,next,expected,template,key()]);
 const addRole=(person,role)=>val('select api.add_team_role($1,$2,$3,$4,$5) v',[club,team,person,role,key()]);
 const prep=(event,kind,label)=>val('select api.save_event_preparation_item($1,$2,$3,$4,null,0) v',[event,key(),kind,label]);
 const note=(event,body)=>val('select api.save_event_preparation_note($1,$2,0) v',[event,body]);
 const has=(fn,event)=>val(`select internal.${fn}($1) v`,[event]);

 // Rollout keeps behaviour: the old leader got the split capabilities, not leaders.manage.
 for (const c of ['event.squad.manage','event.attendance.manage','event.logistics','training.plan','match.plan','match.live'])
  assert.ok((await caps(pO)).includes(c),'backfilled '+c);
 assert.ok(!(await caps(pO)).includes('team.leaders.manage'));
 await as(O);
 await rejects(()=>addRole(pH,'leader'),'42501',null);
 // The functionary (club scope) holds every panel capability and creates the head coach.
 await as(F);
 await addRole(pH,'leader');
 assert.deepEqual(await caps(pH),standard,'new leaders get the standard set');
 await setPerms(pH,catalog,standard,'head_coach');
 assert.deepEqual(await caps(pH),catalog);
 // The head coach creates the team manager and the assistant and tailors them.
 await as(H);
 await addRole(pM,'leader');await addRole(pA,'leader');
 await setPerms(pM,teamManager,standard,'team_manager');
 await setPerms(pA,assistant,standard,'assistant_coach');
 assert.deepEqual(await caps(pM),teamManager);
 await rejects(()=>setPerms(pM,catalog,standard,null),'40001','stale_permissions');
 await rejects(()=>setPerms(pH,catalog.filter(c=>c!=='team.leaders.manage'),catalog,null),'23514','own_leaders_permission');
 await rejects(()=>setPerms(pM,['bogus.capability'],teamManager,null),'22023','invalid_permissions');
 // Team manager: squad, dates, logistics and match day; no training or tactics.
 await as(M);
 assert.equal(await has('actor_can_manage_squad',match),true);
 assert.equal(await has('actor_can_manage_event',match),true,'may move events');
 await prep(match,'material','Bollar');
 await rejects(()=>prep(training,'focus','Presspel'),'42501',null);
 await rejects(()=>note(match,'Pressa högt'),'42501',null);
 await val('select api.configure_match_periods_v2($1,$2,$3) v',[key(),match,[30,30]]);
 let details=await val('select internal.get_event_details_for_actor($1) v',[match]);
 assert.ok(details.caller_actions.includes('match_live'));
 assert.ok(!details.caller_actions.includes('match_plan'));
 const prepView=await val('select api.get_event_preparation($1) v',[match]);
 assert.deepEqual(prepView.permissions,{logistics:true,training:false,match:false});
 await rejects(()=>addRole(pP,'leader'),'42501',null);
 await rejects(()=>setPerms(pA,assistant,assistant,null),'42501',null);
 await rejects(()=>val('select api.list_club_leader_candidates($1,$2) v',[club,team]),'42501',null);
 let roles=await val('select api.list_team_roles($1,$2) v',[club,team]);
 assert.equal(roles.can_manage,false);
 assert.equal(roles.can_edit_details,true,'roster management still edits titles/positions');
 assert.equal(roles.roles.find(r=>r.person_id===pH).permissions,null,'permissions are only shown to those who manage them');
 await rejects(()=>db.query(`insert into core.assignments(club_id,team_id,club_person_id,role_package,state,starts_at)
  values('${club}','${team}','${pP}','leader','active',now())`),'42501','leaders_manage_required');
 // Assistant: training and tactics, match day; no callups or moving events.
 await as(A);
 assert.equal(await has('actor_can_manage_squad',match),false);
 assert.equal(await has('actor_can_manage_attendance',match),true);
 assert.equal(await has('actor_can_manage_event',match),false);
 await prep(training,'focus','Speluppbyggnad');
 await note(match,'Pressa högt');
 await prep(match,'task','Ta med västar');
 // Grants are limited to what the granter holds.
 await as(F);
 await setPerms(pA,[...assistant,'team.leaders.manage'].sort(),assistant,'custom');
 await as(A);
 // The assistant lacks publication.manage, so cannot take it away either.
 await rejects(()=>setPerms(pM,teamManager.filter(c=>c!=='publication.manage'),teamManager,null),'23514','not_grantable');
 await setPerms(pM,[...teamManager,'training.plan'].sort(),teamManager,'custom');
 assert.ok((await caps(pM)).includes('training.plan'),'granted what the granter holds');
 // The head coach sees everyone's permissions and what they may grant.
 await as(H);
 roles=await val('select api.list_team_roles($1,$2) v',[club,team]);
 assert.equal(roles.can_manage,true);
 assert.deepEqual(roles.grantable.slice().sort(),catalog);
 assert.equal(roles.roles.find(r=>r.person_id===pM).permission_template,'custom');
 assert.deepEqual(roles.roles.find(r=>r.person_id===pM).permissions,(await caps(pM)));
 // Removing a permission and re-granting it works (grant rows are reused).
 await setPerms(pM,teamManager,await caps(pM),'team_manager');
 await setPerms(pM,[...teamManager,'match.plan'].sort(),teamManager,'custom');
 assert.ok((await caps(pM)).includes('match.plan'));
 // Ending the leader role clears the template with the titles.
 await val('select api.remove_team_role($1,$2,$3,$4,$5) v',[club,team,pM,'leader',key()]);
 assert.equal((await one('select permission_template t from core.team_person_details where club_person_id=$1',[pM])).t,null);
 await as(M);
 assert.equal(await has('actor_can_manage_squad',match),false,'rights end with the role');
 await as(X);
 await rejects(()=>setPerms(pH,catalog,catalog,null),'42501',null);
 assert.equal((await one("select has_function_privilege('anon','api.set_leader_permissions(uuid,uuid,uuid,text[],text[],text,uuid)','execute') v")).v,false);
 assert.ok((await one("select count(*)::int n from audit.command_events where command_type='team.leader_permissions.updated.v1'")).n>=6);
 console.log('PASS: behaviour-preserving backfill, standard set, templates, head coach/team manager/assistant boundaries per area, own-permission and grant limits, stale guard, leader creation guard, role end, listing and privileges');
} finally {await db.close();}
