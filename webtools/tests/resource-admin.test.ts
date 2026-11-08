import test from "node:test";
import assert from "node:assert/strict";
import { resourceAdminGroups } from "../lib/resource-admin.ts";
import type { Resource } from "../lib/booking.ts";
const r=(id:string,parent_resource_id:string|null=null,extra:Partial<Resource>={}):Resource=>({id,name:id,parent_resource_id,category:"pitch",active:true,description:null,location:null,capacity:null,requires_approval:false,...extra});

test("a matching quarter retains the whole family including inactive ancestors, both halves and its sibling",()=>{
 const resources=[r("whole",null,{active:false}),r("half A","whole"),r("half B","whole"),r("quarter A1","half A"),r("quarter A2","half A"),r("unrelated")];
 const groups=resourceAdminGroups(resources,"quarter A1","all","active");
 assert.equal(groups.length,1);
 assert.deepEqual(groups[0].matchingIds,["quarter A1"]);
 assert.deepEqual(groups[0].items.map(item=>[item.resource.id,item.depth]),[["whole",0],["half A",1],["quarter A1",2],["quarter A2",2],["half B",1]]);
});

test("type and status constrain matches without removing related resources of another type",()=>{
 const resources=[r("hall",null,{category:"hall",active:false}),r("camera","hall",{category:"equipment"})];
 const groups=resourceAdminGroups(resources,"","equipment","active");
 assert.deepEqual(groups[0].matchingIds,["camera"]);
 assert.equal(groups[0].root,resources[0]);
 assert.deepEqual(resourceAdminGroups(resources,"","equipment","inactive"),[]);
 assert.deepEqual(resourceAdminGroups(resources,"","hall","inactive")[0].matchingIds,["hall"]);
});

test("search combines path, location and owner case-insensitively and reset includes every resource once",()=>{
 const resources=[r("whole",null,{name:"Stora planen"}),r("half","whole",{location:"Ränneborg",owner_name:"Kommunen",ownership_kind:"external"}),r("other")];
 assert.deepEqual(resourceAdminGroups(resources,"  STORA ränneborg kommunen ","all","all")[0].matchingIds,["half"]);
 assert.deepEqual(resourceAdminGroups(resources,"egen","all","all"),[]);
 assert.deepEqual(resourceAdminGroups(resources,"","all","all").flatMap(group=>group.matchingIds).sort(),["half","other","whole"]);
 assert.deepEqual(resources.map(resource=>resource.id),["whole","half","other"]);
});
