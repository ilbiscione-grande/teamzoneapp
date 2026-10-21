import assert from "node:assert/strict";
import { test } from "node:test";
import { safeReturnTo } from "../lib/apps.ts";
import { dateSpan, feeLabel, placesLeft, registrationsByClass, staffInvitationToken, tournamentError, wholeNumber, type Registration, type TournamentClass } from "../lib/tournament.ts";

const item = (id: string, sort: number, max: number | null = null, approved = 0): TournamentClass => ({
  id, name: id, description: null, format: "groups_playoff", max_teams: max, fee_sek: null, match_minutes: null, sort_order: sort, approved, pending: 0,
});

test("a tournament's dates read as one span", () => {
  assert.equal(dateSpan("2026-11-14", "2026-11-15"), "14–15 nov. 2026");
  assert.equal(dateSpan("2026-11-14", "2026-11-14"), "14 nov. 2026");
  assert.equal(dateSpan("2026-11-30", "2026-12-01"), "30 nov.–1 dec. 2026");
  assert.equal(dateSpan("2026-12-30", "2027-01-02"), "30 dec. 2026–2 jan. 2027");
});

test("fees, places and numbers from the forms", () => {
  assert.equal(feeLabel(null), null);
  assert.equal(feeLabel(0), "Ingen avgift");
  assert.match(feeLabel(1500) ?? "", /^1\s500 kr$/);
  assert.equal(placesLeft(item("a", 1)), null);
  assert.equal(placesLeft(item("a", 1, 8, 8)), 0);
  assert.equal(placesLeft(item("a", 1, 8, 3)), 5);
  assert.equal(wholeNumber("", 0, 10), null);
  assert.equal(wholeNumber(" 1 500 ", 0, 2000), 1500);
  assert.equal(wholeNumber("1,5", 0, 10), "invalid");
  assert.equal(wholeNumber("1", 2, 10), "invalid");
});

test("registrations group by class in the classes' order", () => {
  const registration = (id: string, classId: string) => ({ id, class_id: classId } as Registration);
  const groups = registrationsByClass([item("F13", 2), item("P12", 1)], [registration("x", "F13"), registration("y", "P12"), registration("z", "F13")]);
  assert.deepEqual(groups.map(group => [group.item.id, group.registrations.map(r => r.id)]), [["P12", ["y"]], ["F13", ["x", "z"]]]);
});

test("errors, invitations and return paths", () => {
  assert.match(tournamentError({ message: "class_full" }), /full/);
  assert.match(tournamentError(null), /Försök igen/);
  const token = "b".repeat(64);
  assert.equal(staffInvitationToken(`https://x.se/turneringar?inbjudan=${token}`), token);
  assert.equal(staffInvitationToken("nej"), null);
  assert.equal(safeReturnTo("/turneringar"), "/turneringar");
  assert.equal(safeReturnTo("/turneringar/00000000-0000-4000-8000-000000000001"), "/turneringar/00000000-0000-4000-8000-000000000001");
  assert.equal(safeReturnTo(`/turneringar?inbjudan=${token}`), `/turneringar?inbjudan=${token}`);
  assert.equal(safeReturnTo("/turneringar/../konto"), "/");
});
