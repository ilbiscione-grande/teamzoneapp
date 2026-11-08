import assert from 'node:assert/strict';

export async function checkResourceSeries({db,call,fails,owner,friend,coach,stranger}) {
 const org=await call(owner,"select api.create_booking_organization('Resource series verification','club',null)");
 await db.query("insert into core.booking_members(organization_id,profile_id,role) values($1,$2,'booker'),($1,$3,'booker')",[org,friend,coach]);
 const resource=(name,extra={})=>call(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[org,JSON.stringify({name,category:'pitch',ownership_kind:'owned',timezone:'Europe/Stockholm',...extra})]);
 const uuid=()=>db.query('select gen_random_uuid() id').then(r=>r.rows[0].id);
 const spring=new Date(Date.UTC(new Date().getUTCFullYear()+1,2,31));spring.setUTCDate(spring.getUTCDate()-spring.getUTCDay());
 const date=n=>new Date(spring.getTime()+n*86400e3).toISOString().slice(0,10);
 const time=(n,h)=>`${date(n)}T${h}:00${n<0?'+01:00':'+02:00'}`;
 const rows=series=>db.query('select * from core.booking_bookings where series_id=$1 order by series_sequence',[series]).then(r=>r.rows);
 const preview=(who,id,r,scope)=>call(who,'select api.preview_booking_resource_series($1,$2,$3)',[id,r,scope]);
 const single=(who,id,r)=>call(who,'select api.preview_booking_resource($1,$2)',[id,r]);
 const payload=(p,scope=p.scope)=>({target_booking_id:p.target_booking_id,new_resource_id:p.new_resource_id,...(scope?{change_scope:scope}:{}),expected_plan:p});
 const commit=async(who,p,key=null)=>call(who,"select api.execute_booking_command($1,'change_booking_resource',$2::jsonb,null)",[key??await uuid(),JSON.stringify(payload(p))]);
 const source=await resource('Series source');const whole=await resource('Series target whole');
 const target=await resource('Series target half',{parent_resource_id:whole,requires_approval:true});const exception=await resource('Series manual exception');
 const series=await call(friend,"select api.create_booking_series($1,'{7}'::smallint[],1::smallint,$2,$3,'18:00','19:00','Europe/Stockholm',null,null,null,false)",[source,date(-21),date(21)]);
 let all=await rows(series.series_id);
 await db.query("update core.booking_bookings set starts_at=now()-interval '2 days',ends_at=now()-interval '1 day' where id=$1",[all[0].id]);
 await db.query("update core.booking_bookings set starts_at=now()-interval '10 minutes',ends_at=now()+interval '10 minutes' where id=$1",[all[1].id]);
 await call(friend,'select api.cancel_booking($1)',[all[2].id]);
 await commit(friend,await single(friend,all[4].id,exception));
 const last=all[6];
 const exceptionalTime=await call(friend,'select api.preview_booking_time($1,\'booking\',$2,$3)',[last.id,time(-20,'18:00'),time(-20,'19:00')]);
 await call(friend,"select api.execute_booking_command($1,'reschedule_booking',$2::jsonb,null)",[await uuid(),JSON.stringify({target_booking_id:last.id,change_scope:'booking',new_starts_at:exceptionalTime.starts_at,new_ends_at:exceptionalTime.ends_at,expected_plan:exceptionalTime})]);
 all=await rows(series.series_id);
 const forward=await preview(friend,all[5].id,target,'series_forward');
 assert.deepEqual(forward.bookings.map(b=>b.series_sequence).sort(),[6,7],'immutable order includes exceptional calendar date');
 let plan=await preview(friend,last.id,target,'series_all');
 assert.deepEqual(plan.bookings.map(b=>b.series_sequence).sort(),[4,6,7]);assert.equal(plan.unchanged.length,1);assert.equal(plan.unchanged[0].resource_id,exception);
 assert.ok(plan.bookings.every(b=>b.status==='pending'));assert.equal(plan.conflicts.length,0);
 await fails(stranger,'select api.preview_booking_resource_series($1,$2,\'series_all\')',[last.id,target],/not_allowed/);
 await fails(friend,'select api.preview_booking_resource_series($1,$2,\'wrong\')',[last.id,target],/invalid_command/);
 await fails(friend,"select api.execute_booking_command($1,'change_booking_resource',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(plan,'wrong'))],/invalid_command/);
 const blocker=await call(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[whole,time(0,'18:00'),time(0,'19:00')]);
 const blocked=await preview(friend,last.id,target,'series_all');assert.equal(blocked.bookings.length,3);assert.equal(blocked.conflicts[0].reason,'resource_busy');
 await fails(friend,"select api.execute_booking_command($1,'change_booking_resource',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(plan))],/resource_change_conflicts/);
 assert.deepEqual(await rows(series.series_id),all);
 await call(owner,'select api.cancel_booking($1)',[blocker.id]);
 await db.exec('savepoint series_swap_stale');await db.query('update core.booking_resources set revision=revision+1 where id=$1',[whole]);
 await fails(friend,"select api.execute_booking_command($1,'change_booking_resource',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(plan))],/stale_revision/);await db.exec('rollback to series_swap_stale');
 await db.exec('savepoint exception_swap_stale');await db.query('update core.booking_bookings set revision=revision+1 where id=$1',[all[4].id]);
 await fails(friend,"select api.execute_booking_command($1,'change_booking_resource',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(plan))],/stale_revision/);await db.exec('rollback to exception_swap_stale');
 await db.exec('savepoint series_swap_permission');await db.query('update core.booking_bookings set booked_by=$2 where id=$1',[all[3].id,stranger]);
 await fails(friend,'select api.preview_booking_resource_series($1,$2,\'series_all\')',[last.id,target],/not_allowed/);await db.exec('rollback to series_swap_permission');
 const key=await uuid();await commit(friend,plan,key);await commit(friend,plan,key);
 const after=await rows(series.series_id);
 for(let i=0;i<7;i++)if([3,5,6].includes(i)){
  assert.equal(after[i].resource_id,target);assert.equal(after[i].revision,all[i].revision+1);assert.equal(after[i].status,'pending');assert.equal(after[i].decided_by,null);
  for(const field of ['id','starts_at','ends_at','series_id','series_sequence','group_id','event_id','booked_by'])assert.deepEqual(after[i][field],all[i][field]);
 }else assert.deepEqual(after[i],all[i]);
 assert.equal((await db.query('select resource_id from core.booking_series where id=$1',[series.series_id])).rows[0].resource_id,source);
 assert.equal((await db.query("select count(*)::int n from core.booking_notifications n join core.booking_bookings b on b.id=n.booking_id where b.series_id=$1 and n.kind='requested'",[series.series_id])).rows[0].n,3,'replay sends no duplicate approval requests');
 // Activity series: replace only the selected resource, preserve companions,
 // differently resourced activities and activities with no resource booking.
 const club=(await db.query("insert into core.clubs values(gen_random_uuid(),'Resource series club') returning id")).rows[0].id;
 const team=(await db.query("insert into core.teams(id,club_id,name) values(gen_random_uuid(),$1,'Resource series team') returning id",[club])).rows[0].id;
 const person=(await db.query("insert into core.club_people values(gen_random_uuid(),$1,'Resource series coach') returning id",[club])).rows[0].id;
 await db.query("insert into core.person_account_links values($1,$2,$3,'active')",[coach,club,person]);
 await db.query("insert into core.assignments(club_id,team_id,club_person_id,role_package) values($1,$2,$3,'leader')",[club,team,person]);
 await db.query('update core.booking_organizations set teamzone_club_id=$2 where id=$1',[org,club]);
 const eventSource=await resource('Activity series source');const eventTarget=await resource('Activity series target',{requires_approval:true});const bus=await resource('Activity series bus');
 const recurrence=await uuid();const events=[];const selected=[];
 for(let i=0;i<8;i++){
  const event=(await db.query("insert into core.events(id,club_id,title,state,starts_at,ends_at,recurrence_id,occurrence_number,timezone) values(gen_random_uuid(),$1,'Resource series activity','scheduled',$2,$3,$4,$5,'Europe/Stockholm') returning id",[club,time(i*7,'18:00'),time(i*7,'19:00'),recurrence,i+1])).rows[0].id;
  await db.query('insert into core.event_teams values($1,$2,$3)',[event,club,team]);events.push(event);
  if(i===2)await call(coach,'select api.create_booking($1,$2,$3,null,null,$4,$5)',[exception,time(i*7,'17:30'),time(i*7,'20:00'),team,event]);
  else if(i>0){const group=await call(coach,'select api.create_booking_group($1::uuid[],$2,$3,null,null,$4,$5,false)',[[eventSource,bus],time(i*7,'17:30'),time(i*7,'20:00'),team,event]);selected[i]=(await db.query('select id from core.booking_bookings where group_id=$1 and resource_id=$2',[group.group_id,eventSource])).rows[0].id;}
 }
 await db.query("update core.events set state='cancelled' where id=$1",[events[5]]);
 await db.query('update core.events set archived_at=now() where id=$1',[events[6]]);
 await db.query("update core.events set starts_at=now()-interval '10 minutes',ends_at=now()+interval '50 minutes' where id=$1",[events[7]]);
 const beforeEvents=(await db.query('select * from core.events where recurrence_id=$1 order by occurrence_number',[recurrence])).rows;
 const beforeBookings=(await db.query('select b.* from core.booking_bookings b join core.events e on e.id=b.event_id where e.recurrence_id=$1 order by b.id',[recurrence])).rows;
 plan=await preview(coach,selected[4],eventTarget,'event_all');assert.equal(plan.bookings.length,3);assert.equal(plan.unchanged.length,2);assert.equal(plan.events.length,5);
 const eventForward=await preview(coach,selected[3],eventTarget,'event_forward');assert.equal(eventForward.bookings.length,2);assert.equal(eventForward.events.length,2);
 const metadata=(await db.query("select internal.booking_json(b,'booker') value from core.booking_bookings b where id=$1",[selected[4]])).rows[0].value;assert.equal(metadata.resource_event_series,true);
 // Resource replacement needs reservation rights and event read access, not
 // event-management rights, since it leaves every activity field unchanged.
 await db.exec('savepoint read_only_events');await db.exec('create or replace function internal.actor_can_manage_event(e uuid) returns boolean language sql stable as $$select false$$;');
 assert.equal((await preview(coach,selected[4],eventTarget,'event_all')).bookings.length,3);await db.exec('rollback to read_only_events');
 await db.exec('savepoint denied_earlier_read');await db.exec(`create or replace function internal.actor_can_read_event(e uuid) returns boolean language sql stable as $$select auth.uid()='${coach}'::uuid and e<>'${events[0]}'::uuid$$;`);
 await fails(coach,"select api.preview_booking_resource_series($1,$2,'event_all')",[selected[4],eventTarget],/event_not_found/);await db.exec('rollback to denied_earlier_read');
 await db.exec('savepoint ambiguous_source');await call(coach,'select api.create_booking($1,$2,$3,null,null,$4,$5)',[eventSource,time(7,'21:00'),time(7,'22:00'),team,events[1]]);
 await fails(coach,"select api.preview_booking_resource_series($1,$2,'event_all')",[selected[4],eventTarget],/resource_series_ambiguous/);await db.exec('rollback to ambiguous_source');
 await db.exec('savepoint earlier_event_changed');await db.query('update core.events set revision=revision+1 where id=$1',[events[0]]);
 await fails(coach,"select api.execute_booking_command($1,'change_booking_resource',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(plan))],/stale_revision/);await db.exec('rollback to earlier_event_changed');
 const busy=await call(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[eventTarget,time(7,'18:00'),time(7,'19:00')]);
 await fails(coach,"select api.execute_booking_command($1,'change_booking_resource',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(plan))],/resource_change_conflicts/);
 assert.deepEqual((await db.query('select b.* from core.booking_bookings b join core.events e on e.id=b.event_id where e.recurrence_id=$1 order by b.id',[recurrence])).rows,beforeBookings);
 await call(owner,'select api.cancel_booking($1)',[busy.id]);
 const eventKey=await uuid();await commit(coach,plan,eventKey);await commit(coach,plan,eventKey);
 assert.deepEqual((await db.query('select * from core.events where recurrence_id=$1 order by occurrence_number',[recurrence])).rows,beforeEvents);
 const finalBookings=(await db.query('select b.* from core.booking_bookings b join core.events e on e.id=b.event_id where e.recurrence_id=$1 order by b.id',[recurrence])).rows;
 for(let i=0;i<beforeBookings.length;i++){
  const old=beforeBookings[i],now=finalBookings[i];
  if([selected[1],selected[3],selected[4]].includes(old.id)){assert.equal(now.resource_id,eventTarget);assert.equal(now.revision,old.revision+1);assert.equal(now.status,'pending');
   for(const field of ['starts_at','ends_at','event_id','group_id','booked_by'])assert.deepEqual(now[field],old[field]);
  }else assert.deepEqual(now,old);
 }
 console.log('resource series: immutable forward/all scopes, preserved exceptions and lifecycle, atomic conflicts, stale plans, permissions, buffers, reapproval and replay passed');
}
