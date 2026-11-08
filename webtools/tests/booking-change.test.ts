import test from "node:test";
import assert from "node:assert/strict";
import { bookingChangeScopes } from "../lib/booking-change.ts";
test("standalone booking never offers a series scope",()=>{
 assert.deepEqual(bookingChangeScopes({series_id:null,resource_event_series:false}).map(s=>s.value),["booking"]);
});
test("booking series offers its own scopes without inventing an activity series",()=>{
 assert.deepEqual(bookingChangeScopes({series_id:"series",resource_event_series:false}).map(s=>s.value),["booking","series_forward","series_all"]);
});
test("both series retain distinct scope identifiers accepted by the existing API",()=>{
 assert.deepEqual(bookingChangeScopes({series_id:"series",resource_event_series:true}).map(s=>s.value),["booking","series_forward","series_all","event_forward","event_all"]);
 assert.deepEqual(bookingChangeScopes({series_id:null,resource_event_series:true}).map(s=>s.value),["booking","event_forward","event_all"]);
});
