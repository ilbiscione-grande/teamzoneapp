import test from "node:test";
import assert from "node:assert/strict";
import { availabilityGroups, availabilityState, type AvailabilityRow } from "../lib/availability-overview.ts";
import type { Resource } from "../lib/booking.ts";
const r=(id:string,extra:Partial<Resource>={}):Resource=>({id,name:id,category:"pitch",active:true,description:null,location:null,capacity:null,requires_approval:false,...extra});
const row=(resource_id:string,extra:Partial<AvailabilityRow>={}):AvailabilityRow=>({resource_id,busy:false,outside_disposition:false,busy_resource_name:null,busy_from:null,busy_to:null,...extra});
test("only explicit free results count as free, including when an outside flag is set without busy",()=>{
 assert.equal(availabilityState(r("a"),[row("a")]),"free");
 assert.equal(availabilityState(r("a"),[row("a",{outside_disposition:true})]),"outside");
 assert.equal(availabilityState(r("a"),[row("a",{busy:true})]),"busy");
 assert.equal(availabilityState(r("a",{active:false}),[row("a")]),"inactive");
});
test("missing and contradictory results never enable booking",()=>{
 assert.equal(availabilityState(r("a"),null),"unknown");
 assert.equal(availabilityState(r("a"),[row("other")]),"unknown");
 assert.equal(availabilityState(r("a"),[{resource_id:"a",busy:false} as AvailabilityRow]),"unknown");
 assert.equal(availabilityState(r("a"),[row("a"),row("a",{busy:true})]),"busy");
});
test("free search retains related hierarchy without treating blocked ancestors as matches",()=>{
 const resources=[r("whole"),r("half",{parent_resource_id:"whole"}),r("quarter",{parent_resource_id:"half"}),r("other")];
 const rows=[row("whole",{busy:true}),row("half",{outside_disposition:true}),row("quarter"),row("other")];
 const groups=availabilityGroups(resources,rows,"quarter","pitch",true);
 assert.deepEqual(groups[0].matchingIds,["quarter"]);
 assert.deepEqual(groups[0].items.map(item=>item.resource.id),["whole","half","quarter"]);
 assert.deepEqual(availabilityGroups(resources,null,"","all",true),[]);
});
