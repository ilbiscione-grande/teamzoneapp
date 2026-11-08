import test from "node:test";
import assert from "node:assert/strict";
import { bookingAlternatives, type ResourceAvailabilityResult } from "../lib/booking-alternatives.ts";
import type { Resource } from "../lib/booking.ts";
const resource=(id:string,extra:Partial<Resource>={}):Resource=>({id,name:id,category:"pitch",active:true,description:null,location:null,capacity:null,requires_approval:false,...extra});
const free=(resource_id:string):ResourceAvailabilityResult=>({resource_id,busy:false,outside_disposition:false});
test("only explicit free results for active authorized resources become alternatives",()=>{
 const resources=[resource("selected"),resource("free"),resource("busy"),resource("outside"),resource("inactive",{active:false}),resource("missing")];
 const rows=[free("selected"),free("free"),{...free("busy"),busy:true},{...free("outside"),outside_disposition:true},free("inactive"),free("unknown")];
 assert.deepEqual(bookingAlternatives(resources,rows,"selected").map(r=>r.id),["free"]);
});
test("missing flags and contradictory results never count as free",()=>{
 const rows=[{resource_id:"incomplete",busy:false} as ResourceAvailabilityResult,free("duplicate"),{...free("duplicate"),busy:true}];
 assert.deepEqual(bookingAlternatives([resource("selected"),resource("incomplete"),resource("duplicate")],rows,"selected"),[]);
});
test("same type is offered first without excluding other resource types or inherited parts",()=>{
 const resources=[resource("selected"),resource("A room",{category:"locker_room"}),resource("B half",{parent_resource_id:"whole"}),resource("C pitch")];
 assert.deepEqual(bookingAlternatives(resources,resources.map(r=>free(r.id)),"selected").map(r=>r.id),["B half","C pitch","A room"]);
 assert.deepEqual(bookingAlternatives(resources,resources.map(r=>free(r.id)),"missing"),[]);
});
