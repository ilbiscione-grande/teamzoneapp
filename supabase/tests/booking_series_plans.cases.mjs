import assert from 'node:assert/strict';
export async function checkSeriesPlans({db,call,fails,owner,friend,coach,stranger}){
 const uuid=()=>db.query('select gen_random_uuid() id').then(r=>r.rows[0].id);
 const day=n=>new Date(Date.now()+n*86400e3).toISOString().slice(0,10);
 const datePlus=(s,n)=>new Date(Date.parse(s)+n*86400e3).toISOString().slice(0,10);
 const plus=(s,h)=>new Date(new Date(s).getTime()+h*3600e3).toISOString();
 let sunday=day(7);while(new Date(sunday).getUTCDay()!==0)sunday=datePlus(sunday,1);
 const org=await call(owner,"select api.create_booking_organization('Future series verification','club',null)");
 await db.query("insert into core.booking_members(organization_id,profile_id,role) values($1,$2,'booker')",[org,friend]);
 const resource=(name,extra={})=>call(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[org,JSON.stringify({name,category:'pitch',ownership_kind:'owned',timezone:'Europe/Stockholm',...extra})]);
 const pitch=await resource('Future pitch'),bus=await resource('Future bus',{category:'vehicle',requires_approval:true}),locker=await resource('Future locker',{category:'locker_room',requires_approval:true}),camera=await resource('Future camera',{category:'equipment'});
 const series=await call(friend,"select api.create_booking_series($1,'{7}'::smallint[],1::smallint,$2,$3,'18:00','19:00','Europe/Stockholm',null,null,null,false)",[pitch,sunday,datePlus(sunday,21)]);
 const roots=(await db.query('select * from core.booking_bookings where series_id=$1 order by series_sequence',[series.series_id])).rows;
 const get=(who,id)=>call(who,'select api.get_booking_series_plan($1)',[id]);
 const preview=(who,id,cfg)=>call(who,'select api.preview_booking_series_plan($1,$2::jsonb)',[id,JSON.stringify(cfg)]);
 const save=async(who,id,cfg,p,key=null)=>call(who,"select api.execute_booking_command($1,'save_booking_series_plan',$2::jsonb,null)",[key??await uuid(),JSON.stringify({target_booking_id:id,configuration:cfg,expected_plan:p})]);
 const control=async(who,p,action)=>call(who,"select api.execute_booking_command($1,'control_booking_series_plan',$2::jsonb,null)",[await uuid(),JSON.stringify({plan_id:p.id,action,expected_revision:p.revision})]);
 const run=async(id,asOf=null)=>Object.values((await db.query('select internal.generate_booking_series_plan_for_actor($1,$2)',[id,asOf])).rows[0])[0];
 let d=await get(friend,roots[0].id);assert.equal(d.plan,null);
 let cfg={...d.defaults,first_day:datePlus(sunday,28),ends_on:datePlus(sunday,154),resource_ids:[pitch,bus],automatic:true};
 let p=await preview(friend,roots[0].id,cfg);assert.equal(p.slots.length,19);assert.ok(p.slots.some(s=>!s.generate_now));
 await fails(stranger,'select api.get_booking_series_plan($1)',[roots[0].id],/not_allowed/);
 await fails(friend,'select internal.run_booking_series_plans()',[],/permission denied/);
 await fails(null,'select api.get_booking_series_plan($1)',[roots[0].id],/unauthenticated/);
 const firstNew=p.slots[0];const blockedTime=p.slots[1];
 const blocker=await call(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[bus,blockedTime.starts_at,blockedTime.ends_at]);
 await fails(friend,"select api.execute_booking_command($1,'save_booking_series_plan',$2::jsonb,null)",[await uuid(),JSON.stringify({target_booking_id:roots[0].id,configuration:cfg,expected_plan:p})],/stale_revision/);
 p=await preview(friend,roots[0].id,cfg);assert.ok(p.slots[1].conflicts.length);
 const key=await uuid();const result=await save(friend,roots[0].id,cfg,p,key);assert.equal((await save(friend,roots[0].id,cfg,p,key)).plan_id,result.plan_id);
 d=await get(friend,roots[0].id);assert.equal(d.plan.state,'active');assert.equal(d.slots.filter(s=>s.state==='blocked').length,1);
 await db.exec('savepoint stale_worker_author');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[owner]);
 await assert.rejects(db.query('select internal.generate_booking_series_plan_for_actor($1)',[d.plan.id]),/stale_revision/);await db.exec('rollback to stale_worker_author');
 const generated=d.slots.filter(s=>s.state==='created');assert.ok(generated.length>0);assert.ok(d.slots.some(s=>s.state==='queued'));
 assert.ok((await db.query("select count(*)::int n from core.booking_bookings where group_id=any($1::uuid[]) and status in('pending','confirmed') group by group_id",[generated.map(s=>s.group_id)])).rows.every(r=>r.n===2));
 assert.equal((await db.query('select count(*)::int n from core.booking_bookings where group_id=$1',[d.slots.find(s=>s.state==='blocked').group_id])).rows[0].n,0);
 const generatedBus=(await db.query('select * from core.booking_bookings where group_id=$1 and resource_id=$2',[generated[0].group_id,bus])).rows[0];assert.equal(generatedBus.status,'pending');
 await call(friend,'select api.cancel_booking($1)',[generatedBus.id]);
 const countBefore=(await db.query('select count(*)::int n from core.booking_bookings where series_id=$1',[series.series_id])).rows[0].n;
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[friend]);await run(d.plan.id);
 assert.equal((await db.query('select count(*)::int n from core.booking_bookings where series_id=$1',[series.series_id])).rows[0].n,countBefore);
 assert.equal((await db.query('select status from core.booking_bookings where id=$1',[generatedBus.id])).rows[0].status,'cancelled');
 await call(owner,'select api.cancel_booking($1)',[blocker.id]);d=await get(friend,roots[0].id);await control(friend,d.plan,'retry');
 d=await get(friend,roots[0].id);assert.equal(d.slots.filter(s=>s.state==='blocked').length,0);assert.ok(d.slots.some(s=>s.id===generated[0].id&&s.state==='created'));
 // Rolling horizon adds future virtual slots only, preserving stable identities.
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[friend]);const extended=await run(d.plan.id,day(35));assert.ok(extended.created>0);
 d=await get(friend,roots[0].id);assert.ok(d.slots.filter(s=>s.state==='created').length>generated.length);
 await control(friend,d.plan,'pause');d=await get(friend,roots[0].id);assert.equal(d.plan.state,'paused');
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[friend]);assert.equal((await run(d.plan.id,day(80))).paused,true);
 await control(friend,d.plan,'resume');d=await get(friend,roots[0].id);
 // Revoked membership pauses unattended generation, without granting cron's rights.
 await db.query('delete from core.booking_members where organization_id=$1 and profile_id=$2',[org,friend]);
 await db.query('select internal.run_booking_series_plans()');
 const paused=(await db.query('select * from internal.booking_series_plans where id=$1',[d.plan.id])).rows[0];assert.equal(paused.state,'paused');assert.equal(paused.last_error,'not_allowed');
 await db.query("insert into core.booking_members(organization_id,profile_id,role) values($1,$2,'booker')",[org,friend]);d=await get(friend,roots[0].id);await control(friend,d.plan,'resume');
 // Legacy bulk commands cannot silently diverge from an opted-in future plan.
 await fails(friend,"select api.preview_booking_time($1,'series_all',$2,$3)",[roots[0].id,plus(roots[0].starts_at,1),plus(roots[0].ends_at,1)],/series_plan_requires_combined/);
 await fails(friend,"select api.preview_booking_resources($1,'series_all','{}'::uuid[],'{}'::uuid[])",[roots[0].id],/series_plan_requires_combined/);
 // A conflict in an as-yet uncreated slot participates in the combined review.
 d=await get(friend,roots[0].id);const waiting=d.slots.find(s=>s.state==='queued');assert.ok(waiting);
 const projected=await db.query("select ($1::timestamp at time zone 'Europe/Stockholm')+interval '1 hour' s,($2::timestamp at time zone 'Europe/Stockholm')+interval '1 hour' e",[waiting.local_start,waiting.local_end]);
 const futureBlock=await call(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[locker,projected.rows[0].s,projected.rows[0].e]);
 let combined=await call(friend,"select api.preview_booking_change($1,'series_all',$2,$3,$4::uuid[],$5::uuid[])",[roots[0].id,plus(roots[0].starts_at,1),plus(roots[0].ends_at,1),[locker],[bus]]);
 assert.ok(combined.future_plan);assert.ok(combined.conflicts.length);
 const changePayload=p=>({target_booking_id:p.target_booking_id,change_scope:p.scope,new_starts_at:p.new_starts_at,new_ends_at:p.new_ends_at,add_resource_ids:p.add_resource_ids,remove_resource_ids:p.remove_resource_ids,expected_plan:p});
 await fails(friend,"select api.execute_booking_command($1,'update_booking',$2::jsonb,null)",[await uuid(),JSON.stringify(changePayload(combined))],/booking_change_conflicts/);
 await call(owner,'select api.cancel_booking($1)',[futureBlock.id]);
 combined=await call(friend,"select api.preview_booking_change($1,'series_all',$2,$3,$4::uuid[],$5::uuid[])",[roots[0].id,plus(roots[0].starts_at,1),plus(roots[0].ends_at,1),[locker],[bus]]);assert.equal(combined.conflicts.length,0);
 await call(friend,"select api.execute_booking_command($1,'update_booking',$2::jsonb,null)",[await uuid(),JSON.stringify(changePayload(combined))]);
 d=await get(friend,roots[0].id);assert.ok(d.plan.configuration.resources.some(r=>r.resource_id===locker));assert.ok(!d.plan.configuration.resources.some(r=>r.resource_id===bus));assert.equal(d.plan.configuration.start_time,'19:00:00');
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[friend]);await run(d.plan.id,day(90));
 assert.equal((await db.query("select count(*)::int n from core.booking_bookings where series_id=$1 and status in('pending','confirmed') and resource_id=$2",[series.series_id,bus])).rows[0].n,0);
 await call(friend,'select api.cancel_booking_series($1)',[series.series_id]);d=await get(friend,roots[0].id);assert.equal(d.plan.state,'paused');
 // Monthly rules clamp from the original day, rather than drifting after Feb.
 cfg={...cfg,first_day:'2028-01-31',ends_on:'2028-04-30',frequency:'monthly',interval:1,resource_ids:[pitch],automatic:false};
 p=await preview(friend,roots[0].id,cfg);assert.deepEqual(p.slots.map(s=>s.local_start.slice(0,10)),['2028-01-31','2028-02-29','2028-03-31','2028-04-30']);
 const daily=await preview(friend,roots[0].id,{...cfg,frequency:'daily',interval:2,ends_on:'2028-02-06'});
 assert.deepEqual(daily.slots.map(s=>s.local_start.slice(0,10)),['2028-01-31','2028-02-02','2028-02-04','2028-02-06']);
 cfg={...cfg,first_day:'2028-03-19',ends_on:'2028-03-26',frequency:'weekly',weekdays:[7],start_time:'02:30',end_time:'03:30'};
 p=await preview(friend,roots[0].id,cfg);assert.ok(p.slots.some(s=>s.conflicts.some(c=>c.reason==='forward_invalid_local_time')));
 const fall=await preview(friend,roots[0].id,{...cfg,first_day:'2027-10-24',ends_on:'2027-10-31',end_time:'02:45'});
 assert.ok(fall.slots.some(s=>s.conflicts.some(c=>c.reason==='forward_invalid_local_time')));
 // Actual event API/outbox is covered separately against the complete audit
 // schema. This reduced fixture exercises recurrence identity and booking sync.
 await db.exec(`create or replace function internal.actor_has_capability(c uuid,t uuid,cap text) returns boolean language sql stable as $$select auth.uid()='${coach}'::uuid and cap='event.manage'$$;`);
 await db.exec(`create or replace function internal.create_booking_plan_event(p internal.booking_series_plans,slot internal.booking_series_slots,ns timestamptz,ne timestamptz) returns uuid language plpgsql security definer set search_path='' as $$declare eid uuid:=gen_random_uuid();e core.events;n int;begin e:=jsonb_populate_record(null::core.events,p.event_template->'event');select coalesce(max(occurrence_number),0)+1 into n from core.events where recurrence_id=p.recurrence_id;insert into core.events(id,club_id,owning_team_id,title,event_type,state,starts_at,ends_at,recurrence_id,occurrence_number,timezone) values(eid,e.club_id,e.owning_team_id,e.title,e.event_type,'scheduled',ns,ne,p.recurrence_id,n,p.configuration->>'timezone');insert into core.event_teams(event_id,club_id,team_id,relation,capabilities) values(eid,e.club_id,e.owning_team_id,'primary','{view,co_manage}');return eid;end;$$;`);
 const club=(await db.query("insert into core.clubs values(gen_random_uuid(),'Future club') returning id")).rows[0].id;
 const team=(await db.query("insert into core.teams(id,club_id,name) values(gen_random_uuid(),$1,'Future team') returning id",[club])).rows[0].id;
 const person=(await db.query("insert into core.club_people values(gen_random_uuid(),$1,'Future coach') returning id",[club])).rows[0].id;
 await db.query("insert into core.person_account_links values($1,$2,$3,'active')",[coach,club,person]);await db.query("insert into core.assignments(club_id,team_id,club_person_id,role_package) values($1,$2,$3,'leader')",[club,team,person]);await db.query('update core.booking_organizations set teamzone_club_id=$2 where id=$1',[org,club]);
 const rid=await uuid();await db.query("insert into core.recurrence_rules(id,club_id,timezone,frequency,interval_value,local_start,occurrence_count) values($1,$2,'Europe/Stockholm','weekly',1,$3::date+time '14:00',3)",[rid,club,sunday]);
 let anchor;const eventIds=[];
 for(let i=0;i<3;i++){
  const eid=await uuid();eventIds.push(eid);const date=datePlus(sunday,i*7);
  await db.query("insert into core.events(id,club_id,owning_team_id,title,event_type,state,starts_at,ends_at,recurrence_id,occurrence_number,timezone) values($1,$2,$3,'Future activity','training','scheduled',($4::date+time '14:00') at time zone 'Europe/Stockholm',($4::date+time '15:00') at time zone 'Europe/Stockholm',$5,$6,'Europe/Stockholm')",[eid,club,team,date,rid,i+1]);
  await db.query('insert into core.event_teams(event_id,club_id,team_id) values($1,$2,$3)',[eid,club,team]);await db.query("insert into core.event_audiences(club_id,event_id,audience_type,team_id,created_by) values($1,$2,'players',$3,$4)",[club,eid,team,coach]);
  const e=(await db.query('select * from core.events where id=$1',[eid])).rows[0];
  const a=await call(coach,'select api.create_booking($1,$2,$3,null,null,$4,$5)',[pitch,plus(e.starts_at,-.5),plus(e.ends_at,.25),team,eid]);
  await call(coach,'select api.create_booking($1,$2,$3,null,null,$4,$5)',[camera,plus(e.starts_at,-1),plus(e.ends_at,2),team,eid]);if(i===0)anchor=a;
 }
 d=await get(coach,anchor.id);cfg={...d.defaults,first_day:datePlus(sunday,21),ends_on:datePlus(sunday,147),resource_ids:[pitch,camera],automatic:true};p=await preview(coach,anchor.id,cfg);
 const eventBlock=await call(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[camera,p.slots[0].bookings.find(b=>b.resource_id===camera).starts_at,p.slots[0].bookings.find(b=>b.resource_id===camera).ends_at]);
 p=await preview(coach,anchor.id,cfg);await save(coach,anchor.id,cfg,p);d=await get(coach,anchor.id);
 assert.equal(d.slots[0].state,'blocked');assert.equal(d.slots[0].event_id,null,'blocked activity does not exist without all of its resources');
 const eg=d.slots.find(s=>s.state==='created');assert.ok(eg.event_id);
 const er=(await db.query('select * from core.events where id=$1',[eg.event_id])).rows[0];const br=(await db.query('select * from core.booking_bookings where event_id=$1',[eg.event_id])).rows;
 assert.equal(br.length,2);assert.equal(new Date(br.find(b=>b.resource_id===camera).starts_at).getTime(),new Date(er.starts_at).getTime()-3600e3);
 assert.equal(new Date(br.find(b=>b.resource_id===pitch).ends_at).getTime(),new Date(er.ends_at).getTime()+900e3);
 await call(owner,'select api.cancel_booking($1)',[eventBlock.id]);await control(coach,d.plan,'retry');d=await get(coach,anchor.id);assert.equal(d.slots[0].state,'created');
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[coach]);await db.query("update core.events set state='cancelled',revision=revision+1 where id=$1",[eg.event_id]);await run(d.plan.id,day(40));
 assert.equal((await db.query('select state from core.events where id=$1',[eg.event_id])).rows[0].state,'cancelled');assert.ok((await db.query('select status from core.booking_bookings where event_id=$1',[eg.event_id])).rows.every(b=>b.status==='cancelled'));
 const ea=(await db.query('select * from core.events where id=$1',[eventIds[0]])).rows[0];
 combined=await call(coach,"select api.preview_booking_change($1,'event_all',$2,$3,$4::uuid[],$5::uuid[])",[anchor.id,plus(ea.starts_at,1),plus(ea.ends_at,1),[locker],[pitch]]);
 assert.ok(combined.future_plan);assert.equal(combined.conflicts.length,0);
 await call(coach,"select api.execute_booking_command($1,'update_booking',$2::jsonb,null)",[await uuid(),JSON.stringify(changePayload(combined))]);
 d=await get(coach,anchor.id);assert.equal(d.plan.configuration.start_time,'15:00:00');assert.ok(d.plan.configuration.resources.some(r=>r.resource_id===locker));
 assert.equal((await call(stranger,'select api.list_booking_series_plans($1)',[org])).length,0);
 console.log('future plans: rolling generation, blocked atomic occurrences, identity/history, retry/replay, rights revocation/pause, combined future conflicts, monthly/DST, activities and individual margins passed');
}
