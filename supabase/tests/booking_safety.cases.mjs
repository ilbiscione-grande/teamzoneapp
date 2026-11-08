import assert from 'node:assert/strict';

export async function checkBookingSafety({db,call,fails,owner,friend,coach,clubAdmin,stranger,clubOrg,team,event,org,pitch,bus,t,id}) {
  const command = (who,key,type,payload,revisions=null) => call(who,
    'select api.execute_booking_command($1,$2,$3::jsonb,$4::jsonb)',
    [key,type,JSON.stringify(payload),revisions && JSON.stringify(revisions)]);
  const create = {target_resource_id:bus,booking_starts_at:t(500),booking_ends_at:t(502),booking_title:'Retry test'};
  const b = await command(friend,id(200),'create_booking',create);
  assert.equal(b.status,'pending');
  assert.equal(b.revision,1);
  assert.deepEqual(await command(friend,id(200),'create_booking',create),b,'same intent returns original result');
  assert.equal(Number((await db.query('select count(*) from core.booking_bookings where id=$1',[b.id])).rows[0].count),1);
  await fails(friend,'select api.execute_booking_command($1,$2,$3::jsonb,null)',[id(200),'create_booking',JSON.stringify({...create,booking_title:'Changed'})],/idempotency_conflict/);
  await fails(owner,'select api.execute_booking_command($1,$2,$3::jsonb,$4::jsonb)',
    [id(201),'decide_booking',JSON.stringify({target_booking_id:b.id,approve:true}),JSON.stringify({[b.id]:0})],/stale_revision/);
  await fails(stranger,'select api.execute_booking_command($1,$2,$3::jsonb,$4::jsonb)',
    [id(201),'decide_booking',JSON.stringify({target_booking_id:b.id,approve:true}),JSON.stringify({[b.id]:1})],/not_allowed/);
  await command(owner,id(201),'decide_booking',{target_booking_id:b.id,approve:true},{[b.id]:1});
  await command(owner,id(201),'decide_booking',{target_booking_id:b.id,approve:true},{[b.id]:1});
  assert.equal((await call(owner,'select api.list_booking_history($1)',[b.id])).length,2,'retry neither updates nor audits twice');
  await fails(friend,'select api.list_booking_history($1)',[b.id],/not_found/);
  await command(friend,id(202),'cancel_booking',{target_booking_id:b.id},{[b.id]:2});
  await fails(owner,'select api.decide_booking($1,true)',[b.id],/not_pending/,'legacy RPC cannot resurrect a cancelled booking');
  const replacement = await command(friend,id(203),'create_booking',create);
  assert.notEqual(replacement.id,b.id);
  // Even privileged writes bypassing the RPC protocol cannot overlap a resource.
  await db.exec('savepoint invariant');
  await assert.rejects(db.query("update core.booking_bookings set status='confirmed' where id=$1",[b.id]), /booking_no_overlap/);
  await db.exec('rollback to invariant');
  await db.exec('savepoint direct_insert');
  await assert.rejects(db.query("insert into core.booking_bookings(organization_id,resource_id,starts_at,ends_at,status,booked_by) values($1,$2,$3,$4,'confirmed',$5)",[org,bus,t(501),t(503),owner]), /booking_no_overlap/);
  await db.exec('rollback to direct_insert');
  const audit = await call(owner,'select api.list_booking_history($1)',[b.id]);
  assert.deepEqual(audit.map(x=>[x.operation,x.after_row.status]),[['INSERT','pending'],['UPDATE','confirmed'],['UPDATE','cancelled']]);
  assert.equal(audit[2].actor_id,friend);

  const groupPayload = {target_resource_ids:[pitch,bus],booking_starts_at:t(550),booking_ends_at:t(552)};
  const group = await command(friend,id(210),'create_booking_group',groupPayload);
  assert.deepEqual(await command(friend,id(210),'create_booking_group',groupPayload),group);
  const rows = (await call(owner,'select api.list_bookings($1,$2,$3)',[org,t(549),t(553)])).filter(b=>b.group_id===group.group_id);
  assert.equal(Object.keys(rows[0].revisions).length,2);
  await command(friend,id(211),'cancel_booking',{target_booking_id:rows[0].id},{[rows[0].id]:1});
  await fails(owner,'select api.execute_booking_command($1,$2,$3::jsonb,$4::jsonb)',
    [id(212),'decide_booking_group',JSON.stringify({target_group_id:group.group_id,approve:true}),JSON.stringify(rows[0].revisions)],/stale_revision/);

  const targets = await call(clubAdmin,'select api.list_event_booking_targets($1)',[event]);
  assert.equal(targets[0].team_id,team);
  const details = await call(clubAdmin,'select api.get_booking_organization($1)',[clubOrg]);
  assert.ok(details.teams.some(t=>t.team_id===team));
  const resource = details.resources.find(r=>r.active);
  const adminPayload = {target_resource_ids:[resource.id],booking_starts_at:t(600),booking_ends_at:t(601),target_team_id:team,target_event_id:event};
  await command(clubAdmin,id(220),'create_booking_group',adminPayload);
  const events = await call(clubAdmin,'select api.list_booking_team_events($1,$2)',[clubOrg,team]);
  assert.ok(events.some(e=>e.event_id===event));
  // A resource administrator cannot attach another club's activity.
  await fails(owner,'select api.create_booking($1,$2,$3,null,null,$4,$5)',[pitch,t(600),t(601),team,event],/not_team_leader|event_not_found/);
  // Series commands use the same retry ledger and aggregate revision contract.
  const day = new Date(Date.now()+30*86400e3).toISOString().slice(0,10);
  const seriesPayload = {target_resource_id:bus,series_weekdays:[1,2,3,4,5,6,7],series_interval:1,
    first_day:day,last_day:day,start_at:'08:00',end_at:'09:00',zone:'Europe/Stockholm'};
  const series = await command(friend,id(230),'create_booking_series',seriesPayload);
  assert.equal(series.created,1);
  assert.deepEqual(await command(friend,id(230),'create_booking_series',seriesPayload),series);
  const member = (await db.query('select id,revision from core.booking_bookings where series_id=$1',[series.series_id])).rows[0];
  assert.equal(await command(owner,id(231),'decide_booking_series',{target_series_id:series.series_id,approve:true},{[member.id]:1}),1);
  assert.equal(await command(friend,id(232),'cancel_booking_series',{target_series_id:series.series_id},{[member.id]:2}),1);
  await db.query("update core.events set state='cancelled' where id=$1",[event]);
  await fails(clubAdmin,'select api.create_booking_group($1::uuid[],$2,$3,null,null,$4,$5,false)',[[resource.id],t(620),t(621),team,event],/event_not_found/);
  await db.query("update core.events set state='scheduled' where id=$1",[event]);
  await fails(null,'select api.execute_booking_command($1,$2,$3::jsonb,null)',[id(240),'create_booking',JSON.stringify(create)],/unauthenticated/);
  assert.equal((await db.query("select has_function_privilege('anon','api.execute_booking_command(uuid,text,jsonb,jsonb)','execute') allowed")).rows[0].allowed,false);
  assert.equal((await db.query("select has_table_privilege('authenticated','internal.booking_audit','select') allowed")).rows[0].allowed,false);
  console.log('booking safety: idempotency, revisions, audit, storage invariant and admin activity booking passed');
}
