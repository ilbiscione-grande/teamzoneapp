import assert from 'node:assert/strict';

export async function checkResourceSwap({db,call,fails,owner,friend,coach,stranger}) {
 const org=await call(owner,"select api.create_booking_organization('Resource swap verification','club',null)");
 await db.query("insert into core.booking_members(organization_id,profile_id,role) values($1,$2,'booker'),($1,$3,'booker')",[org,friend,coach]);
 const resource=(name,extra={})=>call(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[org,JSON.stringify({name,category:'pitch',ownership_kind:'owned',timezone:'UTC',...extra})]);
 const uuid=()=>db.query('select gen_random_uuid() id').then(r=>r.rows[0].id);
 const s=new Date(Date.now()+900*86400e3).toISOString(),e=new Date(Date.now()+900*86400e3+3600e3).toISOString();
 const make=(who,r)=>call(who,'select api.create_booking($1,$2,$3,\'Swap\',\'Keep notes\',null,null)',[r,s,e]);
 const preview=(who,id,r)=>call(who,'select api.preview_booking_resource($1,$2)',[id,r]);
 const payload=p=>({target_booking_id:p.target_booking_id,new_resource_id:p.new_resource_id,expected_plan:p});
 const commit=async(who,p,key=null)=>call(who,"select api.execute_booking_command($1,'change_booking_resource',$2::jsonb,null)",[key??await uuid(),JSON.stringify(payload(p))]);
 const row=id=>db.query('select * from core.booking_bookings where id=$1',[id]).then(r=>r.rows[0]);
 const a=await resource('Swap source');const b=await resource('Swap approval',{requires_approval:true});const c=await resource('Swap free');
 const booked=await make(friend,a);let original=await row(booked.id);
 await fails(stranger,'select api.preview_booking_resource($1,$2)',[booked.id,b],/not_allowed/);
 await fails(null,'select api.preview_booking_resource($1,$2)',[booked.id,b],/unauthenticated/);
 await fails(friend,'select api.preview_booking_resource($1,$2)',[booked.id,a],/resource_change_same/);
 const otherOrg=await call(owner,"select api.create_booking_organization('Other swap org','club',null)");
 const foreign=await call(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[otherOrg,JSON.stringify({name:'Foreign',category:'vehicle',ownership_kind:'owned',timezone:'UTC'})]);
 await fails(friend,'select api.preview_booking_resource($1,$2)',[booked.id,foreign],/resource_change_not_found/);
 let plan=await preview(friend,booked.id,b);assert.equal(plan.status,'pending');assert.equal(plan.conflicts.length,0);
 const block=await make(owner,b);const blocked=await preview(friend,booked.id,b);assert.deepEqual(blocked.conflicts,['resource_busy']);
 await fails(friend,"select api.execute_booking_command($1,'change_booking_resource',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(plan))],/resource_change_conflicts/);
 assert.deepEqual(await row(booked.id),original,'failed swap retains old reservation and all metadata');
 await call(owner,'select api.cancel_booking($1)',[block.id]);
 await db.exec('savepoint swap_stale');await db.query('update core.booking_resources set revision=revision+1 where id=$1',[b]);
 await fails(friend,"select api.execute_booking_command($1,'change_booking_resource',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(plan))],/stale_revision/);
 await db.exec('rollback to swap_stale');
 const key=await uuid();await commit(friend,plan,key);await commit(friend,plan,key);
 let changed=await row(booked.id);assert.equal(changed.resource_id,b);assert.equal(changed.status,'pending');assert.equal(changed.decided_by,null);assert.equal(changed.revision,2);
 for(const field of ['id','starts_at','ends_at','series_id','group_id','event_id','booked_by','title','notes'])assert.deepEqual(changed[field],original[field]);
 assert.equal((await db.query("select count(*)::int n from core.booking_notifications where booking_id=$1 and kind='requested'",[booked.id])).rows[0].n,1,'one approval request on replay');
 assert.equal((await db.query('select leaf_id from internal.booking_resource_claims where booking_id=$1',[booked.id])).rows[0].leaf_id,b);
 // Old resource is available only after the successful atomic replacement.
 const reuse=await make(owner,a);assert.ok(reuse.id);
 plan=await preview(friend,booked.id,c);assert.equal(plan.status,'confirmed');await commit(friend,plan);
 changed=await row(booked.id);assert.equal(changed.decided_by,friend);assert.equal(changed.status,'confirmed');
 // Administrator replacement also produces a correctly labelled notification.
 plan=await preview(owner,booked.id,b);assert.equal(plan.status,'confirmed');await commit(owner,plan);
 assert.equal((await db.query("select count(*)::int n from core.booking_notifications where booking_id=$1 and kind='resource_changed' and profile_id=$2",[booked.id,friend])).rows[0].n,1);
 assert.equal((await db.query("select count(*)::int n from internal.booking_audit where booking_id=$1 and operation='UPDATE'",[booked.id])).rows[0].n,3);
 // A part can replace its own whole reservation; only other reservations clash.
 const whole=await resource('Swap whole');const part=await resource('Swap half',{parent_resource_id:whole});const quarter=await resource('Swap quarter',{parent_resource_id:part});
 const wholeBooking=await make(friend,whole);plan=await preview(friend,wholeBooking.id,quarter);assert.equal(plan.conflicts.length,0);await commit(friend,plan);
 const outside=await make(friend,c);plan=await preview(friend,outside.id,part);assert.ok(plan.conflicts.includes('resource_busy'));
 // External resource hours and inactive resources cannot take over a booking.
 const external=await resource('Swap external',{ownership_kind:'external',owner_name:'Municipality',available_from:s.slice(0,10),available_until:e.slice(0,10),availability:{mode:'weekly',weekly:[],exceptions:[]}});
 assert.ok((await preview(friend,outside.id,external)).conflicts.includes('resource_outside_disposition'));
 await db.query('update core.booking_resources set active=false,revision=revision+1 where id=$1',[external]);
 assert.ok((await preview(friend,outside.id,external)).conflicts.includes('resource_inactive'));
 // A series occurrence keeps its identity; siblings and the template stay put.
 const seriesResource=await resource('Swap series');const seriesTarget=await resource('Swap series exception');
 const first=(await db.query("select (date_trunc('week',now()+interval '950 days')+interval '6 days')::date d")).rows[0].d;
 const last=(await db.query("select $1::date+14 d",[first])).rows[0].d;
 const series=await call(friend,"select api.create_booking_series($1,'{7}'::smallint[],1::smallint,$2,$3,'18:00','19:00','UTC',null,null,null,false)",[seriesResource,first,last]);
 const siblings=(await db.query('select * from core.booking_bookings where series_id=$1 order by series_sequence',[series.series_id])).rows;
 plan=await preview(friend,siblings[1].id,seriesTarget);await commit(friend,plan);
 const after=(await db.query('select * from core.booking_bookings where series_id=$1 order by series_sequence',[series.series_id])).rows;
 assert.deepEqual(after[0],siblings[0]);assert.deepEqual(after[2],siblings[2]);assert.equal(after[1].series_sequence,2);assert.equal(after[1].resource_id,seriesTarget);
 assert.equal((await db.query('select resource_id from core.booking_series where id=$1',[series.series_id])).rows[0].resource_id,seriesResource);
 // Ongoing and historical reservations cannot be swapped.
 await db.exec('savepoint swap_past');await db.query("update core.booking_bookings set starts_at=now()-interval '1 minute',ends_at=now()+interval '1 minute' where id=$1",[outside.id]);
 await fails(friend,'select api.preview_booking_resource($1,$2)',[outside.id,seriesTarget],/resource_change_requires_future/);await db.exec('rollback to swap_past');
 // Activity/group attachment and individual buffers stay intact; event manager
 // rights are not needed to replace a reservation one is allowed to manage.
 const club=(await db.query("insert into core.clubs values(gen_random_uuid(),'Swap club') returning id")).rows[0].id;
 const team=(await db.query("insert into core.teams(id,club_id,name) values(gen_random_uuid(),$1,'Swap team') returning id",[club])).rows[0].id;
 const person=(await db.query("insert into core.club_people values(gen_random_uuid(),$1,'Swap coach') returning id",[club])).rows[0].id;
 await db.query("insert into core.person_account_links values($1,$2,$3,'active')",[coach,club,person]);
 await db.query("insert into core.assignments(club_id,team_id,club_person_id,role_package) values($1,$2,$3,'leader')",[club,team,person]);
 await db.query('update core.booking_organizations set teamzone_club_id=$2 where id=$1',[org,club]);
 const activity=(await db.query("insert into core.events(id,club_id,title,state,starts_at,ends_at) values(gen_random_uuid(),$1,'Swap event','scheduled',$2::timestamptz+interval '30 minutes',$3::timestamptz-interval '15 minutes') returning id",[club,s,e])).rows[0].id;
 await db.query('insert into core.event_teams values($1,$2,$3)',[activity,club,team]);
 const eventA=await resource('Swap event source');const eventB=await resource('Swap event destination');const companion=await resource('Swap event companion');
 const group=await call(coach,'select api.create_booking_group($1::uuid[],$2,$3,null,null,$4,$5,false)',[[eventA,companion],s,e,team,activity]);
 const members=(await db.query('select * from core.booking_bookings where group_id=$1 order by resource_id',[group.group_id])).rows;
 const selected=members.find(b=>b.resource_id===eventA),untouched=members.find(b=>b.resource_id===companion);
 const eventBefore=(await db.query('select * from core.events where id=$1',[activity])).rows[0];
 plan=await preview(coach,selected.id,eventB);
 await db.exec('savepoint swap_event_stale');await db.query('update core.events set revision=revision+1 where id=$1',[activity]);
 await fails(coach,"select api.execute_booking_command($1,'change_booking_resource',$2::jsonb,null)",[await uuid(),JSON.stringify(payload(plan))],/stale_revision/);await db.exec('rollback to swap_event_stale');
 await commit(coach,plan);changed=await row(selected.id);
 assert.equal(changed.resource_id,eventB);assert.equal(changed.group_id,selected.group_id);assert.equal(changed.event_id,activity);
 assert.deepEqual(changed.starts_at,selected.starts_at);assert.deepEqual(changed.ends_at,selected.ends_at);assert.deepEqual(await row(untouched.id),untouched);
 assert.deepEqual((await db.query('select * from core.events where id=$1',[activity])).rows[0],eventBefore);
 const listing=await call(coach,'select api.list_event_bookings($1)',[activity]);assert.ok(listing.some(b=>b.resource_id===eventB));
 // Approval-free target cannot bypass a competing group member's claim.
 const duplicate=await preview(coach,selected.id,companion);assert.ok(duplicate.conflicts.includes('resource_busy'));
 console.log('resource swap: permissions, reapproval, replay, audit/claims, ancestor conflicts, external hours, series identity and unchanged activity/group buffers passed');
}
