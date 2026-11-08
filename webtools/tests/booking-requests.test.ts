import test from "node:test";
import assert from "node:assert/strict";
import { bookingRequests, filterBookingRequests } from "../lib/booking-requests.ts";
import type { Booking } from "../lib/booking.ts";
const booking = (id: string, extra: Partial<Booking> = {}): Booking => ({id, revision:4,revisions:{[id]:4}, resource_name:"Plan",status:"pending", starts_at:"2026-11-05T17:00:00Z",ends_at:"2026-11-05T18:00:00Z",can_decide:true,...extra} as Booking);

test("requests keep complete waiting groups and series while excluding confirmed and declined members",()=>{
 const rows=[booking("group-a",{group_id:"g"}),booking("group-b",{group_id:"g"}),booking("confirmed",{group_id:"g",status:"confirmed"}),booking("series-a",{series_id:"s"}),booking("series-b",{series_id:"s",status:"declined"})];
 const requests=bookingRequests(rows);
 assert.deepEqual(requests.map(item=>[item.kind,item.pending.map(row=>row.id)]),[["group",["group-a","group-b"]],["series",["series-a"]]]);
 assert.equal(requests[0].booking,rows[0]);
 assert.deepEqual(requests[0].booking.revisions,{"group-a":4});
});

test("series take precedence and ids in different decision types never collide",()=>{
 const requests=bookingRequests([booking("same"),booking("group",{group_id:"same"}),booking("series",{series_id:"same",group_id:"same"})]);
 assert.deepEqual(requests.map(item=>item.key).sort(),["group:same","series:same","single:same"]);
});

test("searching a later resource or occurrence preserves every pending member and the original decision payload",()=>{
 const requests=bookingRequests([booking("first",{group_id:"g",resource_name:"A-plan",team_name:"P2012"}),booking("later",{group_id:"g",resource_name:"Omklädning 3",notes:"Behöver nyckel"}),booking("other",{title:"Annat"})]);
 const filtered=filterBookingRequests(requests,"  P2012 NYCKEL omklädning ","group");
 assert.equal(filtered[0],requests[0]);
 assert.deepEqual(filtered[0].pending.map(row=>row.id),["first","later"]);
 assert.deepEqual(filterBookingRequests(requests,"nyckel","series"),[]);
 assert.deepEqual(filterBookingRequests(requests,"finns inte","all"),[]);
});

test("nearest occurrence determines order without mutating source rows or representative revisions",()=>{
 const late=booking("late",{series_id:"s",starts_at:"2026-11-12T17:00:00Z"});
 const early=booking("early",{series_id:"s"});
 const rows=[late,booking("single",{starts_at:"2026-11-06T17:00:00Z"}),early];
 const requests=bookingRequests(rows);
 assert.deepEqual(requests.map(item=>item.booking.id),["early","single"]);
 assert.deepEqual(rows.map(row=>row.id),["late","single","early"]);
 assert.equal(requests[0].booking,early);
});
