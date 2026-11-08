import test from "node:test";
import assert from "node:assert/strict";
import { bookingDecisions, upcomingBookings, upcomingBookingGroups } from "../lib/booking-workspace.ts";
import type { Booking, Resource } from "../lib/booking.ts";

const booking = (id: string, extra: Partial<Booking> = {}): Booking => ({
  id, revision: 1, revisions: {}, resource_id: "pitch", resource_name: "Plan",
  starts_at: "2026-11-02T17:00:00Z", ends_at: "2026-11-02T18:30:00Z",
  title: null, notes: null, status: "pending", booked_by_name: null, is_mine: false,
  team_id: null, team_name: null, event_id: null, event_title: null,
  can_cancel: false, can_decide: true, ...extra,
});

test("pending series take precedence over resource groups and remain separate decisions", () => {
  const items = [booking("1", { series_id: "a", group_id: "shared" }),
    booking("2", { series_id: "a", group_id: "other" }),
    booking("3", { series_id: "b", group_id: "shared" }),
    booking("4", { group_id: "shared" }), booking("5", { group_id: "shared" }), booking("6")];
  assert.deepEqual(bookingDecisions(items).map(item => item.id), ["1", "3", "4", "6"]);
});

test("identical identifiers across decision types never hide a request", () => {
  assert.equal(bookingDecisions([booking("same"), booking("2", { series_id: "same" }), booking("3", { group_id: "same" })]).length, 3);
});

test("booker overview excludes others, declined, cancelled and finished bookings", () => {
  const items = [booking("other"), booking("mine", { is_mine: true }),
    booking("declined", { is_mine: true, status: "declined" }),
    booking("cancelled", { is_mine: true, status: "cancelled" }),
    booking("past", { is_mine: true, ends_at: "2026-11-02T16:00:00Z" })];
  assert.deepEqual(upcomingBookings(items, true, Date.parse("2026-11-02T17:30:00Z")).map(item => item.id), ["mine"]);
});

test("overview retains ongoing bookings and sorts without mutating API data", () => {
  const items = [booking("later", { starts_at: "2026-11-03T17:00:00Z", ends_at: "2026-11-03T18:00:00Z" }), booking("ongoing")];
  assert.deepEqual(upcomingBookings(items, false, Date.parse("2026-11-02T17:30:00Z")).map(item => item.id), ["ongoing", "later"]);
  assert.equal(items[0].id, "later");
});

test('one shared booking of a pitch and changing room becomes one overview row',()=>{
  const items=[booking('room',{group_id:'shared',resource_id:'room',resource_name:'Omklädning'}),booking('pitch',{group_id:'shared'})];
  const groups=upcomingBookingGroups(items,[]);
  assert.equal(groups.length,1);assert.equal(groups[0].items.length,2);
  assert.ok(groups[0].resourceLabel.includes('Plan'));assert.ok(groups[0].resourceLabel.includes('Omklädning'));
  assert.equal(items[0].id,'room');
});
test('unrelated bookings and different series occurrences are never merged',()=>{
  const groups=upcomingBookingGroups([booking('a'),booking('b'),booking('c',{series_id:'s',group_id:'g1'}),booking('d',{series_id:'s',group_id:'g2'})],[]);
  assert.equal(groups.length,4);
});
test('differences in time, pending status, activity, notes or permissions preserve separate rows',()=>{
  const first=booking('a',{group_id:'group'});
  for(const extra of [{starts_at:'2026-11-02T17:30:00Z'},{ends_at:'2026-11-02T19:00:00Z'},{status:'confirmed' as const},{event_id:'activity'},{notes:'Annan anteckning'},{can_cancel:true},{can_decide:false},{is_mine:true}]) {
    assert.equal(upcomingBookingGroups([first,booking('b',{group_id:'group',...extra})],[]).length,2);
  }
});
test('duplicate API rows do not inflate the resource count and representatives remain real booking rows',()=>{
  const original=booking('a',{group_id:'group'});const groups=upcomingBookingGroups([original,original],[]);
  assert.equal(groups[0].items.length,1);assert.equal(groups[0].booking,original);
});

test('three quarters booked together retain one clear physical pitch scope',()=>{
  const layout={A:'A',B:'B',A1:'A1',A2:'A2',B1:'B1',B2:'B2'};
  const r=(id:string,parent_resource_id:string|null=null):Resource=>({id,name:id,category:'pitch',active:true,parent_resource_id,description:null,location:null,capacity:null,requires_approval:false});
  const resources=[{...r('Konstgräset'),pitch_layout:layout},r('A','Konstgräset'),r('B','Konstgräset'),...['A1','A2','B1','B2'].map(id=>r(id,id[0]))];
  const groups=upcomingBookingGroups(['A1','A2','B1'].map(id=>booking(id,{group_id:'three',resource_id:id,resource_name:id})),resources);
  assert.equal(groups.length,1);assert.equal(groups[0].items.length,3);
  assert.equal(groups[0].resourceLabel,'Konstgräset · ¾-plan · allt utom B2');
});
