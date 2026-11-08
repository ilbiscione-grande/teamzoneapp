import assert from 'node:assert/strict';

export async function checkEventSync({db,call,fails,owner,friend,coach,clubAdmin}) {
 const day=new Date(Date.now()+95*86400e3).toISOString().slice(0,10);
 const club=(await db.query("insert into core.clubs(id,name) values(gen_random_uuid(),'Sync club') returning id")).rows[0].id;
 const team=(await db.query("insert into core.teams(id,club_id,name) values(gen_random_uuid(),$1,'Sync team') returning id",[club])).rows[0].id;
 const person=(await db.query("insert into core.club_people(id,club_id,display_name) values(gen_random_uuid(),$1,'Sync coach') returning id",[club])).rows[0].id;
 await db.query("insert into core.person_account_links(profile_id,club_id,club_person_id,state) values($1,$2,$3,'active')",[coach,club,person]);
 await db.query("insert into core.assignments(club_id,team_id,club_person_id,role_package) values($1,$2,$3,'leader')",[club,team,person]);
 const org=await call(owner,"select api.create_booking_organization('Sync org','club',null)");
 await db.query('update core.booking_organizations set teamzone_club_id=$2 where id=$1',[org,club]);
 const details={name:'Whole sync pitch',category:'pitch',ownership_kind:'owned',timezone:'UTC'};
 const resource=async data=>call(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[org,JSON.stringify({...details,...data})]);
 const whole=await resource({});const quarter=await resource({name:'Sync quarter',parent_resource_id:whole,requires_approval:true});const bus=await resource({name:'Sync bus',category:'vehicle'});
 const event=(await db.query("insert into core.events(id,club_id,title,state,starts_at,ends_at) values(gen_random_uuid(),$3,'Sync event','scheduled',$1,$2) returning id",[day+'T10:00Z',day+'T11:00Z',club])).rows[0].id;
 await db.query('insert into core.event_teams(event_id,club_id,team_id) values($1,$2,$3)',[event,club,team]);
 const group=await call(coach,'select api.create_booking_group($1::uuid[],$2,$3,null,null,$4,$5,false)',[[quarter,bus],day+'T09:30Z',day+'T11:30Z',team,event]);
 await call(owner,'select api.decide_booking_group($1,true)',[group.group_id]);
 const snapshot=async()=> (await db.query('select id,resource_id,starts_at,ends_at,status,revision,decided_by from core.booking_bookings where event_id=$1 order by id',[event])).rows;
 const move=async(who,start,end)=>{
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[who]);
  return db.query('update core.events set starts_at=$2,ends_at=$3 where id=$1',[event,start,end]);
 };
 const before=await snapshot();
 await move(coach,day+'T12:00Z',day+'T14:00Z');
 const moved=await snapshot();
 for(const b of moved){assert.equal(new Date(b.starts_at).toISOString(),day+'T11:30:00.000Z');assert.equal(new Date(b.ends_at).toISOString(),day+'T14:30:00.000Z');assert.equal(b.revision,before.find(x=>x.id===b.id).revision+1);}
 assert.equal(moved.find(b=>b.resource_id===quarter).status,'pending','new time requires a new approval from an ordinary leader');
 assert.equal(moved.find(b=>b.resource_id===quarter).decided_by,null);
 assert.equal(moved.find(b=>b.resource_id===bus).status,'confirmed');
 const key=(await db.query('select gen_random_uuid() id')).rows[0].id;
 await fails(coach,'select api.execute_booking_command($1,\'create_booking\',$2::jsonb,null)',[key,JSON.stringify({target_resource_id:bus,booking_starts_at:day+'T18:00Z',booking_ends_at:day+'T19:00Z',target_team_id:team,target_event_id:event,expected_event_starts_at:day+'T10:00Z',expected_event_ends_at:day+'T11:00Z'})],/event_changed/);
 assert.equal((await db.query("select count(*)::integer total from core.booking_notifications where organization_id=$1 and kind='rescheduled'",[org])).rows[0].total,0,'the actor does not receive their own notice');
 await call(owner,'select api.decide_booking_group($1,true)',[group.group_id]);
 await move(owner,day+'T10:00Z',day+'T11:00Z');
 assert.ok((await snapshot()).every(b=>b.status==='confirmed'),'resource administrator may retain approval');
 assert.equal((await db.query("select count(*)::integer total from core.booking_notifications where organization_id=$1 and kind='rescheduled'",[org])).rows[0].total,1,'one notice per group/booker');
 // A whole-pitch conflict rolls back the event, all other resources, revisions,
 // notices and audit entries, including any already processed in this move.
 await db.query('insert into core.booking_members(organization_id,profile_id,role) values($1,$2,\'booker\')',[org,friend]);
 const blocker=await call(friend,'select api.create_booking($1,$2,$3,null,null,null,null)',[whole,day+'T12:00Z',day+'T15:00Z']);
 const stable=await snapshot();const auditCount=(await db.query('select count(*)::integer n from internal.booking_audit')).rows[0].n;
 await db.exec('savepoint sync_conflict');
 await assert.rejects(move(coach,day+'T13:00Z',day+'T14:00Z'),/event_booking_conflict/);await db.exec('rollback to sync_conflict');
 assert.deepEqual(await snapshot(),stable);assert.equal((await db.query('select count(*)::integer n from internal.booking_audit')).rows[0].n,auditCount);
 assert.equal(new Date((await db.query('select starts_at from core.events where id=$1',[event])).rows[0].starts_at).toISOString(),day+'T10:00:00.000Z');
 await call(friend,'select api.cancel_booking($1)',[blocker.id]);
 await call(owner,'select api.save_booking_resource_v2($1,$2,$3::jsonb,1)',[org,whole,JSON.stringify({...details,available_from:day,available_until:day})]);
 await db.exec('savepoint sync_hours');
 const tomorrow=new Date(day+'T12:00Z');tomorrow.setUTCDate(tomorrow.getUTCDate()+1);const next=tomorrow.toISOString().slice(0,10);
 await assert.rejects(move(coach,next+'T10:00Z',next+'T11:00Z'),/event_booking_outside_hours/);await db.exec('rollback to sync_hours');
 assert.deepEqual(await snapshot(),stable);
 // Cancellation frees the linked resources only; restoring never silently
 // re-reserves them. A new booking cannot attach to a cancelled activity.
 const unrelated=await call(friend,'select api.create_booking($1,$2,$3,null,null,null,null)',[bus,day+'T18:00Z',day+'T19:00Z']);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[clubAdmin]);
 await db.query("update core.events set state='cancelled' where id=$1",[event]);
 assert.ok((await snapshot()).every(b=>b.status==='cancelled'));
 assert.equal((await db.query('select status from core.booking_bookings where id=$1',[unrelated.id])).rows[0].status,'confirmed');
 await fails(coach,'select api.create_booking($1,$2,$3,null,null,$4,$5)',[bus,day+'T15:00Z',day+'T16:00Z',team,event],/event_not_found/);
 await db.query("update core.events set state='scheduled' where id=$1",[event]);assert.ok((await snapshot()).every(b=>b.status==='cancelled'));
 // Several adjacent slots on the same resource move in a safe direction.
 const one=await call(coach,'select api.create_booking($1,$2,$3,null,null,$4,$5)',[bus,day+'T10:00Z',day+'T11:00Z',team,event]);
 const two=await call(coach,'select api.create_booking($1,$2,$3,null,null,$4,$5)',[bus,day+'T11:00Z',day+'T12:00Z',team,event]);
 await move(coach,day+'T11:00Z',day+'T12:00Z');await move(coach,day+'T10:00Z',day+'T11:00Z');
 assert.equal(new Date((await db.query('select starts_at from core.booking_bookings where id=$1',[two.id])).rows[0].starts_at).toISOString(),day+'T11:00:00.000Z');
 await db.exec('savepoint sync_duration');await assert.rejects(move(coach,day+'T10:00Z',day+'T12:00Z'),/event_booking_conflict/);await db.exec('rollback to sync_duration');
 // Booking history retains its activity reference. Cancellation is supported;
 // permanent deletion is rejected instead of silently detaching reservations.
 await db.exec('savepoint sync_history');
 await assert.rejects(db.query("delete from core.events where id=$1",[event]),/event_booking_history/);
 await db.exec('rollback to sync_history');
 await db.query("update core.events set state='cancelled' where id=$1",[event]);
 assert.equal((await db.query('select status from core.booking_bookings where id=$1',[one.id])).rows[0].status,'cancelled');
 assert.equal((await db.query('select event_id from core.booking_bookings where id=$1',[one.id])).rows[0].event_id,event);
 assert.equal((await db.query("select has_function_privilege('authenticated','internal.sync_bookings_from_event()','execute') allowed")).rows[0].allowed,false);
 assert.match((await db.query("select internal.notification_title('booking.rescheduled.v1') title")).rows[0].title,/ny tid/);
 console.log('activity booking sync: margins, reapproval, groups, hierarchy conflicts, atomic rollback, inherited hours, cancellation, restoration and adjacent slots passed');
}
