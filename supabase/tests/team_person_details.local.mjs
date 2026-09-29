import assert from 'node:assert/strict';

// Titles and positions (descriptive only). Runs inside the team_roles
// transaction and rolls itself back so the role tests start unchanged.
// State on entry: t1 has pF (club functionary), pL (leader), pQ (player);
// t2 has pP (player).
export async function testTeamPersonDetails(db, read, {club,t1,t2,func,leader,outsider,pF,pL,pP,pQ}) {
 await db.exec(read('supabase/migrations/20260929101319_team_person_functions_positions.sql'));
 await db.exec(read('supabase/migrations/20260929140000_team_titles_positions_by_sport.sql'));
 await db.exec('savepoint details_suite');
 const one=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
 const as=id=>db.query("select set_config('request.jwt.claim.sub',$1,true)",[id]);
 const key=n=>'91000000-0000-4000-8000-'+String(n).padStart(12,'0');
 const saveV1=(team,person,titles,positions,rev,n)=>one(
  'select api.set_team_person_details($1,$2,$3,$4::text[],$5::text[],$6,$7) v',
  [club,team,person,titles,positions,rev,key(n)]).then(r=>r.v);
 const save=(team,person,titles,positions,customTitles,customPositions,rev,n)=>one(
  'select api.set_team_person_details_v2($1,$2,$3,$4::text[],$5::text[],$6::text[],$7::text[],$8,$9) v',
  [club,team,person,titles,positions,customTitles,customPositions,rev,key(n)]).then(r=>r.v);
 const details=async(team,person)=>(await one('select api.list_team_roles($1,$2) v',[club,team])).v
  .roles.find(r=>r.person_id===person);
 const rejects=async(fn,code,message)=>{await db.exec('savepoint details_test');try {
  await assert.rejects(fn,e=>e.code===code&&(!message||e.message===message),message);
 } finally {await db.exec('rollback to details_test');}};
 await as(func);
 const assignmentsBefore=(await one('select count(*)::int n from core.assignments')).n;
 const grantsBefore=(await one('select count(*)::int n from core.capability_grants')).n;
 await db.exec('set local role authenticated');
 // Titles belong to leader roles, positions to player roles.
 assert.equal(await saveV1(t1,pF,['head_coach','contact_person'],[],0,1),1,'own titles via v1');
 assert.equal(await saveV1(t1,pF,['head_coach','contact_person'],[],0,1),1,'retry idempotent');
 await rejects(()=>saveV1(t1,pF,[],['defender'],1,2),'23514','positions_need_player_role');
 await rejects(()=>save(t2,pP,['team_manager'],[],[],[],0,3),'23514','titles_need_leader_role');
 await rejects(()=>save(t2,pP,[],[],['Materialare'],[],0,3),'23514','titles_need_leader_role');
 // Two levels plus the team's own labels.
 assert.equal(await save(t2,pP,[],['defender','centre_back'],[],[' Libero ','Libero'],0,4),1);
 let pp=await details(t2,pP);
 assert.deepEqual(pp.positions,['centre_back','defender']);
 assert.deepEqual(pp.custom_positions,['Libero'],'trimmed and deduplicated');
 const list=(await one('select api.list_team_roles($1,$2) v',[club,t2])).v;
 assert.equal(list.sport,'football');
 assert.deepEqual(list.position_catalog.filter(p=>p.level==='general').map(p=>p.key),['goalkeeper','defender','midfielder','forward']);
 assert.equal(list.position_catalog.find(p=>p.key==='striker').parent,'forward');
 await rejects(()=>save(t2,pP,[],['hb_pivot'],[],[],1,5),'23514','invalid_position');
 await rejects(()=>save(t2,pP,[],[],[],['x'.repeat(41)],1,6),'23514');
 await rejects(()=>save(t2,pP,[],[],[],['a','b','c','d','e','f'],1,7),'23514');
 await rejects(()=>save(t2,pP,[],[],[],[],0,8),'40001','stale_revision');
 // v1 keeps custom labels it does not know about.
 assert.equal(await save(t1,pF,['head_coach'],[],['Ungdomsansvarig'],[],1,9),2);
 assert.equal(await saveV1(t1,pF,['team_manager'],[],2,10),3);
 assert.deepEqual((await details(t1,pF)).custom_titles,['Ungdomsansvarig']);
 // Changing sport drops catalog positions that no longer exist; custom stays.
 assert.equal((await one('select api.set_team_sport($1,$2,$3,$4) v',[club,t2,'handball',key(11)])).v,'handball');
 pp=await details(t2,pP);
 assert.deepEqual(pp.positions,[]);
 assert.deepEqual(pp.custom_positions,['Libero']);
 assert.equal(await save(t2,pP,[],['hb_backcourt','hb_left_back'],[],['Libero'],pp.details_revision,12),pp.details_revision+1);
 assert.equal((await one('select api.list_team_roles($1,$2) v',[club,t2])).v.position_catalog.find(p=>p.key==='hb_left_back').parent,'hb_backcourt');
 await rejects(()=>one('select api.set_team_sport($1,$2,$3,$4) v',[club,t2,'curling',key(13)]),'22023');
 await db.exec('reset role');
 assert.equal((await one('select count(*)::int n from core.assignments')).n,assignmentsBefore);
 assert.equal((await one('select count(*)::int n from core.capability_grants')).n,grantsBefore,'labels grant no permissions');
 // Labels follow the role: player -> leader clears positions, leader removal clears titles.
 await db.exec('set local role authenticated');
 await one('select api.change_team_role($1,$2,$3,$4,$5,$6) v',[club,t2,pP,'player','leader',key(14)]);
 pp=await details(t2,pP);
 assert.deepEqual([pp.positions,pp.custom_positions],[[],[]],'positions cleared with the player role');
 assert.equal(await save(t2,pP,['assistant_coach'],[],['Fystränare U13'],[],pp.details_revision,15),pp.details_revision+1);
 await one('select api.remove_team_role($1,$2,$3,$4,$5) v',[club,t2,pP,'leader',key(16)]);
 await db.exec('reset role');
 const stored=await one('select functions,custom_titles from core.team_person_details where team_id=$1 and club_person_id=$2',[t2,pP]);
 assert.deepEqual([stored.functions,stored.custom_titles],[[],[]],'titles cleared with the leader role');
 // Boundaries.
 await db.exec('set local role authenticated');
 await rejects(()=>save(t1,pP,[],['goalkeeper'],[],[],0,17),'42501','not_found');
 await as(leader);
 await rejects(()=>save(t2,pQ,[],[],[],[],0,18),'42501');
 await as(outsider);
 await rejects(()=>save(t1,pL,['contact_person'],[],[],[],0,19),'42501');
 await rejects(()=>one('select api.set_team_sport($1,$2,$3,$4) v',[club,t1,'handball',key(20)]),'42501');
 await db.exec('reset role');
 await as(func);
 assert.equal((await one("select has_table_privilege('authenticated','core.team_person_details','INSERT') v")).v,false);
 assert.equal((await one("select has_table_privilege('authenticated','core.sport_positions','SELECT') v")).v,false);
 for (const fn of ['api.set_team_person_details_v2(uuid,uuid,uuid,text[],text[],text[],text[],bigint,uuid)','api.set_team_sport(uuid,uuid,text,uuid)'])
  assert.equal((await one(`select has_function_privilege('anon','${fn}','EXECUTE') v`)).v,false);
 assert.ok((await one("select count(*)::int n from audit.command_events where command_type like 'team.person_details.%'")).n>=5);
 await db.exec('rollback to details_suite');
 console.log('PASS: titles need leader role, positions need player role, two-level catalog, custom labels, sport switch, v1 compatibility, clearing on role end, revisions, idempotency, boundaries and no permission escalation');
}
