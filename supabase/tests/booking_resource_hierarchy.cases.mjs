import assert from 'node:assert/strict';

export async function checkResourceHierarchy({db,call,fails,owner,friend,stranger,org}) {
 const base={name:'Whole',category:'pitch',ownership_kind:'owned',timezone:'UTC',requires_approval:true};
 const save=(id,details,revision=null,who=owner)=>call(who,'select api.save_booking_resource_v2($1,$2,$3::jsonb,$4)',[org,id,JSON.stringify({...base,...details}),revision]);
 const whole=await save(null,{});
 const halfA=await save(null,{name:'Half A',parent_resource_id:whole});
 const halfB=await save(null,{name:'Half B',parent_resource_id:whole});
 const quarterA=await save(null,{name:'Quarter A1',parent_resource_id:halfA});
 const quarterB=await save(null,{name:'Quarter A2',parent_resource_id:halfA});
 const eighth=await save(null,{name:'Eighth A1a',parent_resource_id:quarterA});
 const independent=await save(null,{name:'Independent'});
 const day=new Date(Date.now()+65*86400e3).toISOString().slice(0,10);
 const from=`${day}T10:00Z`,to=`${day}T11:00Z`;
 const book=(r,start=from,end=to)=>call(friend,'select api.create_booking($1,$2,$3,null,null,null,null)',[r,start,end]);
 const blocked=(r)=>fails(friend,'select api.create_booking($1,$2,$3,null,null,null,null)',[r,from,to],/resource_busy/);
 const first=await book(eighth);assert.equal(first.status,'pending');
 for(const r of [quarterA,halfA,whole])await blocked(r);
 const cousin=await book(quarterB);await book(halfB); // independent branches remain available
 const separate=await book(independent);
 const free=await call(friend,'select api.list_booking_availability($1,$2,$3)',[org,from,to]);
 for(const r of [whole,halfA,quarterA,eighth])assert.equal(free.find(x=>x.resource_id===r).busy,true);
 assert.equal(free.find(x=>x.resource_id===whole).busy_resource_id,eighth);
 const group=await call(friend,'select api.create_booking_group($1::uuid[],$2,$3,null,null,null,null,true)',[[whole,quarterA],`${day}T12:00Z`,`${day}T13:00Z`]);
 assert.ok(group.items.every(x=>x.busy),'ancestor and descendant cannot be selected together, even without existing bookings');
 await fails(friend,'select api.create_booking_group($1::uuid[],$2,$3,null,null,null,null,false)',[[whole,quarterA],`${day}T12:00Z`,`${day}T13:00Z`],/resource_busy/);
 const siblings=await call(friend,'select api.create_booking_group($1::uuid[],$2,$3,null,null,null,null,false)',[[quarterA,quarterB],`${day}T12:00Z`,`${day}T13:00Z`]);assert.ok(siblings.group_id);
 const series=await call(friend,"select api.create_booking_series($1,'{1,2,3,4,5,6,7}'::smallint[],1::smallint,$2::date,$2::date,'10:00','11:00','UTC',null,null,null,true)",[whole,day]);assert.equal(series.times[0].clash,true);
 // Inserting another subdivision rebuilds claims of already booked parents.
 const childB=await save(null,{name:'Quarter B1',parent_resource_id:halfB});await blocked(childB);
 await fails(owner,'select api.save_booking_resource_v2($1,$2,$3::jsonb,1)',[org,independent,JSON.stringify({...base,parent_resource_id:eighth})],/hierarchy_has_bookings/);
 assert.equal((await call(owner,'select api.get_booking_organization($1)',[org])).resources.find(x=>x.id===independent).parent_resource_id,null);
 // Self, ancestor-under-descendant, cross-organization and unauthorized edits.
 for(const parent of [whole,eighth])await fails(owner,'select api.save_booking_resource_v2($1,$2,$3::jsonb,1)',[org,whole,JSON.stringify({...base,parent_resource_id:parent})],/invalid_resource_hierarchy/);
 const otherOrg=await call(owner,"select api.create_booking_organization('Other hierarchy','other',null)");
 const other=await call(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[otherOrg,JSON.stringify(base)]);
 await fails(owner,'select api.save_booking_resource_v2($1,$2,$3::jsonb,1)',[org,independent,JSON.stringify({...base,parent_resource_id:other})],/invalid_resource_hierarchy/);
 await fails(friend,'select api.save_booking_resource_v2($1,$2,$3::jsonb,1)',[org,halfA,JSON.stringify({...base,parent_resource_id:null})],/not_admin/);
 await fails(stranger,'select api.get_booking_organization($1)',[org],/not_found/);
 // Atomic multirow changes cannot introduce a cycle either.
 const cycleA=await save(null,{name:'Cycle A'}),cycleB=await save(null,{name:'Cycle B'});
 await db.exec('savepoint cyclic_hierarchy');
 await assert.rejects(db.query('update core.booking_resources set parent_resource_id=case when id=$1 then $2::uuid else $1::uuid end where id in ($1,$2)',[cycleA,cycleB]),/invalid_resource_hierarchy/);
 await db.exec('rollback to cyclic_hierarchy');
 // Verify the exclusion constraint even without the friendly pre-check (local DB only).
 await db.exec('savepoint claim_invariant; alter table core.booking_bookings disable trigger booking_00_hierarchy');
 await assert.rejects(db.query("insert into core.booking_bookings(organization_id,resource_id,starts_at,ends_at,status,booked_by) values($1,$2,$3,$4,'confirmed',$5)",[org,whole,from,to,owner]),/booking_leaf_no_overlap/);
 await db.exec('rollback to claim_invariant');
 // Local hours and periods of ancestors constrain every descendant.
 await fails(owner,'select api.save_booking_resource_v2($1,$2,$3::jsonb,1)',[org,whole,JSON.stringify({...base,availability:{mode:'weekly',weekly:[],exceptions:[]}})],/disposition_has_bookings/);
 const limited=await save(null,{name:'Closed parent',availability:{mode:'weekly',weekly:[],exceptions:[]}});
 const limitedChild=await save(null,{name:'Child of closed parent',parent_resource_id:limited});
 await fails(friend,'select api.create_booking($1,$2,$3,null,null,null,null)',[limitedChild,from,to],/resource_outside_disposition/);
 const fresh=await save(null,{name:'Reparented'});await book(fresh,`${day}T15:00Z`,`${day}T16:00Z`);
 await fails(owner,'select api.save_booking_resource_v2($1,$2,$3::jsonb,1)',[org,fresh,JSON.stringify({...base,parent_resource_id:limited})],/hierarchy_has_bookings/);
 // Old v2 clients retain parent linkage, and stale revisions cannot move it.
 await save(quarterA,{name:'Quarter A1 renamed'},1);
 assert.equal((await call(owner,'select api.get_booking_organization($1)',[org])).resources.find(x=>x.id===quarterA).parent_resource_id,halfA);
 await fails(owner,'select api.save_booking_resource_v2($1,$2,$3::jsonb,1)',[org,quarterA,JSON.stringify({...base,parent_resource_id:null})],/stale_revision/);
 // Cancelling frees ancestors after every overlapping descendant is cancelled.
 await call(friend,'select api.cancel_booking($1)',[first.id]);await call(friend,'select api.cancel_booking($1)',[cousin.id]);
 await book(halfA);
 await call(friend,'select api.cancel_booking($1)',[separate.id]);
 await save(independent,{name:'Now a child',parent_resource_id:halfA},1);
 assert.equal((await db.query("select has_table_privilege('authenticated','internal.booking_resource_claims','select') allowed")).rows[0].allowed,false);
 // Organization cleanup cascades through a subdivided resource and its claims.
 const cleanupOrg=await call(owner,"select api.create_booking_organization('Hierarchy cleanup','other',null)");
 const cleanupParent=await call(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[cleanupOrg,JSON.stringify(base)]);
 const cleanupChild=await call(owner,'select api.save_booking_resource_v2($1,null,$2::jsonb,null)',[cleanupOrg,JSON.stringify({...base,parent_resource_id:cleanupParent})]);
 await call(owner,'select api.create_booking($1,$2,$3,null,null,null,null)',[cleanupChild,from,to]);
 await db.query('delete from core.booking_organizations where id=$1',[cleanupOrg]);
 assert.equal((await db.query('select count(*)::integer total from internal.booking_resource_claims where organization_id=$1',[cleanupOrg])).rows[0].total,0);
 console.log('resource hierarchy: whole/half/quarter/eighth, independent branches, cycles, claims, schedules, groups, series and revisions passed');
}
