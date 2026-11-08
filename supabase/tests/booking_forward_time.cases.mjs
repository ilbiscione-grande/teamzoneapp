import assert from 'node:assert/strict';

export async function checkForwardTime({db,call,fails,owner,friend,coach,stranger}) {
 const year=new Date().getUTCFullYear()+1;
 const spring=new Date(Date.UTC(year,2,31));spring.setUTCDate(spring.getUTCDate()-spring.getUTCDay());
 const day=(offset)=>new Date(spring.getTime()+offset*86400e3).toISOString().slice(0,10);
 const local=(offset,time)=>`${day(offset)}T${time}:00${offset<0?'+01:00':'+02:00'}`;
 const org=await call(owner,"select api.create_booking_organization('Forward verification','club',null)");
 await db.query("insert into core.booking_members(organization_id,profile_id,role) values($1,$2,'booker')",[org,friend]);
 const resource=async(name,approval=false,parent=null)=>call(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[org,JSON.stringify({name,category:'pitch',ownership_kind:'owned',timezone:'Europe/Stockholm',requires_approval:approval,parent_resource_id:parent})]);
 const uuid=()=>db.query('select gen_random_uuid() id').then(r=>r.rows[0].id);
 const preview=(who,id,scope,start,end)=>call(who,'select api.preview_booking_time($1,$2,$3,$4)',[id,scope,start,end]);
 const payload=plan=>({target_booking_id:plan.target_booking_id,change_scope:plan.scope,new_starts_at:plan.starts_at,new_ends_at:plan.ends_at,expected_plan:plan});
 const commit=async(who,plan,key=null)=>call(who,"select api.execute_booking_command($1,'reschedule_booking',$2::jsonb,null)",[key??await uuid(),JSON.stringify(payload(plan))]);
 const rows=series=>db.query('select *,to_char(starts_at at time zone \'Europe/Stockholm\',\'YYYY-MM-DD HH24:MI\') local_start from core.booking_bookings where series_id=$1 order by series_sequence',[series]).then(r=>r.rows);
 const field=async(id,column)=>Object.values((await db.query(`select ${column} from core.booking_bookings where id=$1`,[id])).rows[0])[0];
 const pitch=await resource('Forward series pitch',true);
 const series=await call(friend,"select api.create_booking_series($1,'{7}'::smallint[],1::smallint,$2::date,$3::date,'18:00','19:00','Europe/Stockholm',null,null,null,false)",[pitch,day(-14),day(14)]);
 await call(owner,'select api.decide_booking_series($1,true)',[series.series_id]);
 let all=await rows(series.series_id);assert.deepEqual(all.map(b=>b.series_sequence),[1,2,3,4,5]);
 // Move the fifth occurrence before the anchor in calendar time. It must
 // still be included according to its immutable place in the series.
 const fifth=all[4];const exceptional=await preview(friend,fifth.id,'booking',local(-13,'18:00'),local(-13,'19:00'));
 await commit(friend,exceptional);await call(owner,'select api.decide_booking($1,true)',[fifth.id]);
 await call(friend,'select api.cancel_booking($1)',[all[3].id]);
 all=await rows(series.series_id);const first=all[0],cancelled=all[3],anchor=all[1];
 const plan=await preview(friend,anchor.id,'series_forward',local(0,'18:30'),local(0,'19:30'));
 assert.deepEqual(plan.bookings.map(b=>b.series_sequence).sort(),[2,3,5]);assert.equal(plan.timezone,'Europe/Stockholm');
 await fails(stranger,'select api.preview_booking_time($1,\'series_forward\',$2,$3)',[anchor.id,local(0,'18:30'),local(0,'19:30')],/not_allowed/);
 const token=await uuid();await commit(friend,plan,token);await commit(friend,plan,token);
 all=await rows(series.series_id);
 assert.equal(all[0].local_start,first.local_start);assert.equal(all[0].revision,first.revision);
 assert.equal(all[3].local_start,cancelled.local_start);assert.equal(all[3].status,'cancelled');
 assert.equal(all[1].local_start,day(0)+' 18:30');assert.equal(all[2].local_start,day(7)+' 18:30');assert.equal(all[4].local_start,day(-6)+' 18:30');
 for(const n of [1,2,4]){assert.equal(all[n].status,'pending');assert.equal(all[n].decided_by,null);assert.equal(all[n].revision,plan.bookings.find(b=>b.id===all[n].id).revision+1);}
 const metadata=(await db.query('select internal.booking_json(b,\'booker\') value from core.booking_bookings b where id=$1',[anchor.id])).rows[0].value;
 assert.equal(metadata.series_forward_remaining,3);
 await db.exec('savepoint immutable');await assert.rejects(db.query('update core.booking_bookings set series_sequence=99 where id=$1',[anchor.id]),/immutable_series_sequence/);await db.exec('rollback to immutable');
 // A valid anchor time must still fail if a later occurrence lands in the
 // missing hour at the spring daylight-saving transition.
 const gap=await resource('Forward spring gap');
 const gapSeries=await call(friend,"select api.create_booking_series($1,'{7}'::smallint[],1::smallint,$2::date,$3::date,'04:00','05:00','Europe/Stockholm',null,null,null,false)",[gap,day(-7),day(0)]);
 const gapRows=await rows(gapSeries.series_id);
 await fails(friend,"select api.preview_booking_time($1,'series_forward',$2,$3)",[gapRows[0].id,local(-7,'02:00'),local(-7,'03:00')],/forward_invalid_local_time/);
 const autumn=new Date(Date.UTC(year,9,31));autumn.setUTCDate(autumn.getUTCDate()-autumn.getUTCDay());
 const autumnDay=n=>new Date(autumn.getTime()+n*86400e3).toISOString().slice(0,10);
 const fallResource=await resource('Forward autumn');
 const fall=await call(friend,"select api.create_booking_series($1,'{7}'::smallint[],1::smallint,$2::date,$3::date,'18:00','19:00','Europe/Stockholm',null,null,null,false)",[fallResource,autumnDay(-7),autumnDay(7)]);
 const fallRows=await rows(fall.series_id);
 const fallPlan=await preview(friend,fallRows[0].id,'series_forward',`${autumnDay(0)}T18:30:00+01:00`,`${autumnDay(0)}T19:30:00+01:00`);await commit(friend,fallPlan);
 assert.deepEqual((await rows(fall.series_id)).map(b=>b.local_start),[0,7,14].map(n=>autumnDay(n)+' 18:30'));
 // Calendar recurrence: all future activities, even one without bookings,
 // are listed and revised; each resource keeps its individual buffers.
 const club=(await db.query("insert into core.clubs values(gen_random_uuid(),'Forward club') returning id")).rows[0].id;
 const team=(await db.query("insert into core.teams(id,club_id,name) values(gen_random_uuid(),$1,'Forward team') returning id",[club])).rows[0].id;
 const person=(await db.query("insert into core.club_people values(gen_random_uuid(),$1,'Forward coach') returning id",[club])).rows[0].id;
 await db.query("insert into core.person_account_links values($1,$2,$3,'active')",[coach,club,person]);
 await db.query("insert into core.assignments(club_id,team_id,club_person_id,role_package) values($1,$2,$3,'leader')",[club,team,person]);
 await db.query('update core.booking_organizations set teamzone_club_id=$2 where id=$1',[org,club]);
 const whole=await resource('Forward whole');const part=await resource('Forward quarter',true,whole);const bus=await resource('Forward bus');
 const recurrence=await uuid();const events=[];
 for(let i=0;i<3;i++){
  const event=(await db.query("insert into core.events(id,club_id,title,state,starts_at,ends_at,recurrence_id,occurrence_number,timezone) values(gen_random_uuid(),$1,'Forward activity','scheduled',$2,$3,$4,$5,'Europe/Stockholm') returning id",[club,local((i-1)*7,'18:00'),local((i-1)*7,'19:00'),recurrence,i+1])).rows[0].id;
  await db.query('insert into core.event_teams values($1,$2,$3)',[event,club,team]);events.push(event);
  if(i<2){const group=await call(coach,'select api.create_booking_group($1::uuid[],$2,$3,null,null,$4,$5,false)',[[part,bus],local((i-1)*7,'17:30'),local((i-1)*7,'19:30'),team,event]);await call(owner,'select api.decide_booking_group($1,true)',[group.group_id]);}
 }
 const linked=await db.query('select * from core.booking_bookings where event_id=$1 order by resource_id',[events[0]]);
 const selected=linked.rows.find(b=>b.resource_id===part);const busBooking=linked.rows.find(b=>b.resource_id===bus);
 const buffer=await preview(coach,busBooking.id,'booking',local(-7,'16:00'),local(-7,'21:00'));await commit(coach,buffer);
 let eventPlan=await preview(coach,selected.id,'event_forward',local(0,'18:30'),local(0,'19:30'));
 assert.equal(eventPlan.events.length,3);assert.equal(eventPlan.bookings.length,4);
 const activityMetadata=(await db.query('select internal.booking_json(b,\'booker\') value from core.booking_bookings b where id=$1',[selected.id])).rows[0].value;
 assert.equal(activityMetadata.event_forward_remaining,3);
 // Authorization covers every activity, including those with no resources.
 await db.exec('savepoint permission_fixture');
 await db.exec(`create or replace function internal.actor_can_manage_event(e uuid) returns boolean language sql stable as $$select auth.uid()='${coach}'::uuid and e<>'${events[2]}'::uuid$$;`);
 await fails(coach,"select api.preview_booking_time($1,'event_forward',$2,$3)",[selected.id,local(0,'18:30'),local(0,'19:30')],/event_move_not_allowed/);
 await db.exec('rollback to permission_fixture');
 const blocker=await call(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[whole,local(7,'18:45'),local(7,'19:45')]);
 const revisions=(await db.query('select id,revision,starts_at,ends_at from core.events where recurrence_id=$1 order by id',[recurrence])).rows;
 const audit=(await db.query('select count(*)::int n from internal.booking_audit')).rows[0].n;
 await fails(coach,"select api.execute_booking_command($1,'reschedule_booking',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(eventPlan))],/forward_conflicts/);
 assert.deepEqual((await db.query('select id,revision,starts_at,ends_at from core.events where recurrence_id=$1 order by id',[recurrence])).rows,revisions);
 assert.equal((await db.query('select count(*)::int n from internal.booking_audit')).rows[0].n,audit);
 await call(owner,'select api.cancel_booking($1)',[blocker.id]);
 const eventToken=await uuid();await commit(coach,eventPlan,eventToken);await commit(coach,eventPlan,eventToken);
 const actual=(await db.query("select id,revision,to_char(starts_at at time zone timezone,'YYYY-MM-DD HH24:MI') local_start from core.events where recurrence_id=$1 order by occurrence_number",[recurrence])).rows;
 assert.deepEqual(actual.map(e=>e.local_start),[day(0)+' 18:30',day(7)+' 18:30',day(14)+' 18:30']);assert.ok(actual.every(e=>e.revision===2));
 assert.equal(new Date(await field(busBooking.id,'starts_at')).toISOString(),new Date(local(0,'16:30')).toISOString());
 const middleBooking=(await db.query('select id from core.booking_bookings where event_id=$1 and resource_id=$2',[events[1],part])).rows[0].id;
 const middle=await preview(coach,middleBooking,'event_forward',local(7,'19:00'),local(7,'20:00'));
 assert.equal(middle.events.length,2);await commit(coach,middle);
 assert.equal((await db.query('select revision from core.events where id=$1',[events[0]])).rows[0].revision,2,'earlier activity excluded from middle-forward edit');
 const afterPlan=await preview(coach,selected.id,'event_forward',local(0,'19:00'),local(0,'20:00'));
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[coach]);
 await db.query("update core.events set state='cancelled',revision=revision+1 where id=$1",[events[1]]);
 await fails(coach,"select api.execute_booking_command($1,'reschedule_booking',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(afterPlan))],/stale_revision/);
 const skip=await preview(coach,selected.id,'event_forward',local(0,'19:00'),local(0,'20:00'));
 assert.equal(skip.events.length,2);await commit(coach,skip);
 assert.equal((await db.query('select state from core.events where id=$1',[events[1]])).rows[0].state,'cancelled');
 assert.ok((await db.query('select status from core.booking_bookings where event_id=$1',[events[1]])).rows.every(b=>b.status==='cancelled'));
 console.log('forward time: stable series order, DST, buffers, reapproval, complete activity coverage, conflicts, stale plans and replay passed');
}
