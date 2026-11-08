import assert from 'node:assert/strict';

export async function checkResourceSets({db,call,fails,owner,friend,coach,stranger}) {
 const org=await call(owner,"select api.create_booking_organization('Resource sets verification','club',null)");
 await db.query("insert into core.booking_members(organization_id,profile_id,role) values($1,$2,'booker'),($1,$3,'booker')",[org,friend,coach]);
 const resource=(name,extra={})=>call(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[org,JSON.stringify({name,category:'pitch',ownership_kind:'owned',timezone:'Europe/Stockholm',...extra})]);
 const uuid=()=>db.query('select gen_random_uuid() id').then(r=>r.rows[0].id);
 const preview=(who,id,scope,add=[],remove=[])=>call(who,'select api.preview_booking_resources($1,$2,$3::uuid[],$4::uuid[])',[id,scope,add,remove]);
 const payload=p=>({target_booking_id:p.target_booking_id,change_scope:p.scope,add_resource_ids:p.add_resource_ids,remove_resource_ids:p.remove_resource_ids,expected_plan:p});
 const save=async(who,p,key=null)=>call(who,"select api.execute_booking_command($1,'update_booking_resources',$2::jsonb,null)",[key??await uuid(),JSON.stringify(payload(p))]);
 const row=id=>db.query('select * from core.booking_bookings where id=$1',[id]).then(r=>r.rows[0]);
 const source=await resource('Set pitch');const bus=await resource('Set bus',{category:'vehicle',requires_approval:true});
 const camera=await resource('Set camera',{category:'equipment'});const locker=await resource('Set locker',{category:'locker_room'});const exception=await resource('Set manual pitch');
 const start=new Date(Date.now()+1100*86400e3).toISOString(),end=new Date(Date.now()+1100*86400e3+3600e3).toISOString();
 const original=await call(friend,'select api.create_booking($1,$2,$3,null,null,null,null)',[source,start,end]);
 let plan=await preview(friend,original.id,'booking');assert.equal(plan.contexts[0].existing.length,1);assert.equal(plan.change_count,0);
 await fails(stranger,'select api.preview_booking_resources($1,\'booking\',$2::uuid[],$3::uuid[])',[original.id,[bus],[]],/not_allowed/);
 await fails(friend,'select api.preview_booking_resources($1,\'booking\',$2::uuid[],$3::uuid[])',[original.id,[bus],[bus]],/invalid_resource_set/);
 const originalRow=await row(original.id);plan=await preview(friend,original.id,'booking',[bus,camera]);assert.equal(plan.change_count,2);
 const block=await call(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[bus,start,end]);
 await fails(friend,"select api.execute_booking_command($1,'update_booking_resources',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(plan))],/resource_set_conflicts/);
 assert.deepEqual(await row(original.id),originalRow);
 await call(owner,'select api.cancel_booking($1)',[block.id]);
 const key=await uuid();await save(friend,plan,key);await save(friend,plan,key);
 let ctx=(await preview(friend,original.id,'booking')).contexts[0];assert.equal(ctx.existing.length,3);
 const firstBus=ctx.existing.find(b=>b.resource_id===bus);const firstCamera=ctx.existing.find(b=>b.resource_id===camera);
 assert.equal(firstBus.status,'pending');assert.equal(firstCamera.status,'confirmed');assert.ok(ctx.existing.every(b=>b.group_id&&b.group_id===ctx.existing[0].group_id&&b.booked_by===friend));
 assert.equal((await db.query("select count(*)::int n from core.booking_notifications where booking_id=$1 and kind='requested'",[firstBus.id])).rows[0].n,1);
 const retained=await row(firstCamera.id);plan=await preview(friend,original.id,'booking',[],[bus]);await save(friend,plan);
 assert.equal((await row(firstBus.id)).status,'cancelled');assert.deepEqual(await row(firstCamera.id),retained);
 // Explicit single-occurrence rebooking preserves history and uses a new row.
 plan=await preview(friend,original.id,'booking',[bus]);await save(friend,plan);
 ctx=(await preview(friend,original.id,'booking')).contexts[0];assert.notEqual(ctx.existing.find(b=>b.resource_id===bus).id,firstBus.id);
 await db.exec('savepoint set_stale');plan=await preview(friend,original.id,'booking',[],[camera]);
 await db.query('update core.booking_bookings set revision=revision+1 where id=$1',[firstCamera.id]);
 await fails(friend,"select api.execute_booking_command($1,'update_booking_resources',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(plan))],/stale_revision/);await db.exec('rollback to set_stale');
 plan=await preview(friend,original.id,'booking',[],[source,bus,camera]);await save(friend,plan);
 assert.ok((await db.query('select status from core.booking_bookings where group_id=$1',[ctx.existing[0].group_id])).rows.every(b=>b.status==='cancelled'));

 const whole=await resource('Set whole');const part=await resource('Set quarter',{parent_resource_id:whole});
 const wholeBooking=await call(friend,'select api.create_booking($1,$2,$3,null,null,null,null)',[whole,start,end]);
 plan=await preview(friend,wholeBooking.id,'booking',[part],[whole]);assert.equal(plan.conflicts.length,0,'planned removal releases own ancestor claim');await save(friend,plan);
 const partBooking=(await db.query("select id from core.booking_bookings where resource_id=$1 and status='confirmed'",[part])).rows[0].id;
 assert.ok((await preview(friend,partBooking,'booking',[whole])).conflicts.some(c=>c.reason==='resource_busy'),'kept part conflicts with new whole');
 const independent=await call(friend,'select api.create_booking($1,$2,$3,null,null,null,null)',[locker,start,end]);
 assert.ok((await preview(friend,independent.id,'booking',[whole,part])).conflicts.some(c=>c.reason==='resource_busy'),'conflicting additions are detected before any insert');
 const extra=[];for(let i=0;i<10;i++)extra.push(await resource(`Set capacity ${i}`));
 await fails(friend,"select api.preview_booking_resources($1,'booking',$2::uuid[],'{}'::uuid[])",[independent.id,extra],/too_many_resources/);
 plan=await preview(friend,independent.id,'booking',[locker]);assert.equal(plan.change_count,0);
 await fails(friend,"select api.execute_booking_command($1,'update_booking_resources',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(plan))],/resource_set_no_change/);

 // Standalone series: resources share occurrence identity and continue to obey
 // the existing time/approval/cancellation commands, even after removing pitch.
 const spring=new Date(Date.UTC(new Date().getUTCFullYear()+1,2,31));spring.setUTCDate(spring.getUTCDate()-spring.getUTCDay());
 const day=n=>new Date(spring.getTime()+n*86400e3).toISOString().slice(0,10);
 const series=await call(friend,"select api.create_booking_series($1,'{7}'::smallint[],1::smallint,$2,$3,'18:00','19:00','Europe/Stockholm',null,null,null,false)",[source,day(-14),day(14)]);
 const roots=(await db.query('select * from core.booking_bookings where series_id=$1 order by series_sequence',[series.series_id])).rows;
 await db.exec('savepoint fabricated_occurrence');
 await assert.rejects(db.query("insert into core.booking_bookings(organization_id,resource_id,starts_at,ends_at,status,booked_by,series_id,series_sequence,group_id) values($1,$2,$3,$4,'confirmed',$5,$6,99,gen_random_uuid())",[org,camera,roots[0].starts_at,roots[0].ends_at,friend,series.series_id]),/invalid_series_occurrence/);
 await db.exec('rollback to fabricated_occurrence');
 let swap=await call(friend,'select api.preview_booking_resource($1,$2)',[roots[1].id,exception]);
 await call(friend,"select api.execute_booking_command($1,'change_booking_resource',$2::jsonb,null)",[await uuid(),JSON.stringify({target_booking_id:roots[1].id,new_resource_id:exception,expected_plan:swap})]);
 await save(friend,await preview(friend,roots[2].id,'booking',[bus]));
 let single=(await preview(friend,roots[2].id,'booking')).contexts[0];await call(friend,'select api.cancel_booking($1)',[single.existing.find(b=>b.resource_id===bus).id]);
 plan=await preview(friend,roots[4].id,'series_all',[bus,camera]);assert.equal(plan.contexts.length,4);assert.equal(plan.unchanged_contexts.length,1);assert.equal(plan.change_count,7);
 assert.ok(plan.contexts.find(c=>c.series_sequence===3).unchanged_resources.some(n=>n.reason==='previously_cancelled'));
 const allKey=await uuid();await save(friend,plan,allKey);await save(friend,plan,allKey);
 let all=(await db.query('select * from core.booking_bookings where series_id=$1 order by series_sequence,resource_id',[series.series_id])).rows;
 for(const c of plan.contexts)for(const added of c.add){const b=all.find(b=>b.series_sequence===c.series_sequence&&b.resource_id===added.resource_id&&b.status!=='cancelled');assert.ok(b);assert.equal(new Date(b.starts_at).toISOString(),new Date(c.starts_at).toISOString());assert.equal(new Date(b.ends_at).toISOString(),new Date(c.ends_at).toISOString());}
 const meta=(await db.query("select internal.booking_json(b,'booker') value from core.booking_bookings b where id=$1",[roots[4].id])).rows[0].value;
 assert.equal(meta.series_remaining,5);assert.equal(meta.series_upcoming_remaining,5);assert.equal(meta.series_forward_remaining,1);
 const beforePrefix=all.filter(b=>b.series_sequence<4);
 plan=await preview(friend,roots[3].id,'series_forward',[locker],[camera]);assert.equal(plan.contexts.length,2);assert.equal(plan.change_count,4);await save(friend,plan);
 all=(await db.query('select * from core.booking_bookings where series_id=$1 order by series_sequence,resource_id',[series.series_id])).rows;
 assert.deepEqual(all.filter(b=>b.series_sequence<4),beforePrefix);
 const addedLocker=all.find(b=>b.series_sequence===4&&b.resource_id===locker&&b.status==='confirmed');
 await save(friend,await preview(friend,addedLocker.id,'booking',[],[source]));assert.equal((await row(roots[3].id)).status,'cancelled');
 const timePlan=await call(friend,"select api.preview_booking_time($1,'series_forward',$2::timestamptz+interval '1 hour',$3::timestamptz+interval '1 hour')",[addedLocker.id,addedLocker.starts_at,addedLocker.ends_at]);
 assert.ok(timePlan.bookings.some(b=>b.resource_id===bus));assert.ok(timePlan.bookings.some(b=>b.resource_id===locker));
 await call(friend,"select api.execute_booking_command($1,'reschedule_booking',$2::jsonb,null)",[await uuid(),JSON.stringify({target_booking_id:addedLocker.id,change_scope:'series_forward',new_starts_at:timePlan.starts_at,new_ends_at:timePlan.ends_at,expected_plan:timePlan})]);
 assert.equal(new Date((await row(addedLocker.id)).starts_at).toISOString(),new Date(new Date(addedLocker.starts_at).getTime()+3600e3).toISOString());
 await call(owner,'select api.decide_booking_series($1,true)',[series.series_id]);
 assert.equal((await db.query("select count(*)::int n from core.booking_bookings where series_id=$1 and status='pending'",[series.series_id])).rows[0].n,0);
 // Re-add a previously removed resource explicitly in a series occurrence.
 await save(friend,await preview(friend,addedLocker.id,'booking',[camera]));
 const duplicate=(await db.query("select series_sequence,resource_id,count(*)::int n from core.booking_bookings where series_id=$1 and status in('pending','confirmed') group by series_sequence,resource_id having count(*)>1",[series.series_id])).rows;assert.equal(duplicate.length,0);
 await call(friend,'select api.cancel_booking_series($1)',[series.series_id]);
 assert.equal((await db.query("select count(*)::int n from core.booking_bookings where series_id=$1 and status in('pending','confirmed')",[series.series_id])).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from internal.booking_resource_claims c join core.booking_bookings b on b.id=c.booking_id where b.series_id=$1',[series.series_id])).rows[0].n,0);

 // Recurring activities: keep independently timed resources and links, remove
 // reservations without cancelling activities, preserve skipped exceptions.
 const club=(await db.query("insert into core.clubs values(gen_random_uuid(),'Set club') returning id")).rows[0].id;
 const team=(await db.query("insert into core.teams(id,club_id,name) values(gen_random_uuid(),$1,'Set team') returning id",[club])).rows[0].id;
 const person=(await db.query("insert into core.club_people values(gen_random_uuid(),$1,'Set coach') returning id",[club])).rows[0].id;
 await db.query("insert into core.person_account_links values($1,$2,$3,'active')",[coach,club,person]);
 await db.query("insert into core.assignments(club_id,team_id,club_person_id,role_package) values($1,$2,$3,'leader')",[club,team,person]);
 await db.query('update core.booking_organizations set teamzone_club_id=$2 where id=$1',[org,club]);
 const recurrence=await uuid();const events=[],anchors=[];
 for(let i=0;i<5;i++){
  const event=(await db.query("insert into core.events(id,club_id,title,state,starts_at,ends_at,recurrence_id,occurrence_number,timezone) values(gen_random_uuid(),$1,'Set activity','scheduled',$2::timestamptz+interval '30 minutes',$3::timestamptz-interval '15 minutes',$4,$5,'Europe/Stockholm') returning id",[club,new Date(Date.now()+(1200+i*7)*86400e3).toISOString(),new Date(Date.now()+(1200+i*7)*86400e3+3600e3).toISOString(),recurrence,i+1])).rows[0].id;
  events.push(event);await db.query('insert into core.event_teams values($1,$2,$3)',[event,club,team]);
  if(i===4)continue;
  const bounds=(await db.query("select starts_at-interval '30 minutes' s,ends_at+interval '15 minutes' e from core.events where id=$1",[event])).rows[0];
  const g=await call(coach,'select api.create_booking_group($1::uuid[],$2,$3,null,null,$4,$5,false)',[[i===1?exception:source,bus],bounds.s,bounds.e,team,event]);
  await call(owner,'select api.decide_booking_group($1,true)',[g.group_id]);
  if(i!==1)anchors[i]=(await db.query('select id from core.booking_bookings where group_id=$1 and resource_id=$2',[g.group_id,source])).rows[0].id;
 }
 await save(coach,await preview(coach,anchors[0],'booking',[camera]));
 let cameraRow=(await preview(coach,anchors[0],'booking')).contexts[0].existing.find(b=>b.resource_id===camera);
 await db.query("update core.booking_bookings set starts_at=starts_at-interval '1 hour',ends_at=ends_at+interval '2 hours',revision=revision+1 where id=$1",[cameraRow.id]);cameraRow=await row(cameraRow.id);
 await save(coach,await preview(coach,anchors[2],'booking',[camera]));single=(await preview(coach,anchors[2],'booking')).contexts[0];await call(coach,'select api.cancel_booking($1)',[single.existing.find(b=>b.resource_id===camera).id]);
 const beforeEvents=(await db.query('select * from core.events where recurrence_id=$1 order by occurrence_number',[recurrence])).rows;
 plan=await preview(coach,anchors[3],'event_all',[camera,locker],[bus]);assert.equal(plan.contexts.length,3);assert.equal(plan.unchanged_contexts.length,2);assert.equal(plan.change_count,7);
 const future=await preview(coach,anchors[2],'event_forward',[locker],[bus]);assert.equal(future.contexts.length,2);
 await db.exec('savepoint missing_event_permission');await db.exec(`create or replace function internal.actor_can_read_event(e uuid) returns boolean language sql stable as $$select auth.uid()='${coach}'::uuid and e<>'${events[4]}'::uuid$$;`);
 await fails(coach,"select api.preview_booking_resources($1,'event_all',$2::uuid[],$3::uuid[])",[anchors[3],[locker],[bus]],/event_not_found/);await db.exec('rollback to missing_event_permission');
 const eventKey=await uuid();await save(coach,plan,eventKey);await save(coach,plan,eventKey);
 assert.deepEqual((await db.query('select * from core.events where recurrence_id=$1 order by occurrence_number',[recurrence])).rows,beforeEvents);
 assert.deepEqual(await row(cameraRow.id),cameraRow,'independent camera buffers remain untouched');
 for(const c of plan.contexts){const current=(await preview(coach,c.anchor_booking_id,'booking')).contexts[0];assert.ok(current.existing.some(b=>b.resource_id===locker));assert.ok(!current.existing.some(b=>b.resource_id===bus));assert.ok(current.existing.every(b=>b.event_id===c.event_id));}
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[coach]);
 await db.query("update core.events set starts_at=starts_at+interval '1 hour',ends_at=ends_at+interval '1 hour',revision=revision+1 where id=$1",[events[0]]);
 assert.equal(new Date((await row(cameraRow.id)).starts_at).toISOString(),new Date(new Date(cameraRow.starts_at).getTime()+3600e3).toISOString());
 await db.query("update core.events set state='cancelled',revision=revision+1 where id=$1",[events[2]]);
 assert.ok((await db.query('select status from core.booking_bookings where event_id=$1',[events[2]])).rows.every(b=>b.status==='cancelled'));
 console.log('resource sets: single/forward/all, atomic changes, history and exceptions, shared series identity/counts, legacy time/approval/cancellation, buffers and activity sync passed');
}
