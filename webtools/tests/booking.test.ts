import assert from "node:assert/strict";
import { test } from "node:test";
import { addDays, bookingError, dayRange, groupResources, invitationToken, localInstant, type Resource } from "../lib/booking.ts";
import { safeReturnTo } from "../lib/apps.ts";

test("days step over month ends and local times become instants", () => {
  assert.equal(addDays("2026-10-31", 1), "2026-11-01");
  assert.equal(addDays("2026-01-01", -1), "2025-12-31");
  const { from, to } = dayRange("2026-10-21");
  assert.equal(new Date(to).getTime() - new Date(from).getTime(), 24 * 3600e3);
  assert.equal(new Date(localInstant("2026-10-21", "18:30")).getHours(), 18);
});

test("the API's error codes read as sentences", () => {
  assert.match(bookingError({ message: "resource_busy" }), /redan bokad/);
  assert.match(bookingError({ message: "something else" }), /Försök igen/);
  assert.match(bookingError(null), /Försök igen/);
});

test("resources group by category in a fixed order, inactive ones hidden", () => {
  const resource = (name: string, category: Resource["category"], active = true): Resource => ({
    id: name, name, category, description: null, location: null, capacity: null, requires_approval: false, active,
  });
  const groups = groupResources([resource("Minibuss", "vehicle"), resource("Plan 2", "pitch"), resource("Plan 1", "pitch"), resource("Gammal", "hall", false)]);
  assert.deepEqual(groups.map(group => [group.category, group.items.map(item => item.name)]), [["pitch", ["Plan 1", "Plan 2"]], ["vehicle", ["Minibuss"]]]);
  assert.equal(groupResources([resource("Gammal", "hall", false)], true).length, 1);
});

test("an invitation token comes from a pasted link or the bare token", () => {
  const token = "a".repeat(64);
  assert.equal(invitationToken(`https://x.app/bokningar?inbjudan=${token}`), token);
  assert.equal(invitationToken(` ${token} `), token);
  assert.equal(invitationToken("nope"), null);
});

test("booking pages and invitations are valid places to return to", () => {
  assert.equal(safeReturnTo("/bokningar"), "/bokningar");
  assert.equal(safeReturnTo("/bokningar/00000000-0000-4000-8000-000000000001"), "/bokningar/00000000-0000-4000-8000-000000000001");
  assert.equal(safeReturnTo(`/bokningar?inbjudan=${"b".repeat(64)}`), `/bokningar?inbjudan=${"b".repeat(64)}`);
  assert.equal(safeReturnTo("/bokningar?inbjudan=x"), "/");
});

test("a match in the activity list says home or away", async () => {
  const { eventOptionLabel } = await import("../lib/booking.ts");
  const base = { event_id: "e", event_type: "match", starts_at: "2026-10-24T08:00:00Z", ends_at: "2026-10-24T10:00:00Z" };
  assert.match(eventOptionLabel({ ...base, title: "P2012 – Aneby SK", home_away: "away", opponent_name: "Aneby SK" }), /^P2012 – Aneby SK · Borta · /);
  assert.match(eventOptionLabel({ ...base, title: "Bortamatch", home_away: "home", opponent_name: "Aneby SK" }), /^Bortamatch · mot Aneby SK · Hemma · /);
  assert.doesNotMatch(eventOptionLabel({ ...base, title: "Träning", event_type: "training" }), /Hemma|Borta/);
});
