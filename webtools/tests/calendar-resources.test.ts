import test from 'node:test';
import assert from 'node:assert/strict';
import { calendarCards, calendarResources, physicalResource } from '../lib/calendar-resources.ts';
import type { Booking, Resource } from '../lib/booking.ts';
const r=(id:string,parent_resource_id:string|null=null,category:Resource['category']='pitch'):Resource=>({id,name:id,parent_resource_id,category,active:true,requires_approval:false,description:null,location:null,capacity:null});
const root={...r('Konstgräs'),pitch_layout:{A:'A',B:'B',A1:'A1',A2:'A2',B1:'B1',B2:'B2'}};
const resources=[root,r('A',root.id),r('B',root.id),r('A1','A'),r('A2','A'),r('B1','B'),r('B2','B'),r('Room',null,'locker_room')];
const b=(id:string,resource_id:string,extra:Partial<Booking>={}):Booking=>({id,resource_id,resource_name:resource_id,group_id:'group',starts_at:'2026-11-05T17:00Z',ends_at:'2026-11-05T19:00Z',title:'Training',status:'confirmed',...extra} as Booking);
test('a physical pitch has one column including every nested part; other types stay separate',()=>{
 assert.deepEqual(calendarResources(resources,resources).map(r=>r.id),['Konstgräs','Room']);
 assert.equal(calendarResources([resources[3]],resources)[0].id,'Konstgräs');
 assert.equal(physicalResource(r('orphan','missing'),resources).id,'orphan');
});
test('three quarters booked together become one card while locker stays separate',()=>{
 const cards=calendarCards([b('1','A1'),b('2','A2'),b('3','B1'),b('4','Room')],resources);
 assert.equal(cards.length,2);
 assert.deepEqual(cards[0].coverage,['A1','A2','B1']);
 assert.equal(cards[0].label,'¾ plan · utom B2');
 assert.equal(cards[0].bookings.length,3);
});
test('whole, half and quarter coverage are explicit and independent bookings are not merged',()=>{
 const cards=calendarCards([b('1','Konstgräs',{group_id:null}),b('2','A',{group_id:null}),b('3','B1',{group_id:null})],resources);
 assert.deepEqual(cards.map(c=>c.coverage?.length),[4,2,1]);
 assert.deepEqual(cards.map(c=>c.label),['Helplan','½ plan · A','¼ plan · B1']);
 assert.equal(calendarCards([b('1','A1'),b('2','A2',{group_id:'different'})],resources).length,2);
});
test('different times, states, events and physical pitches are never merged',()=>{
 for(const extra of [{starts_at:'2026-11-06T17:00Z'},{status:'pending' as const},{event_id:'another'},{title:'Other'}]) assert.equal(calendarCards([b('1','A1'),b('2','A2',extra)],resources).length,2);
 assert.equal(calendarCards([b('1','A1'),b('2','Other')],[...resources,r('Other')]).length,2);
});
test('legacy and edited layouts do not acquire invented fractions',()=>{
 const legacy=resources.map(r=>r.id===root.id?{...r,pitch_layout:null}:r);
 const card=calendarCards([b('1','A1'),b('2','A2')],legacy)[0];
 assert.equal(card.label,'A1 + A2');assert.equal(card.coverage,null);
 assert.equal(calendarCards([b('1','A1')],[...resources,r('eighth','A1')])[0].coverage,null);
});
