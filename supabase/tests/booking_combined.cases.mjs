import assert from 'node:assert/strict';
export async function checkCombined({db,call,fails,owner,friend,coach,stranger}) {
 const org=await call(owner,"select api.create_booking_organization('Combined verification','club',null)");
 await db.query("insert into core.booking_members values($1,$2,'booker',now())",[org,friend]);
 const resource=(name,extra={})=>call(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[org,JSON.stringify({name,category:'pitch',ownership_kind:'owned',timezone:'Europe/Stockholm',...extra})]);
 const uuid=()=>db.query('select gen_random_uuid() id').then(r=>r.rows[0].id);
 const pitch=await resource('Combined pitch'),bus=await resource('Combined bus',{category:'vehicle'}),locker=await resource('Combined locker',{requires_approval:true}),camera=await resource('Combined camera'),other=await resource('Combined manual');
 const addHours=(s,h)=>new Date(new Date(s).getTime()+h*3600e3).toISOString();
 const row=id=>db.query('select * from core.booking_bookings where id=$1',[id]).then(r=>r.rows[0]);
 const preview=(who,id,scope,s,e,add=[],remove=[])=>call(who,'select api.preview_booking_change($1,$2,$3,$4,$5::uuid[],$6::uuid[])',[id,scope,s,e,add,remove]);
 const payload=p=>({target_booking_id:p.target_booking_id,change_scope:p.scope,new_starts_at:p.new_starts_at,new_ends_at:p.new_ends_at,add_resource_ids:p.add_resource_ids,remove_resource_ids:p.remove_resource_ids,expected_plan:p});
 const save=async(who,p,key=null)=>call(who,"select api.execute_booking_command($1,'update_booking',$2::jsonb,null)",[key??await uuid(),JSON.stringify(payload(p))]);
 const commandFail=async(who,p,pattern)=>fails(who,"select api.execute_booking_command($1,'update_booking',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(p))],pattern);
 const start=new Date(Date.now()+1400*86400e3).toISOString(),end=addHours(start,1);
 const g=await call(friend,'select api.create_booking_group($1::uuid[],$2,$3,null,null,null,null,false)',[[pitch,bus],start,end]);
 let members=(await db.query('select * from core.booking_bookings where group_id=$1',[g.group_id])).rows;
 const anchor=members.find(b=>b.resource_id===pitch),oldBus=members.find(b=>b.resource_id===bus);
 await db.query("update core.booking_bookings set starts_at=starts_at-interval '30 minutes',ends_at=ends_at+interval '15 minutes',revision=revision+1 where id=$1",[oldBus.id]);
 // A busy added resource at the OLD time must not prevent a valid combined move.
 const blockOld=await call(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[locker,start,end]);
 let p=await preview(friend,anchor.id,'booking',addHours(start,3),addHours(end,3),[locker],[pitch]);
 assert.deepEqual(p.conflicts,[]);assert.equal(p.final_bookings.length,2);
 assert.equal(new Date(p.contexts[0].add[0].starts_at).toISOString(),addHours(start,3));
 assert.equal(new Date(p.contexts[0].keep[0].starts_at).toISOString(),addHours(start,2.5));
 await fails(stranger,'select api.preview_booking_change($1,\'booking\',$2,$3,$4::uuid[],$5::uuid[])',[anchor.id,addHours(start,3),addHours(end,3),[locker],[pitch]],/not_allowed/);
 const blockNew=await call(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[locker,addHours(start,3),addHours(end,3)]);
 const before=(await db.query('select * from core.booking_bookings where group_id=$1 order by id',[g.group_id])).rows;
 await commandFail(friend,p,/booking_change_conflicts/);
 assert.deepEqual((await db.query('select * from core.booking_bookings where group_id=$1 order by id',[g.group_id])).rows,before);
 await call(owner,'select api.cancel_booking($1)',[blockNew.id]);
 const key=await uuid();await save(friend,p,key);await save(friend,p,key);
 assert.equal((await row(anchor.id)).status,'cancelled');assert.equal(new Date((await row(oldBus.id)).starts_at).toISOString(),addHours(start,2.5));
 members=(await db.query("select * from core.booking_bookings where group_id=$1 and status in('pending','confirmed')",[g.group_id])).rows;
 assert.equal(members.length,2);const added=members.find(b=>b.resource_id===locker);assert.equal(added.status,'pending');assert.equal(added.booked_by,friend);
 assert.equal((await db.query("select count(*)::int n from core.booking_notifications where booking_id=$1 and kind='requested'",[added.id])).rows[0].n,1);
 p=await preview(friend,oldBus.id,'booking',addHours(start,2.5),addHours(end,3.25));assert.equal(p.change_count,0);await commandFail(friend,p,/booking_change_no_change/);
 p=await preview(friend,oldBus.id,'booking',addHours(start,4),addHours(end,4),[camera]);
 await db.query('update core.booking_resources set revision=revision+1 where id=$1',[camera]);await commandFail(friend,p,/stale_revision/);
 await call(owner,'select api.decide_booking($1,true)',[added.id]);
 const approvalResource=await resource('Combined extra approval',{requires_approval:true});
 const requestsBefore=(await db.query("select count(*)::int n from core.booking_notifications where organization_id=$1 and kind='requested'",[org])).rows[0].n;
 p=await preview(friend,oldBus.id,'booking',addHours(start,5),addHours(end,5),[approvalResource]);await save(friend,p);
 assert.equal((await db.query("select count(*)::int n from core.booking_notifications where organization_id=$1 and kind='requested'",[org])).rows[0].n,requestsBefore+1,'one group approval request covers both moved and newly added approval resources');
 // Parent-to-child replacement frees the removed root before claiming a child.
 const child=await resource('Combined quarter',{parent_resource_id:pitch});
 p=await preview(friend,oldBus.id,'booking',addHours(start,6),addHours(end,6),[child],[locker]);assert.deepEqual(p.conflicts,[]);await save(friend,p);
 p=await preview(friend,oldBus.id,'booking',addHours(start,7),addHours(end,7),[pitch]);assert.ok(p.conflicts.some(c=>c.reason==='resource_busy'));await commandFail(friend,p,/booking_change_conflicts/);
 // All/forward moves include manually changed resource occurrences, while set
 // edits preserve those exceptions and prior cancellations. Wall clock across DST.
 const series=await call(friend,"select api.create_booking_series($1,'{7}'::smallint[],1::smallint,'2032-03-14','2032-04-11','18:00','19:00','Europe/Stockholm',null,null,null,false)",[pitch]);
 let roots=(await db.query('select * from core.booking_bookings where series_id=$1 order by series_sequence',[series.series_id])).rows;
 await db.query('update core.booking_bookings set resource_id=$2,revision=revision+1 where id=$1',[roots[1].id,other]);
 p=await preview(friend,roots[3].id,'series_all',addHours(roots[3].starts_at,1),addHours(roots[3].ends_at,1),[bus],[pitch]);
 assert.equal(p.contexts.length,4);assert.equal(p.selection.unchanged_contexts.length,1);assert.equal(p.timing.bookings.length,5);assert.deepEqual(p.conflicts,[]);await save(friend,p);
 let all=(await db.query('select b.*,to_char(b.starts_at at time zone \'Europe/Stockholm\',\'HH24:MI\') local from core.booking_bookings b where series_id=$1 order by series_sequence,resource_id',[series.series_id])).rows;
 assert.ok(all.filter(b=>b.status==='confirmed').every(b=>b.local==='19:00'));
 assert.equal(all.find(b=>b.id===roots[1].id).resource_id,other);
 let bus4=all.find(b=>b.series_sequence===4&&b.resource_id===bus);
 const prefix=all.filter(b=>b.series_sequence<4);
 p=await preview(friend,bus4.id,'series_forward',addHours(bus4.starts_at,1),addHours(bus4.ends_at,1),[camera],[bus]);assert.equal(p.contexts.length,2);await save(friend,p);
 all=(await db.query('select b.*,to_char(b.starts_at at time zone \'Europe/Stockholm\',\'HH24:MI\') local from core.booking_bookings b where series_id=$1 order by series_sequence,resource_id',[series.series_id])).rows;
 assert.deepEqual(all.filter(b=>b.series_sequence<4),prefix);assert.ok(all.filter(b=>b.series_sequence>=4&&b.status==='confirmed').every(b=>b.local==='20:00'));
 // Two new rows colliding with each other are rejected before touching time.
 const lastCamera=all.find(b=>b.series_sequence===5&&b.resource_id===camera);
 p=await preview(friend,lastCamera.id,'booking',addHours(lastCamera.starts_at,1),addHours(lastCamera.ends_at,1),[pitch,child],[camera]);assert.ok(p.conflicts.length);await commandFail(friend,p,/booking_change_conflicts/);
 for(const [first,last,s,e] of [['2032-03-21','2032-03-28','2032-03-21T01:30:00Z','2032-03-21T02:30:00Z'],['2032-10-24','2032-10-31','2032-10-24T00:30:00Z','2032-10-24T00:45:00Z']]) {
  const dst=await call(friend,"select api.create_booking_series($1,'{7}'::smallint[],1::smallint,$2,$3,'18:00','19:00','Europe/Stockholm',null,null,null,false)",[pitch,first,last]);
  const id=(await db.query('select id from core.booking_bookings where series_id=$1 and series_sequence=1',[dst.series_id])).rows[0].id;
  await fails(friend,"select api.preview_booking_change($1,'series_all',$2,$3,'{}'::uuid[],'{}'::uuid[])",[id,s,e],/forward_invalid_local_time/);
 }
 // Event commands must move the activity and ALL its bookings, including
 // independently grouped buffers, missing-source activities and zero-resource activities.
 const club=(await db.query("insert into core.clubs values(gen_random_uuid(),'Combined club') returning id")).rows[0].id;
 const team=(await db.query("insert into core.teams(id,club_id,name) values(gen_random_uuid(),$1,'Combined team') returning id",[club])).rows[0].id;
 const person=(await db.query("insert into core.club_people values(gen_random_uuid(),$1,'Combined coach') returning id",[club])).rows[0].id;
 await db.query("insert into core.person_account_links values($1,$2,$3,'active')",[coach,club,person]);await db.query("insert into core.assignments(club_id,team_id,club_person_id,role_package) values($1,$2,$3,'leader')",[club,team,person]);
 await db.query('update core.booking_organizations set teamzone_club_id=$2 where id=$1',[org,club]);
 const recurrence=await uuid(),events=[],eventRoots=[],separate=[];
 for(let i=0;i<4;i++) {
  const s=new Date(Date.now()+(1500+i*7)*86400e3).toISOString(),e=addHours(s,1);
  const id=(await db.query("insert into core.events(id,club_id,title,state,starts_at,ends_at,recurrence_id,occurrence_number,timezone) values(gen_random_uuid(),$1,'Combined activity','scheduled',$2,$3,$4,$5,'Europe/Stockholm') returning id",[club,s,e,recurrence,i+1])).rows[0].id;
  events.push(id);await db.query('insert into core.event_teams values($1,$2,$3)',[id,club,team]);
  if(i===3)continue;
  eventRoots[i]=await call(coach,'select api.create_booking($1,$2,$3,null,null,$4,$5)',[i===1?other:pitch,addHours(s,-.5),addHours(e,.25),team,id]);
  separate[i]=await call(coach,'select api.create_booking($1,$2,$3,null,null,$4,$5)',[camera,addHours(s,-1),addHours(e,2),team,id]);
 }
 const originalEvents=(await db.query('select * from core.events where recurrence_id=$1 order by occurrence_number',[recurrence])).rows;
 p=await preview(coach,eventRoots[2].id,'event_all',addHours(originalEvents[2].starts_at,2),addHours(originalEvents[2].ends_at,2),[bus],[pitch]);
 assert.equal(p.timing.events.length,4);assert.equal(p.contexts.length,2);assert.equal(p.selection.unchanged_contexts.length,2);assert.deepEqual(p.conflicts,[]);
 const c=p.contexts.find(c=>c.event_id===events[0]);assert.equal(new Date(c.add[0].starts_at).toISOString(),addHours(originalEvents[0].starts_at,1.5));
 await fails(friend,'select api.preview_booking_change($1,\'booking\',$2,$3,$4::uuid[],$5::uuid[])',[eventRoots[0].id,addHours(originalEvents[0].starts_at,1),addHours(originalEvents[0].ends_at,1),[],[]],/not_allowed|event_move_not_allowed/);
 await db.exec('savepoint denied_missing');await db.exec(`create or replace function internal.actor_can_manage_event(e uuid) returns boolean language sql stable as $$select auth.uid()='${coach}'::uuid and e<>'${events[3]}'::uuid$$;`);
 await fails(coach,'select api.preview_booking_change($1,\'event_all\',$2,$3,$4::uuid[],$5::uuid[])',[eventRoots[2].id,addHours(originalEvents[2].starts_at,2),addHours(originalEvents[2].ends_at,2),[bus],[pitch]],/event_move_not_allowed/);await db.exec('rollback to denied_missing');
 const ek=await uuid();await save(coach,p,ek);await save(coach,p,ek);
 const changedEvents=(await db.query('select * from core.events where recurrence_id=$1 order by occurrence_number',[recurrence])).rows;
 assert.ok(changedEvents.every((e,i)=>e.revision===2&&new Date(e.starts_at).toISOString()===addHours(originalEvents[i].starts_at,2)));
 assert.equal((await row(eventRoots[0].id)).status,'cancelled');assert.equal((await row(eventRoots[1].id)).resource_id,other);
 assert.equal(new Date((await row(separate[0].id)).starts_at).toISOString(),addHours(originalEvents[0].starts_at,1));
 let eventBus=(await db.query("select * from core.booking_bookings where event_id=$1 and resource_id=$2 and status='confirmed'",[events[2],bus])).rows[0];
 p=await preview(coach,eventBus.id,'event_forward',addHours(changedEvents[2].starts_at,1),addHours(changedEvents[2].ends_at,1),[locker],[bus]);assert.equal(p.timing.events.length,2);assert.equal(p.contexts.length,1);await save(coach,p);
 assert.deepEqual((await db.query('select * from core.events where id=$1',[events[0]])).rows[0],changedEvents[0]);
 let eventLocker=(await db.query("select * from core.booking_bookings where event_id=$1 and resource_id=$2 and status='pending'",[events[2],locker])).rows[0];
 const beforeSingle=(await db.query('select * from core.events where id=$1',[events[2]])).rows[0];
 p=await preview(coach,eventLocker.id,'booking',addHours(beforeSingle.starts_at,1),addHours(beforeSingle.ends_at,1),[],[locker]);assert.equal(p.timing.events.length,1);await save(coach,p);
 assert.equal((await row(eventLocker.id)).status,'cancelled');assert.equal(new Date((await row(separate[2].id)).starts_at).toISOString(),addHours(beforeSingle.starts_at,0));
 console.log('combined changes: final-state conflicts, atomic rollback/replay, approvals, stale plans, hierarchy, all scopes, DST, exceptions, event buffers and missing-resource activities passed');
}
