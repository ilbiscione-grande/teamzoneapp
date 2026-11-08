import assert from 'node:assert/strict';

export async function checkResourceSchedule({db,call,fails,owner,friend,stranger,org}) {
 const base={name:'Veckohall',category:'hall',ownership_kind:'owned',timezone:'UTC',available_from:null,available_until:null,requires_approval:true};
 const day=new Date(Date.now()+40*86400e3).toISOString().slice(0,10);
 const next=n=>{const d=new Date(day+'T12:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
 const weekday=(new Date(day+'T12:00Z').getUTCDay()||7);
 const plan={mode:'weekly',weekly:[{day:weekday,start:480,end:600},{day:weekday,start:600,end:720}],exceptions:[{date:next(7),windows:[]},{date:next(1),windows:[{start:900,end:1020}]}]};
 const save=(resource,availability=plan,revision=null)=>call(owner,'select api.save_booking_resource_v2($1,$2,$3::jsonb,$4)',[org,resource,JSON.stringify({...base,availability}),revision]);
 const resource=await save(null);
 const booking=(d,from,to)=>call(friend,'select api.create_booking($1,$2,$3,null,null,null,null)',[resource,`${d}T${from}Z`,`${d}T${to}Z`]);
 const rejected=(d,from,to)=>fails(friend,'select api.create_booking($1,$2,$3,null,null,null,null)',[resource,`${d}T${from}Z`,`${d}T${to}Z`],/resource_outside_disposition/);
 const valid=await booking(day,'08:00','12:00'); // adjacent windows form a single interval
 assert.equal(valid.status,'pending','pending bookings also protect their disposition');
 await rejected(day,'07:59','08:00');await rejected(day,'12:00','12:01');
 await rejected(next(7),'09:00','10:00'); // closed override
 await rejected(next(1),'14:00','15:00');
 await booking(next(1),'15:00','17:00'); // extra hours on an otherwise closed weekday
 await fails(owner,'select api.save_booking_resource_v2($1,$2,$3::jsonb,1)',[org,resource,JSON.stringify({...base,availability:{...plan,weekly:[]}})],/disposition_has_bookings/);
 // Older v2 clients omitting the new field must preserve the schedule.
 await call(owner,'select api.save_booking_resource_v2($1,$2,$3::jsonb,1)',[org,resource,JSON.stringify({...base,name:'Renamed'})]);
 assert.deepEqual((await call(owner,'select api.get_booking_organization($1)',[org])).resources.find(r=>r.id===resource).availability,plan);
 await rejected(next(7),'09:00','10:00');
 await fails(owner,'select api.save_booking_resource_v2($1,$2,$3::jsonb,1)',[org,resource,JSON.stringify({...base,availability:plan})],/stale_revision/);
 const free=await call(friend,'select api.list_booking_availability($1,$2,$3)',[org,next(7)+'T09:00Z',next(7)+'T10:00Z']);
 assert.equal(free.find(r=>r.resource_id===resource).busy,true);
 const group=await call(friend,'select api.create_booking_group($1::uuid[],$2,$3,null,null,null,null,true)',[[resource],next(7)+'T09:00Z',next(7)+'T10:00Z']);assert.equal(group.items[0].busy,true);
 const series=await call(friend,"select api.create_booking_series($1,$2::smallint[],1::smallint,$3::date,$4::date,'09:00','10:00','UTC',null,null,null,true)",[resource,[weekday],next(7),next(14)]);
 assert.deepEqual(series.times.map(t=>t.outside_disposition),[true,false]);
 const actual=await call(friend,"select api.create_booking_series($1,$2::smallint[],1::smallint,$3::date,$4::date,'09:00','10:00','UTC',null,null,null,false)",[resource,[weekday],next(7),next(14)]);
 assert.equal(actual.created,1);
 await db.exec('savepoint direct_hours');
 await assert.rejects(db.query("insert into core.booking_bookings(organization_id,resource_id,starts_at,ends_at,status,booked_by) values($1,$2,$3,$4,'confirmed',$5)",[org,resource,next(7)+'T09:00Z',next(7)+'T10:00Z',owner]),/resource_outside_disposition/);
 await db.exec('rollback to direct_hours');
 // Missing, malformed, duplicate and oversized structures are rejected atomically.
 for(const invalid of [null,{}, {...plan,mode:'x'},{...plan,weekly:{}},{...plan,weekly:[{day:0,start:1,end:2}]},{...plan,weekly:[{day:1,start:2,end:1}]},{...plan,weekly:[{day:1,start:1.5,end:3}]},{...plan,weekly:[{day:1,start:0,end:1441}]},{...plan,exceptions:[{date:'2030-02-30',windows:[]}]},{...plan,exceptions:[plan.exceptions[0],plan.exceptions[0]]},{...plan,exceptions:[{date:day,windows:null}]}]){
  await fails(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[org,JSON.stringify({...base,availability:invalid})],/invalid_availability/);
 }
 await fails(friend,'select api.save_booking_resource_v2($1,$2,$3::jsonb,2)',[org,resource,JSON.stringify({...base,availability:plan})],/not_admin/);
 await fails(stranger,'select api.get_booking_organization($1)',[org],/not_found/);
 // A gap remains closed; coverage must include the entire requested interval.
 const gap=await save(null,{mode:'weekly',weekly:[{day:weekday,start:480,end:540},{day:weekday,start:600,end:660}],exceptions:[]});
 assert.equal((await db.query('select internal.booking_within_disposition(r,$2,$3) ok from core.booking_resources r where id=$1',[gap,day+'T08:00Z',day+'T11:00Z'])).rows[0].ok,false);
 // Midnight joins neighbouring local days; no artificial gap at 00:00.
 const overnight=await save(null,{mode:'weekly',weekly:[{day:weekday,start:1320,end:1440},{day:weekday%7+1,start:0,end:120}],exceptions:[]});
 await call(friend,'select api.create_booking($1,$2,$3,null,null,null,null)',[overnight,day+'T22:00Z',next(1)+'T02:00Z']);
 // Full local DST dates remain 23/25 hours. Repeated 02:xx uses PG standard time.
 const year=new Date().getUTCFullYear()+2;
 for(const [month,hours] of [[2,23],[9,25]]){
  const d=new Date(Date.UTC(year,month+1,0));d.setUTCDate(d.getUTCDate()-d.getUTCDay());const date=d.toISOString().slice(0,10);
  const dst=await call(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[org,JSON.stringify({...base,timezone:'Europe/Stockholm',availability:{mode:'weekly',weekly:[{day:7,start:0,end:1440}],exceptions:[]}})]);
  const bounds=(await db.query("select $1::date::timestamp at time zone 'Europe/Stockholm' lo,($1::date+1)::timestamp at time zone 'Europe/Stockholm' hi",[date])).rows[0];
  assert.equal((new Date(bounds.hi)-new Date(bounds.lo))/3600e3,hours);
  await call(friend,'select api.create_booking($1,$2,$3,null,null,null,null)',[dst,bounds.lo,bounds.hi]);
  const narrow=await call(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[org,JSON.stringify({...base,timezone:'Europe/Stockholm',availability:{mode:'weekly',weekly:[{day:7,start:150,end:180}],exceptions:[]}})]);
  if(month===2) {
   const check=(await db.query('select internal.booking_within_disposition(r,$2,$3) ok from core.booking_resources r where id=$1',[narrow,date+'T01:00Z',date+'T01:30Z'])).rows[0];
   assert.equal(check.ok,false,'window in the missing hour collapses without raising');
  } else {
   for(const [hour,expected] of [['00',false],['01',true]]) {
    assert.equal((await db.query('select internal.booking_within_disposition(r,$2,$3) ok from core.booking_resources r where id=$1',[narrow,`${date}T${hour}:30Z`,`${date}T${hour}:45Z`])).rows[0].ok,expected,'ambiguous boundary uses second, standard-time occurrence');
   }
  }
 }
 // Cancellation permits a later schedule restriction; pending/confirmed remain protected.
 await call(owner,'select api.cancel_booking($1)',[valid.id]);
 await save(resource,{...plan,exceptions:[...plan.exceptions,{date:day,windows:[]}]},2);
 console.log('resource schedule: coverage, overrides, midnight, DST, legacy clients, revisions, groups and series passed');
}
