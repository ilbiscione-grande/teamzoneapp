import test from 'node:test';
import assert from 'node:assert/strict';
import { pitchOptions, dispositionLabel } from '../lib/pitch-options.ts';
import type { Resource } from '../lib/booking.ts';
const r=(id:string,parent_resource_id:string|null=null):Resource=>({id,name:id,parent_resource_id,category:'pitch',active:true,description:null,location:null,capacity:null,requires_approval:false});
const layout={A:'A',B:'B',A1:'A1',A2:'A2',B1:'B1',B2:'B2'};
const root={...r('root'),pitch_layout:layout};
const resources=[root,r('A','root'),r('B','root'),r('A1','A'),r('A2','A'),r('B1','B'),r('B2','B')];
test('owner setup offers full, halves, quarters and every physical three-quarter combination',()=>{
 const options=pitchOptions(root,resources);
 assert.equal(options.length,11);
 assert.deepEqual(options.find(item=>item.id==='three-A1')?.resourceIds,['A2','B1','B2']);
 assert.deepEqual(options.find(item=>item.id==='A')?.resourceIds,['A']);
 for(const option of options.filter(item=>item.id.startsWith('three-'))) {
  assert.equal(new Set(option.resourceIds).size,3);
  assert.ok(!option.resourceIds.includes(option.id.slice(6)));
 }
});
test('ordinary and legacy trees do not acquire assumed fractions',()=>{
 assert.deepEqual(pitchOptions({...root,pitch_layout:null},resources),[]);
 assert.deepEqual(pitchOptions(undefined,resources),[]);
});

test('extent is not repeated when an owner name already starts with it',()=>{
 const named=resources.map(item=>({...item,name:item.id==='A'?'Halvplan A':item.id==='B2'?'  fjärdedelsplan B2  ':item.name}));
 const options=pitchOptions(named[0],named);
 assert.equal(options.find(item=>item.id==='A')?.label,'Halvplan A');
 assert.equal(options.find(item=>item.id==='B2')?.label,'fjärdedelsplan B2');
 assert.equal(options.find(item=>item.id==='A1')?.label,'Fjärdedelsplan · A1');
 assert.deepEqual(options.map(item=>item.resourceIds),pitchOptions(root,resources).map(item=>item.resourceIds));
 assert.equal(named.find(item=>item.id==='B2')?.name,'  fjärdedelsplan B2  ');
});

test('custom names retain their full identity and missing extents stay explicit',()=>{
 const named=resources.map(item=>({...item,name:item.id==='A'?'Norra halvan':item.id==='B2'?'Fjärdedelsplansytan vid klubbstugan':item.name}));
 const options=pitchOptions(named[0],named);
 assert.equal(options.find(item=>item.id==='A')?.label,'Halvplan · Norra halvan');
 assert.equal(options.find(item=>item.id==='B2')?.label,'Fjärdedelsplan · Fjärdedelsplansytan vid klubbstugan');
 assert.equal(options.find(item=>item.id==='three-A1')?.label,'¾-plan · allt utom A1');
});
test('incomplete, inactive, moved or further divided layouts fail closed',()=>{
 for(const invalid of [resources.slice(0,-1),resources.map(item=>item.id==='A1'?{...item,active:false}:item),resources.map(item=>item.id==='A1'?{...item,parent_resource_id:'B'}:item),[...resources,r('extra','root')],[...resources,r('eighth','A1')]]) assert.deepEqual(pitchOptions(root,invalid),[]);
 assert.deepEqual(pitchOptions({...root,active:false},resources),[]);
});
test('external disposition without end is clearly indefinite',()=>{
 assert.equal(dispositionLabel({...root,available_from:'2026-11-01',available_until:null}),'2026-11-01–tills vidare');
 assert.equal(dispositionLabel({...root,available_from:'2026-11-01',available_until:'2027-04-01'}),'2026-11-01–2027-04-01');
});
