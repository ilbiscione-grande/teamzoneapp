import test from "node:test";
import assert from "node:assert/strict";
import { bookingAgenda, calendarWeek } from "../lib/booking-agenda.ts";
import { emptyFilter, localInstant, type Booking, type Resource } from "../lib/booking.ts";

const resource = (id: string, extra: Partial<Resource> = {}): Resource => ({id, name:id, category:"pitch", active:true, description:null, location:null, capacity:null, requires_approval:false, ...extra});
const booking = (id: string, start: string, end: string, extra: Partial<Booking> = {}): Booking => ({id, resource_id:"pitch", resource_name:"pitch", starts_at:localInstant("2026-11-05",start), ends_at:localInstant("2026-11-05",end), status:"confirmed", title:"Träning", team_name:"P2012", team_id:"team", is_mine:false, ...extra} as Booking);
const days = ["2026-11-05", "2026-11-06"];
const allDay = {...emptyFilter, range:{start:0,end:24}};

test("calendar labels use ISO week numbers through year boundaries and week 53", () => {
 for (const [day, week] of [["2026-11-01",44],["2026-11-02",45],["2026-12-31",53],["2027-01-01",53],["2027-01-04",1],["2024-12-30",1]] as const) assert.equal(calendarWeek(day),week,day);
});

test("agenda searches across title, team and inherited resource path while excluding unauthorized or inactive resources", () => {
 const resources=[resource("whole",{name:"Stora planen"}),resource("pitch",{parent_resource_id:"whole"}),resource("inactive",{active:false})];
 const rows=[booking("yes","18:00","19:00"),booking("inactive","18:00","19:00",{resource_id:"inactive"}),booking("unknown","18:00","19:00",{resource_id:"unknown"})];
 assert.deepEqual(bookingAgenda(rows,resources,days,allDay,"  P2012 STORA träning ")[0].bookings.map(row=>row.id),["yes"]);
 assert.deepEqual(bookingAgenda(rows,resources,days,allDay,"match"),[]);
});

test("resource, team, own, pending and time filters all constrain the agenda", () => {
 const resources=[resource("pitch")];
 const yes=booking("yes","18:00","19:00",{status:"pending",is_mine:true});
 const filter={...allDay,resourceIds:["pitch"],teams:["team"],onlyMine:true,onlyPending:true,range:{start:18,end:20}};
 const rows=[yes,{...yes,id:"other-resource",resource_id:"other"},{...yes,id:"other-team",team_id:null},{...yes,id:"other-owner",is_mine:false},{...yes,id:"confirmed",status:"confirmed" as const},booking("earlier","17:00","18:00",{status:"pending",is_mine:true})];
 assert.deepEqual(bookingAgenda(rows,resources,days,filter,"")[0].bookings.map(row=>row.id),["yes"]);
 assert.deepEqual(bookingAgenda(rows,resources,days,{...allDay,resourceIds:[]},""),[]);
});

test("overnight bookings occupy both days, midnight boundaries do not leak and equal times retain separate resources", () => {
 const resources=[resource("pitch"),resource("room")];
 const overnight=booking("night","23:00","23:30",{ends_at:localInstant("2026-11-06","01:00")});
 const midnight=booking("midnight","22:00","23:00",{ends_at:localInstant("2026-11-06","00:00")});
 const rows=[overnight,midnight,booking("b","18:00","19:00",{resource_id:"room",resource_name:"room"}),booking("a","18:00","19:00")];
 const groups=bookingAgenda(rows,resources,days,allDay,"");
 assert.deepEqual(groups.map(group=>group.bookings.map(row=>row.id)),[["a","b","midnight","night"],["night"]]);
 assert.deepEqual(rows.map(row=>row.id),["night","midnight","b","a"]);
});
