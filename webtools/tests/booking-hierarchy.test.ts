import test from 'node:test';
import assert from 'node:assert/strict';
import { resourceCanContain, resourcePath, resourceTree, type Resource } from '../lib/booking.ts';

const resource=(id:string,name:string,parent_resource_id:string|null=null):Resource=>({id,name,parent_resource_id,category:'pitch',description:null,location:null,capacity:null,requires_approval:false,active:true});
const resources=[resource('whole','Helplan'),resource('half','Halvplan','whole'),resource('quarter','Kvartsplan','half'),resource('other','Andra halvplanen','whole')];

test('availability tree keeps parents before descendants across categories and inactive parents',()=>{
 const items=[{...resources[2],category:'equipment' as const},resources[3],{...resources[0],active:false},resources[1]];
 const tree=resourceTree(items);
 assert.deepEqual(tree.map(x=>[x.resource.id,x.depth]),[['whole',0],['other',1],['half',1],['quarter',2]]);
 assert.equal(tree[0].resource.active,false);
 assert.equal(resourceTree([resource('a','A','b'),resource('b','B','a')]).length,2);
});
test('subdivision labels retain the complete whole/half/quarter path',()=>{
 assert.equal(resourcePath(resources[2],resources),'Helplan → Halvplan → Kvartsplan');
});
test('parent choices exclude self and every descendant while keeping other branches',()=>{
 assert.equal(resourceCanContain(resources[0],'whole',resources),false);
 assert.equal(resourceCanContain(resources[2],'whole',resources),false);
 assert.equal(resourceCanContain(resources[2],'half',resources),false);
 assert.equal(resourceCanContain(resources[3],'half',resources),true);
 assert.equal(resourceCanContain(resources[0],null,resources),true);
});
test('partial and malformed legacy paths remain bounded',()=>{
 assert.equal(resourcePath(resource('a','A','missing'),resources),'A');
 const cycle=[resource('a','A','b'),resource('b','B','a')];
 assert.equal(resourceCanContain(cycle[0],null,cycle),false);
 assert.equal(resourcePath(cycle[0],cycle),'B → A');
});
