import assert from 'node:assert/strict';

export async function checkResourceOwnership({db,call,fails,owner,friend,stranger,org,t,id}) {
 const day = new Date(Date.now()+20*86400e3).toISOString().slice(0,10);
 const next = n => {const d=new Date(day+'T12:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
 const details={name:'Kommunal hall',category:'hall',description:null,location:null,capacity:30,
   requires_approval:false,active:true,ownership_kind:'external',owner_name:'Kommunen',timezone:'UTC',available_from:day,available_until:day};
 const save=(who,resource,data=details,revision=null)=>call(who,
  'select api.save_booking_resource_v2($1,$2,$3::jsonb,$4)',[org,resource,JSON.stringify(data),revision]);
 const invalid=(data,pattern)=>fails(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[org,JSON.stringify(data)],pattern);
 await invalid({...details,owner_name:' '},/invalid_disposition/);
 await invalid({...details,available_until:null},/invalid_disposition/);
 await invalid({...details,available_until:next(-1)},/invalid_disposition/);
 await invalid({...details,timezone:'Imaginary/Place'},/invalid_timezone/);
 await fails(friend,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[org,JSON.stringify(details)],/not_admin/);
 const resource=await save(owner,null);
 const view=await call(owner,'select api.get_booking_organization($1)',[org]);
 const found=view.resources.find(r=>r.id===resource);
 assert.equal(found.ownership_kind,'external');assert.equal(found.owner_name,'Kommunen');assert.equal(found.timezone,'UTC');
 assert.equal(found.available_from,day);assert.equal(found.available_until,day);assert.equal(found.revision,1);
 assert.ok(view.resources.filter(r=>r.id!==resource).every(r=>r.ownership_kind==='unspecified'&&r.available_from===null),'old resources retain behavior without assuming actual ownership');
 await invalid({...details,ownership_kind:'unspecified',owner_name:null,available_from:null,available_until:null},/invalid_disposition/);
 const from=day+'T00:00:00Z', until=next(1)+'T00:00:00Z';
 const booking=await call(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[resource,from,until]);
 assert.equal(booking.status,'confirmed','both local date boundaries are inclusive');
 await fails(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[resource,next(-1)+'T23:59:00Z',from],/resource_outside_disposition/);
 await fails(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[resource,until,next(1)+'T01:00:00Z'],/resource_outside_disposition/);
 const availability=await call(friend,'select api.list_booking_availability($1,$2,$3)',[org,until,next(1)+'T01:00:00Z']);
 assert.equal(availability.find(r=>r.resource_id===resource).busy,true);
 assert.equal(availability.find(r=>r.resource_id===resource).busy_with,'Utanför resursens bokningsbara tider');
 const group=await call(friend,'select api.create_booking_group($1::uuid[],$2,$3,null,null,null,null,true)',[[resource],until,next(1)+'T01:00:00Z']);
 assert.equal(group.items[0].busy,true,'dry run agrees with write guard');
 await fails(owner,'select api.save_booking_resource_v2($1,$2,$3::jsonb,1)',[org,resource,JSON.stringify({...details,available_from:next(1),available_until:next(1)})],/disposition_has_bookings/);
 await fails(owner,'select api.save_booking_resource_v2($1,$2,$3::jsonb,0)',[org,resource,JSON.stringify(details)],/stale_revision/);
 await fails(owner,'select api.save_booking_resource_v2($1,$2,$3::jsonb,null)',[org,resource,JSON.stringify(details)],/revision_required/);
 await call(owner,'select api.cancel_booking($1)',[booking.id]);
 await save(owner,resource,{...details,available_from:next(1),available_until:next(1)},1);
 assert.equal((await call(owner,'select api.get_booking_organization($1)',[org])).resources.find(r=>r.id===resource).revision,2);
 const series=await call(friend,"select api.create_booking_series($1,'{1,2,3,4,5,6,7}'::smallint[],1::smallint,$2::date,$3::date,'10:00','11:00','UTC',null,null,null,true)",[resource,day,next(1)]);
 assert.deepEqual(series.times.map(x=>[x.clash,x.outside_disposition]),[[true,true],[false,false]]);
  const actual=await call(friend,"select api.create_booking_series($1,'{1,2,3,4,5,6,7}'::smallint[],1::smallint,$2::date,$3::date,'10:00','11:00','UTC',null,null,null,false)",[resource,day,next(1)]);
  assert.equal(actual.created,1,'series creates only the occurrence inside the right');
 // Direct writes also obey the period; failure rolls back without audit residue.
 await db.exec('savepoint direct_disposition');
 await assert.rejects(db.query("insert into core.booking_bookings(organization_id,resource_id,starts_at,ends_at,status,booked_by) values($1,$2,$3,$4,'confirmed',$5)",[org,resource,from,day+'T01:00Z',owner]),/resource_outside_disposition/);
 await db.exec('rollback to direct_disposition');

 // Date-only rights use local calendar days, including 23/25-hour DST days.
 const year=new Date().getUTCFullYear()+2;
 for(const [month,hours] of [[2,23],[9,25]]){
  const d=new Date(Date.UTC(year,month+1,0));d.setUTCDate(d.getUTCDate()-d.getUTCDay());
  const date=d.toISOString().slice(0,10);
  const external=await save(owner,null,{...details,name:'DST hall',timezone:'Europe/Stockholm',available_from:date,available_until:date});
  const bounds=(await db.query("select $1::date::timestamp at time zone 'Europe/Stockholm' starts_at,($1::date+1)::timestamp at time zone 'Europe/Stockholm' ends_at",[date])).rows[0];
  assert.equal((new Date(bounds.ends_at)-new Date(bounds.starts_at))/3600e3,hours);
  await call(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[external,bounds.starts_at,bounds.ends_at]);
 }
 assert.equal((await db.query("select has_function_privilege('anon','api.save_booking_resource_v2(uuid,uuid,jsonb,bigint)','execute') allowed")).rows[0].allowed,false);
 console.log('resource ownership: rights, local date boundaries, DST, revisions, legacy writes and previews passed');
}
