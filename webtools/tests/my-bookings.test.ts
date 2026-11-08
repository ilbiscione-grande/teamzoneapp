import test from "node:test";
import assert from "node:assert/strict";
import { myBookingGroups, myBookingEntries } from "../lib/my-bookings.ts";
import type { Booking } from "../lib/booking.ts";
const now=Date.parse("2026-11-01T12:00:00Z");
const b=(id:string,extra:Partial<Booking>={}):Booking=>({id,resource_name:"Plan",title:"Träning",team_name:"P2012",is_mine:true,status:"confirmed",starts_at:"2026-11-05T17:00:00Z",ends_at:"2026-11-05T18:00:00Z",...extra} as Booking);
const ids=(rows:Booking[],query="",status:"all"|"pending"|"confirmed"="all",days=60)=>myBookingGroups(rows,query,status,days,now).flatMap(group=>group.bookings.map(row=>row.id));

test("search finds the complete shared booking through any resource and across resource names",()=>{
 const rows=[b("pitch",{resource_id:"pitch",resource_name:"D-plan",group_id:"shared"}),b("room",{resource_id:"room",resource_name:"Omklädningsrum 3",group_id:"shared"})];
 for(const query of ["", "omklädningsrum", "D-plan omklädningsrum"]){
  const entries=myBookingEntries(rows,[],query,"all",60,now).flatMap(day=>day.entries);
  assert.equal(entries.length,1);
  assert.equal(entries[0].items.length,2);
  assert.match(entries[0].resourceLabel,/D-plan/);
  assert.match(entries[0].resourceLabel,/Omklädningsrum 3/);
  assert.equal(entries[0].booking,rows[0]);
 }
 assert.equal(myBookingEntries(rows,[],"okänd","all",60,now).length,0);
 assert.deepEqual(rows.map(row=>row.id),["pitch","room"]);
});

test("shared-booking counts preserve status, ownership, period and separate recurring occurrences",()=>{
 const rows=[b("one",{group_id:"shared"}),b("pending",{group_id:"shared",status:"pending"}),b("other",{group_id:"shared",is_mine:false}),b("cancelled",{status:"cancelled"}),b("next",{group_id:"shared",starts_at:"2026-11-15T17:00:00Z",ends_at:"2026-11-15T18:00:00Z"})];
 const entries=(status:"all"|"pending"|"confirmed",days:number)=>myBookingEntries(rows,[],"",status,days,now).flatMap(day=>day.entries);
 assert.equal(entries("all",60).length,3);
 assert.equal(entries("all",7).length,2);
 assert.equal(entries("pending",60).length,1);
 assert.equal(entries("confirmed",60).length,2);
});
test("only own active bookings remain, including ongoing bookings but excluding finished and cancelled rows",()=>{
 assert.deepEqual(ids([b("yes"),b("other",{is_mine:false}),b("cancelled",{status:"cancelled"}),b("declined",{status:"declined"}),b("finished",{ends_at:new Date(now).toISOString()}),b("ongoing",{starts_at:new Date(now-1000).toISOString(),ends_at:new Date(now+1000).toISOString()})]),["ongoing","yes"]);
});
test("combined search and status preserve separate resources of the same activity",()=>{
 const rows=[b("pitch",{status:"pending"}),b("room",{resource_name:"Omklädning",status:"pending"}),b("confirmed")];
 assert.deepEqual(ids(rows,"  P2012 TRÄNING ","pending"),["room","pitch"]);
 assert.deepEqual(ids(rows,"omklädning","pending"),["room"]);
 assert.deepEqual(ids(rows,"finns inte"),[]);
});
test("period is end-exclusive and grouping sorts without altering source records",()=>{
 const rows=[b("later",{starts_at:new Date(now+7*86400e3).toISOString(),ends_at:new Date(now+7*86400e3+1000).toISOString()}),b("soon")];
 assert.deepEqual(ids(rows,"","all",7),["soon"]);
 assert.deepEqual(ids(rows),["soon","later"]);
 assert.deepEqual(rows.map(row=>row.id),["later","soon"]);
 assert.equal(myBookingGroups(rows,"","all",60,now)[0].bookings[0],rows[1]);
});
