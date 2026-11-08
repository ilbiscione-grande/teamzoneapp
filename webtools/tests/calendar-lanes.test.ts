import test from 'node:test';
import assert from 'node:assert/strict';
import { calendarLanes } from '../lib/calendar-lanes.ts';
test('simultaneous bookings have separate lanes while touching bookings reuse space',()=>{
 const input=[{id:'A',top:0,height:.2},{id:'B',top:.1,height:.2},{id:'C',top:.2,height:.1},{id:'D',top:.3,height:.1}];
 const output=calendarLanes(input);
 assert.deepEqual(output.map(row=>[row.item.id,row.lane,row.lanes]),[['A',0,2],['B',1,2],['C',0,2],['D',0,2]]);
 for(const a of output) for(const b of output) if(a!==b && a.item.top < b.item.top+b.item.height-1e-10 && b.item.top < a.item.top+a.item.height-1e-10) assert.notEqual(a.lane,b.lane);
});
test('layout is deterministic, does not change input and handles empty weeks',()=>{
 const input=[{id:'B',top:0,height:.3},{id:'A',top:0,height:.1}];
 assert.deepEqual(calendarLanes(input),calendarLanes([...input].reverse()));
 assert.equal(input[0].id,'B');
 assert.deepEqual(calendarLanes([]),[]);
});
