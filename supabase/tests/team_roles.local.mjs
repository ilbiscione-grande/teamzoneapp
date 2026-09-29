// Isolated PostgreSQL tests for TEAM-09 team roles: no hosted database.
// Uses the real leader-capability and player-context triggers.
// Run: node supabase/tests/team_roles.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');
const db=new PGlite();
const club='10000000-0000-4000-8000-000000000001',t1='20000000-0000-4000-8000-000000000001',t2='20000000-0000-4000-8000-000000000002';
const func='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',leader='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',outsider='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const pF='40000000-0000-4000-8000-000000000001',pL='40000000-0000-4000-8000-000000000002',
 pP='40000000-0000-4000-8000-000000000003',pQ='40000000-0000-4000-8000-000000000004';
const key=n=>'90000000-0000-4000-8000-'+String(n).padStart(12,'0');
const as=id=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
const one=async(sql,params=[])=>(await db.query(sql,params)).rows[0];
const rejects=async(fn,code,message)=>{await db.exec('savepoint r');try{await assert.rejects(fn,e=>e.code===code,message);}finally{await db.exec('rollback to r');}};
const active=(person,team,role)=>one(`select count(*)::int n from core.assignments where club_person_id=$1 and team_id=$2 and role_package=$3 and state='active'`,[person,team,role]).then(r=>r.n);
try {
 await db.exec(`
 create role anon;create role authenticated;
 create schema core;create schema internal;create schema api;create schema audit;create schema auth;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
 create table internal.command_deduplication(actor_profile_id uuid,idempotency_key uuid,command_type text,result jsonb,unique(actor_profile_id,idempotency_key,command_type));
 create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,aggregate_id uuid,aggregate_revision bigint,metadata jsonb);
 create table core.teams(id uuid primary key,club_id uuid,name text,status text default 'active',revision bigint not null default 1,unique(id,club_id));
 create table core.club_people(id uuid primary key,club_id uuid,display_name text,status text default 'active',unique(id,club_id));
 create table core.person_account_links(club_id uuid,club_person_id uuid,profile_id uuid,state text);
 create table core.assignments(id uuid primary key default gen_random_uuid(),club_id uuid not null,team_id uuid,club_person_id uuid not null,
  role_package text not null,state text not null default 'pending',starts_at timestamptz not null,ends_at timestamptz,created_at timestamptz default now(),
  created_by uuid,revision bigint not null default 1,check(ends_at is null or ends_at>starts_at));
 create table core.capability_grants(id uuid primary key default gen_random_uuid(),club_id uuid,assignment_id uuid references core.assignments(id),
  capability text,scope_type text,scope_id uuid,starts_at timestamptz,ends_at timestamptz,created_by uuid,unique(assignment_id,capability,scope_type,scope_id));
 create table core.team_assignments(id uuid primary key default gen_random_uuid(),club_id uuid,team_id uuid,club_person_id uuid,
  state text not null default 'active',starts_at timestamptz not null,ends_at timestamptz,created_by uuid,ended_by uuid,revision bigint not null default 1);
 create function internal.actor_owns_club_person(target_club_id uuid,target_club_person_id uuid) returns boolean language sql stable as
  $$select exists(select 1 from core.person_account_links link where link.profile_id=auth.uid() and link.club_id=target_club_id
   and link.club_person_id=target_club_person_id and link.state='active')$$;
 grant usage on schema api,internal,auth to authenticated;
 insert into core.teams values('${t1}','${club}','F2012'),('${t2}','${club}','F2013');
 insert into core.club_people values('${pF}','${club}','Frida Funktionär'),('${pL}','${club}','Lars Ledare'),
  ('${pP}','${club}','Pelle Spelare'),('${pQ}','${club}','Quinn Hemma');
 insert into core.person_account_links values('${club}','${pF}','${func}','active'),('${club}','${pL}','${leader}','active');
 `);
 // The real capability check (club/team grants, active assignment).
 const cap=read('supabase/migrations/20260831153810_team_leader_scoped_roster_management.sql');
 await db.exec(cap.slice(cap.indexOf('create or replace function internal.actor_has_capability('),cap.indexOf('revoke all on function internal.actor_has_capability')));
 const bundle=read('supabase/migrations/20260920172500_auth04_materialize_leader_capability_bundle.sql');
 await db.exec(bundle.slice(0,bundle.indexOf('insert into internal.migration_provenance')));
 const sync=read('supabase/migrations/20260920163500_team08_sync_player_context_with_roster.sql');
 await db.exec(sync.slice(0,sync.indexOf('-- Reconcile pre-trigger data')));
 await db.exec(`
 insert into core.assignments(id,club_id,team_id,club_person_id,role_package,state,starts_at)
 values('50000000-0000-4000-8000-000000000001','${club}','${t1}','${pF}','club_functionary','active',now()-interval '1 day');
 insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at)
 values('${club}','50000000-0000-4000-8000-000000000001','club.memberships.manage','club','${club}',now()-interval '1 day');
 insert into core.assignments(club_id,team_id,club_person_id,role_package,state,starts_at)
 values('${club}','${t1}','${pL}','leader','active',now()-interval '1 day');
 insert into core.team_assignments(club_id,team_id,club_person_id,starts_at) values('${club}','${t2}','${pP}',now()-interval '1 day'),
  ('${club}','${t1}','${pQ}',now()-interval '1 day');
 `);
 await db.exec(read('supabase/migrations/20260929090000_team09_team_roles.sql'));
 await db.exec('begin');
 const call=(fn,args)=>one(`select api.${fn}(${args.map((_,i)=>'$'+(i+1)).join(',')}) v`,args).then(r=>r.v);
 await as(func);
 if(process.argv.includes('--details')) {
  const {testTeamPersonDetails}=await import('./team_person_details.local.mjs');
  await testTeamPersonDetails(db,read,{club,t1,t2,func,leader,outsider,pF,pL,pP,pQ});
 }
 assert.equal(await active(pP,t2,'player'),1,'home period creates the player context');
 const candidates=await call('list_club_leader_candidates',[club,t2]);
 assert.deepEqual(candidates.map(c=>c.name),['Frida Funktionär','Lars Ledare']);
 assert.equal(candidates.find(c=>c.person_id===pF).is_self,true);
 // Add myself as leader, then an existing club leader (retry is a no-op).
 await call('add_team_role',[club,t2,pF,'leader',key(1)]);
 assert.equal(await active(pF,t2,'leader'),1);
 assert.equal((await one(`select count(*)::int n from core.capability_grants g join core.assignments a on a.id=g.assignment_id
  where a.club_person_id=$1 and a.team_id=$2 and g.capability='event.manage' and g.scope_id=$2`,[pF,t2])).n,1,'leader bundle materialized');
 await call('add_team_role',[club,t2,pL,'leader',key(2)]);
 await call('add_team_role',[club,t2,pL,'leader',key(2)]);
 await call('add_team_role',[club,t2,pL,'leader',key(3)]);
 assert.equal(await active(pL,t2,'leader'),1,'no duplicate leader role');
 assert.deepEqual(await call('list_club_leader_candidates',[club,t2]),[]);
 // Player -> leader ends the home period and the player context.
 await call('change_team_role',[club,t2,pP,'player','leader',key(4)]);
 assert.equal(await active(pP,t2,'player'),0);
 assert.equal(await active(pP,t2,'leader'),1);
 assert.equal((await one(`select state from core.team_assignments where club_person_id=$1`,[pP])).state,'ended');
 await rejects(()=>call('change_team_role',[club,t2,pP,'player','leader',key(5)]),'40001','stale from-role');
 // Leader -> player creates a home period here.
 await call('change_team_role',[club,t2,pL,'leader','player',key(6)]);
 assert.equal(await active(pL,t2,'leader'),0);
 assert.equal(await active(pL,t2,'player'),1);
 await rejects(()=>call('change_team_role',[club,t2,pF,'leader','player',key(7)]),'23514','cannot demote own leader role');
 await rejects(()=>call('remove_team_role',[club,t2,pF,'leader',key(8)]),'23514','cannot remove own leader role');
 await rejects(()=>call('add_team_role',[club,t2,pQ,'player',key(9)]),'23514','player with home in another team');
 await rejects(()=>call('add_team_role',[club,t2,pQ,'club_functionary',key(10)]),'22023','no club mandate here');
 await call('add_team_role',[club,t2,pQ,'leader',key(11)]);
 await call('remove_team_role',[club,t2,pQ,'leader',key(12)]);
 assert.equal(await active(pQ,t2,'leader'),0);
 assert.equal(await active(pQ,t1,'player'),1,'other team untouched');
 const listed=await call('list_team_roles',[club,t2]);
 assert.equal(listed.can_manage,true);
 assert.deepEqual(listed.roles.map(r=>[r.name,r.role]),[['Frida Funktionär','leader'],['Pelle Spelare','leader'],['Lars Ledare','player']]);
 assert.equal((await one(`select count(*)::int n from audit.command_events where command_type like 'roster.role.%'`)).n,7);
 // The new leader can now manage team 2 roles; outsiders cannot.
 await as(leader);
 await rejects(()=>call('add_team_role',[club,t2,pQ,'leader',key(13)]),'42501','ended leader role has no rights');
 await as(outsider);
 await rejects(()=>call('list_team_roles',[club,t2]),'42501');
 await rejects(()=>call('add_team_role',[club,t2,pQ,'leader',key(14)]),'42501');
 assert.equal((await one("select has_function_privilege('anon','api.add_team_role(uuid,uuid,uuid,text,uuid)','execute') v")).v,false);
 console.log('PASS: add self/club leader, idempotency, capability bundle, player<->leader changes, own-role guard, home-team guard, remove, list, audit and authorization');
} finally {await db.close();}
