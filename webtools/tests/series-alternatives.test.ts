import test from 'node:test';
import assert from 'node:assert/strict';
import { checkedSeriesCandidate, seriesCandidates, seriesScopeLabel } from '../lib/series-alternatives.ts';
import type { Resource, SeriesTime } from '../lib/booking.ts';
const resource=(id:string,extra:Partial<Resource>={}):Resource=>({id,name:id,category:'pitch',active:true,description:null,location:null,capacity:null,requires_approval:false,...extra});
const layout={A:'A',B:'B',A1:'A1',A2:'A2',B1:'B1',B2:'B2'};
const resources=[resource('root',{pitch_layout:layout}),...['A','B'].map(id=>resource(id,{parent_resource_id:'root'})),...['A1','A2','B1','B2'].map(id=>resource(id,{parent_resource_id:id[0]}))];
const slot:SeriesTime={starts_at:'2030-06-12T12:00:00Z',ends_at:'2030-06-12T13:30:00Z',clash:true};
test('a three-quarter alternative has one short owner-configured scope label',()=>{
 assert.equal(seriesScopeLabel(['A1','A2','B1'],resources),'root · ¾-plan · allt utom B2');
 assert.equal(seriesScopeLabel(['room'],[resource('room',{category:'room'})]),'room');
});
test('time suggestions preserve date, duration, original identity and all selected parts',()=>{
 const options=seriesCandidates(slot,['A1','A2','B1'],resources);
 assert.equal(options.length,11);
 for(const item of options){assert.equal(item.original_starts_at,slot.starts_at);assert.equal(new Date(item.ends_at).getTime()-new Date(item.starts_at).getTime(),90*60000);assert.equal(item.starts_at.slice(0,10),slot.starts_at.slice(0,10));assert.equal(item.resource_ids.length,3);}
});
test('half, quarter and full alternatives retain physical coverage',()=>{
 const sameTime=(ids:string[])=>seriesCandidates(slot,ids,resources).filter(x=>x.starts_at===slot.starts_at).map(x=>x.resource_ids);
 assert.deepEqual(sameTime(['A']),[['B']]);
 assert.deepEqual(sameTime(['A1']),[['A2'],['B1'],['B2']]);
 assert.deepEqual(sameTime(['root']),[]);
 assert.deepEqual(sameTime(['A','B1']),[]);
});
test('changed occurrences retain original identity; resources with no owner layout only offer time changes',()=>{
 const options=seriesCandidates({...slot,original_starts_at:'2030-06-12T10:00:00Z',resource_ids:['B']},['A'],resources);
 assert.ok(options.every(x=>x.original_starts_at==='2030-06-12T10:00:00Z'));
 assert.deepEqual(options[0].resource_ids,['B']);
 assert.equal(seriesCandidates(slot,['room'],[resource('room',{category:'room'})]).length,8);
});
test('incomplete, duplicate, busy and malformed checks never enable an alternative',()=>{
 assert.equal(checkedSeriesCandidate(['A','B'],{items:[{resource_id:'A',busy:false},{resource_id:'B',busy:false}]}),true);
 for(const data of [null,{}, {items:[]},{items:[{resource_id:'A',busy:false}]},{items:[{resource_id:'A',busy:false},{resource_id:'B',busy:true}]},{items:[{resource_id:'A',busy:false},{resource_id:'A',busy:false}]},{items:[{resource_id:'A',busy:false},{resource_id:'B'}]}])assert.equal(checkedSeriesCandidate(['A','B'],data),false);
});
