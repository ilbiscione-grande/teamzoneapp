import assert from "node:assert/strict";
import test from "node:test";
import { loadOwnTeamEvents, type CalendarRpc } from "../lib/own-team-events.ts";

const context = { context_id: "context", team_id: "own", team_name: "Own team", club_name: "Club" };
const event = { event_id: "meeting", owning_team_id: "own", title: "Meeting", event_type: "meeting", state: "scheduled", starts_at: "2026-09-27T10:00:00Z", event_cursor: "cursor" };
test("a follower without team membership never requests the private calendar", async () => {
  const calls: string[] = [];
  const result = await loadOwnTeamEvents(async name => { calls.push(name); return {data: [], error: null}; }, "start", "end");
  assert.deepEqual(calls, ["get_my_contexts"]);
  assert.equal(result.hasTeams, false);
  assert.deepEqual(result.items, []);
});
test("own-team calendar includes training as well as meetings and activities", async () => {
  const rpc: CalendarRpc = async (name, params) => {
    if (name === "get_my_contexts") return { data: [context, {...context, context_id: "club", team_id: null}], error: null };
    assert.deepEqual(params.context_ids, ["context"]);
    return { data: [event, {...event, event_id: "other", owning_team_id: "other"}, {...event, event_id: "cancelled", state: "cancelled"}, {...event, event_id: "training", event_type: "training"}, {...event, event_id: "activity", event_type: "activity"}], error: null };
  };
  const result = await loadOwnTeamEvents(rpc, "start", "end");
  assert.deepEqual(result.items.map(item => item.event_id), ["activity", "meeting", "training"]);
});
test("pagination scans past training rows to avoid hiding later meetings", async () => {
  let pages = 0;
  const result = await loadOwnTeamEvents(async name => {
    if (name === "get_my_contexts") return { data: [context], error: null };
    pages++;
    return { data: pages === 1 ? Array.from({length: 200}, (_,i) => ({...event, event_id: String(i), event_type: "training", event_cursor: String(i)})) : [event], error: null };
  }, "start", "end");
  assert.equal(pages, 2);
  assert.equal(result.items.length, 201);
});
test("revoked calendar access fails closed instead of returning partial events", async () => {
  await assert.rejects(loadOwnTeamEvents(async name => name === "get_my_contexts" ? {data: [context], error: null} : {data: null, error: "not_found"}, "start", "end"));
});
