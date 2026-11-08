import assert from 'node:assert/strict';

export async function checkUpcomingSeries({db,call,fails,owner,friend,coach,stranger}) {
 const org=await call(owner,"select api.create_booking_organization('Upcoming verification','club',null)");
 await db.query("insert into core.booking_members(organization_id,profile_id,role) values($1,$2,'booker')",[org,friend]);
 const resource=(name,approval=false,parent=null)=>call(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[org,JSON.stringify({name,category:'pitch',timezone:'Europe/Stockholm',ownership_kind:'owned',requires_approval:approval,parent_resource_id:parent})]);
 const uuid=()=>db.query('select gen_random_uuid() id').then(r=>r.rows[0].id);
 const year=new Date().getUTCFullYear()+1;
 const spring=new Date(Date.UTC(year,2,31));spring.setUTCDate(spring.getUTCDate()-spring.getUTCDay());
 const date=n=>new Date(spring.getTime()+n*86400e3).toISOString().slice(0,10);
 const time=(n,h)=>`${date(n)}T${h}:00${n<0?'+01:00':'+02:00'}`;
 const preview=(who,id,scope,s,e)=>call(who,'select api.preview_booking_time($1,$2,$3,$4)',[id,scope,s,e]);
 const payload=p=>({target_booking_id:p.target_booking_id,change_scope:p.scope,new_starts_at:p.starts_at,new_ends_at:p.ends_at,expected_plan:p});
 const commit=async(who,p,key=null)=>call(who,"select api.execute_booking_command($1,'reschedule_booking',$2::jsonb,null)",[key??await uuid(),JSON.stringify(payload(p))]);
 const bookings=series=>db.query('select * from core.booking_bookings where series_id=$1 order by series_sequence',[series]).then(r=>r.rows);
 const whole=await resource('Upcoming whole');const pitch=await resource('Upcoming quarter',true,whole);
 const series=await call(friend,"select api.create_booking_series($1,'{7}'::smallint[],1::smallint,$2::date,$3::date,'18:00','19:00','Europe/Stockholm',null,null,null,false)",[pitch,date(-21),date(14)]);
 await call(owner,'select api.decide_booking_series($1,true)',[series.series_id]);
 let rows=await bookings(series.series_id);const anchor=rows[5];
 // Earlier historical, ongoing and cancelled occurrences remain untouched.
 await db.query("update core.booking_bookings set starts_at=now()-interval '2 days',ends_at=now()-interval '1 day' where id=$1",[rows[0].id]);
 await db.query("update core.booking_bookings set starts_at=now()-interval '10 minutes',ends_at=now()+interval '10 minutes' where id=$1",[rows[1].id]);
 await call(friend,'select api.cancel_booking($1)',[rows[2].id]);rows=await bookings(series.series_id);
 const unchanged=rows.slice(0,3);
 const metadata=(await db.query("select internal.booking_json(b,'booker') value from core.booking_bookings b where id=$1",[anchor.id])).rows[0].value;
 assert.equal(metadata.series_upcoming_remaining,3);assert.equal(metadata.series_forward_remaining,1);
 const plan=await preview(friend,anchor.id,'series_all',time(14,'18:30'),time(14,'19:30'));
 assert.deepEqual(plan.bookings.map(b=>b.series_sequence).sort(),[4,5,6]);assert.equal(plan.conflicts.length,0);
 await fails(stranger,"select api.preview_booking_time($1,'series_all',$2,$3)",[anchor.id,time(14,'18:30'),time(14,'19:30')],/not_allowed/);
 // An obstacle before the selected last occurrence stops the entire batch.
 const block=await call(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[whole,time(0,'19:00'),time(0,'20:00')]);
 const blocked=await preview(friend,anchor.id,'series_all',time(14,'18:30'),time(14,'19:30'));
 assert.equal(blocked.bookings.length,3);assert.ok(blocked.conflicts.length>0);
 await fails(friend,"select api.execute_booking_command($1,'reschedule_booking',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(plan))],/forward_conflicts/);
 assert.deepEqual(await bookings(series.series_id),rows);
 await call(owner,'select api.cancel_booking($1)',[block.id]);
 // A changed earlier future occurrence invalidates a preview from the last.
 await db.exec('savepoint earlier_stale');
 await db.query('update core.booking_bookings set revision=revision+1 where id=$1',[rows[3].id]);
 await fails(friend,"select api.execute_booking_command($1,'reschedule_booking',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(plan))],/stale_revision/);
 await db.exec('rollback to earlier_stale');
 const key=await uuid();await commit(friend,plan,key);await commit(friend,plan,key);
 rows=await bookings(series.series_id);assert.deepEqual(rows.slice(0,3),unchanged);
 for(let i=3;i<6;i++){assert.equal(new Date(rows[i].starts_at).toISOString(),new Date(time((i-3)*7,'18:30')).toISOString());assert.equal(rows[i].status,'pending');}
 // Distinct scope is part of the canonical plan and cannot reuse confirmation.
 const mismatched={...plan,scope:'series_forward'};
 await fails(friend,"select api.execute_booking_command($1,'reschedule_booking',$2::jsonb,null)",[await uuid(),JSON.stringify({...payload(mismatched),expected_plan:plan})],/stale_revision/);
 // Missing spring time in an earlier future occurrence must be rejected too.
 const gap=await resource('Upcoming spring gap');
 const gapSeries=await call(friend,"select api.create_booking_series($1,'{7}'::smallint[],1::smallint,$2::date,$3::date,'04:00','05:00','Europe/Stockholm',null,null,null,false)",[gap,date(-7),date(7)]);
 const gapRows=await bookings(gapSeries.series_id);
 await fails(friend,"select api.preview_booking_time($1,'series_all',$2,$3)",[gapRows[2].id,time(7,'02:00'),time(7,'03:00')],/forward_invalid_local_time/);
 // All recurring activities, including earlier ones with no resources.
 const club=(await db.query("insert into core.clubs values(gen_random_uuid(),'Upcoming club') returning id")).rows[0].id;
 const team=(await db.query("insert into core.teams(id,club_id,name) values(gen_random_uuid(),$1,'Upcoming team') returning id",[club])).rows[0].id;
 const person=(await db.query("insert into core.club_people values(gen_random_uuid(),$1,'Upcoming coach') returning id",[club])).rows[0].id;
 await db.query("insert into core.person_account_links values($1,$2,$3,'active')",[coach,club,person]);
 await db.query("insert into core.assignments(club_id,team_id,club_person_id,role_package) values($1,$2,$3,'leader')",[club,team,person]);
 await db.query('update core.booking_organizations set teamzone_club_id=$2 where id=$1',[org,club]);
 const bus=await resource('Upcoming activity bus');const recurrence=await uuid();const events=[];let selected;
 for(let i=0;i<6;i++){
  const id=(await db.query("insert into core.events(id,club_id,title,state,starts_at,ends_at,recurrence_id,occurrence_number,timezone) values(gen_random_uuid(),$1,'Upcoming activity','scheduled',$2,$3,$4,$5,'Europe/Stockholm') returning id",[club,time((i-3)*7,'18:00'),time((i-3)*7,'19:00'),recurrence,i+1])).rows[0].id;
  await db.query('insert into core.event_teams values($1,$2,$3)',[id,club,team]);events.push(id);
  if(i===4||i===5){const b=await call(coach,'select api.create_booking($1,$2,$3,null,null,$4,$5)',[bus,time((i-3)*7,'17:30'),time((i-3)*7,'20:00'),team,id]);if(i===5)selected=b.id;}
 }
 await db.query("update core.events set starts_at=now()-interval '2 days',ends_at=now()-interval '1 day' where id=$1",[events[0]]);
 await db.query("update core.events set starts_at=now()-interval '10 minutes',ends_at=now()+interval '10 minutes' where id=$1",[events[1]]);
 await db.query("update core.events set state='cancelled' where id=$1",[events[2]]);
 const before=(await db.query('select id,revision,starts_at,ends_at,state from core.events where recurrence_id=$1 order by occurrence_number',[recurrence])).rows;
 let eventPlan=await preview(coach,selected,'event_all',time(14,'18:30'),time(14,'19:30'));
 assert.equal(eventPlan.events.length,3);assert.equal(eventPlan.bookings.length,2);assert.equal(eventPlan.conflicts.length,0);
 const eventMetadata=(await db.query("select internal.booking_json(b,'booker') value from core.booking_bookings b where id=$1",[selected])).rows[0].value;
 assert.equal(eventMetadata.event_upcoming_remaining,3);assert.equal(eventMetadata.event_forward_remaining,1);
 await db.exec('savepoint upcoming_permission');
 await db.exec(`create or replace function internal.actor_can_manage_event(e uuid) returns boolean language sql stable as $$select auth.uid()='${coach}'::uuid and e<>'${events[3]}'::uuid$$;`);
 await fails(coach,"select api.preview_booking_time($1,'event_all',$2,$3)",[selected,time(14,'18:30'),time(14,'19:30')],/event_move_not_allowed/);
 await db.exec('rollback to upcoming_permission');
 await db.exec('savepoint upcoming_event_stale');
 await db.query('update core.events set revision=revision+1 where id=$1',[events[3]]);
 await fails(coach,"select api.execute_booking_command($1,'reschedule_booking',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(eventPlan))],/stale_revision/);
 await db.exec('rollback to upcoming_event_stale');
 const eventKey=await uuid();await commit(coach,eventPlan,eventKey);await commit(coach,eventPlan,eventKey);
 const after=(await db.query('select id,revision,starts_at,ends_at,state from core.events where recurrence_id=$1 order by occurrence_number',[recurrence])).rows;
 assert.deepEqual(after.slice(0,3),before.slice(0,3));assert.ok(after.slice(3).every(e=>e.revision===2));
 for(let i=3;i<6;i++)assert.equal(new Date(after[i].starts_at).toISOString(),new Date(time((i-3)*7,'18:30')).toISOString());
 const linked=(await db.query('select * from core.booking_bookings where event_id=$1',[events[4]])).rows[0];
 assert.equal(new Date(linked.starts_at).toISOString(),new Date(time(7,'18:00')).toISOString());
 assert.equal(new Date(linked.ends_at).toISOString(),new Date(time(7,'20:30')).toISOString());
 console.log('upcoming series: last-occurrence anchor, earlier conflicts/permissions/staleness, historical and ongoing exclusions, DST, buffers, reapproval and replay passed');
}
