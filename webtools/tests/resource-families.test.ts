import test from "node:test";
import assert from "node:assert/strict";
import { resourceFamilies } from "../lib/resource-families.ts";
import type { Resource } from "../lib/booking.ts";
const r=(id:string,parent_resource_id:string|null=null,extra:Partial<Resource>={}):Resource=>({id,name:id,parent_resource_id,category:"pitch",active:true,description:null,location:null,capacity:null,requires_approval:false,...extra});
test("whole, half and quarter stay together including an inactive parent and a different category",()=>{
 const groups=resourceFamilies([r("quarter","half",{category:"equipment"}),r("other"),r("half","whole"),r("whole",null,{active:false})]);
 const family=groups.find(g=>g.root.id==="whole")!;
 assert.deepEqual(family.items.map(n=>[n.resource.id,n.depth]),[["whole",0],["half",1],["quarter",2]]);
 assert.equal(groups.length,2);
});
test("siblings remain siblings when a half has its own two parts",()=>{
 const nodes=resourceFamilies([r("whole"),r("A","whole"),r("B","whole"),r("A1","A"),r("A2","A")])[0].items;
 assert.deepEqual(nodes.map(n=>[n.resource.id,n.depth]),[["whole",0],["A",1],["A1",2],["A2",2],["B",1]]);
});
test("orphaned and cyclic legacy resources are retained once without loops",()=>{
 const all=resourceFamilies([r("orphan","missing"),r("a","b"),r("b","a")]).flatMap(g=>g.items);
 assert.equal(all.length,3);assert.equal(new Set(all.map(n=>n.resource.id)).size,3);
});
