import assert from "node:assert/strict";
import test from "node:test";
import { attributeName, attributeOptions } from "../lib/tactics/attributes.ts";
import { createPlayer } from "../lib/tactics/document.ts";
import { formationPositions } from "../lib/tactics/formations.ts";
import { applySuggestion, formationSlots, matchFormat, slotLabel, type SuggestedSlot } from "../lib/tactics/lineup.ts";
import type { PlayerObject, SquadPlayer, TacticsObject } from "../lib/tactics/model.ts";
import { positionOptions } from "../lib/tactics/player-label.ts";

test("places carry the app's codes, in the board's spot order", () => {
  const slots = formationSlots([4, 3, 3]);
  assert.deepEqual(slots.map(slot => slot.code), ["GK", "1A", "1B", "1C", "1D", "2A", "2B", "2C", "3A", "3B", "3C"]);
  assert.deepEqual([...new Set(slots.map(slot => slot.group))], ["goalkeeper", "defender", "midfielder", "forward"]);
  assert.equal(slots.length, formationPositions([4, 3, 3], "home").length);
  // A, B … run from the team's left: top of the pitch for the home team.
  const spots = formationPositions([4, 3, 3], "home");
  assert.ok(spots[1].y < spots[4].y);
});

test("the match format follows the players, the goalkeeper included", () => {
  assert.equal(matchFormat([4, 3, 3]), "11v11");
  assert.equal(matchFormat([3, 3, 2]), "9v9");
  assert.equal(matchFormat([2, 3, 1]), "7v7");
  assert.equal(matchFormat([2, 1, 1]), "5v5");
  assert.equal(matchFormat([3, 2]), null);
});

test("places named as in the app's line-up", () => {
  const lines = [4, 2, 3, 1];
  assert.deepEqual(formationSlots(lines).map(slot => slotLabel(lines, slot.code)),
    ["MV", "VB", "MB", "MB", "HB", "DM", "DM", "VY", "OM", "HY", "ANF"]);
  assert.equal(slotLabel([4, 3, 3], "3A"), "VY");
  assert.equal(slotLabel([4, 3, 3], "3A", true), "LW");
  assert.equal(slotLabel([4, 4, 2], "2A"), "VM");
});

test("attributes and positions named for the team", () => {
  const attributes = { sport: "football", catalog: [{ key: "heading", area: "technical" }], custom: [{ id: "c1", label: "Långa inkast" }] };
  assert.equal(attributeName("heading", attributes, "sv"), "Huvudspel");
  assert.equal(attributeName("heading", attributes, "en"), "Heading");
  assert.equal(attributeName("c1", attributes, "en"), "Långa inkast");
  assert.deepEqual(attributeOptions(attributes, "sv").map(option => option.name), ["Huvudspel", "Långa inkast"]);
  assert.ok(positionOptions("football", "sv").some(option => option.key === "striker"));
  assert.ok(!positionOptions("football", "sv").some(option => option.key.startsWith("hb_")));
  assert.deepEqual(positionOptions("handball", "sv").map(option => option.key).slice(0, 2), ["goalkeeper", "hb_backcourt"]);
});

test("a suggestion puts each player at their place, moving those on the board", () => {
  const squad: SquadPlayer[] = ["a", "b", "c", "d", "e", "f", "g", "h"].map((id, index) => ({ personId: id, name: id.toUpperCase(), number: index + 1, position: null }));
  // On the board: a and h from the squad, one numbered player, and an away player.
  let objects: TacticsObject[] = [];
  objects = [...objects, createPlayer({ x: 1, y: 1 }, "home", objects, squad[0])];
  objects = [...objects, createPlayer({ x: 2, y: 2 }, "home", objects, squad[7])];
  objects = [...objects, createPlayer({ x: 3, y: 3 }, "home", objects)];
  objects = [...objects, createPlayer({ x: 90, y: 30 }, "away", objects)];
  const lines = [2, 3, 1];
  const slots: SuggestedSlot[] = formationSlots(lines).map((slot, index) => ({
    ...slot, locked: false, person_id: index < 6 ? squad[index].personId : null, name: index < 6 ? squad[index].name : null,
  }));
  const next = applySuggestion(objects, "home", lines, slots, squad);
  const spots = formationPositions(lines, "home");
  const home = next.filter((item): item is PlayerObject => item.type === "player" && item.side === "home");
  const at = (personId: string) => home.find(item => item.personId === personId)!;
  assert.equal(at("a").id, objects[0].id, "a is moved, not added again");
  assert.deepEqual({ x: at("a").x, y: at("a").y }, spots[0]);
  assert.deepEqual({ x: at("f").x, y: at("f").y }, spots[5]);
  assert.equal(at("f").number, 6);
  assert.equal(home.find(item => item.personId === "h"), undefined, "h is left out");
  // The empty place takes the numbered player.
  const numbered = home.find(item => !item.personId)!;
  assert.deepEqual({ x: numbered.x, y: numbered.y }, spots[6]);
  assert.equal(home.length, 7);
  assert.ok(next.some(item => item.type === "player" && item.side === "away"), "the away team stays");
});
