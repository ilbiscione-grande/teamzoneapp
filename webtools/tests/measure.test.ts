import assert from "node:assert/strict";
import { test } from "node:test";
import { chainOrder, chainPoints, halfway, metres, pathLength, polygonArea, shapeMeasure, squareMetres } from "../lib/tactics/measure.ts";
import type { PlayerObject, TacticsObject } from "../lib/tactics/model.ts";

const player = (id: string, x: number, y: number, hidden = false) =>
  ({ id, type: "player", x, y, hidden, side: "home", number: null, name: null, personId: null, color: null, rotation: 0, locked: false }) as PlayerObject;

test("sizes read as a coach reads them, in Swedish", () => {
  assert.equal(metres(7.36), "7,4 m");
  assert.equal(metres(23.6), "24 m");
  assert.equal(squareMetres(1234), "1 230 m²".replace(" ", " "));
  assert.equal(shapeMeasure({ type: "rect", width: 20, height: 15 }), "20 × 15 m · 300 m²");
  assert.equal(shapeMeasure({ type: "ellipse", width: 10, height: 10 }), "Ø 10 × 10 m · 79 m²");
});

test("a closed outline's ground and a path's length", () => {
  const square = [{ x: 0, y: 0 }, { x: 10, y: 0 }, { x: 10, y: 10 }, { x: 0, y: 10 }];
  assert.equal(polygonArea(square), 100);
  assert.equal(pathLength(square, false), 30);
  assert.equal(pathLength(square, true), 40);
});

test("a line through players follows them, leaving out the hidden and the gone", () => {
  const objects: TacticsObject[] = [player("a", 0, 0), player("b", 10, 0, true), player("c", 10, 10)];
  assert.deepEqual(chainPoints({ players: ["a", "b", "c", "x"] }, objects), [{ x: 0, y: 0 }, { x: 10, y: 10 }]);
  assert.deepEqual(chainPoints({ players: ["a", "c"] }, objects, { c: { x: 5, y: 5 } }), [{ x: 0, y: 0 }, { x: 5, y: 5 }], "a dragged player where they are now");
});

test("open goes in the picked order; closed goes round, never crossing itself", () => {
  const picked = [player("a", 0, 0), player("c", 10, 10), player("b", 10, 0), player("d", 0, 10)];
  assert.deepEqual(chainOrder(picked, false), ["a", "c", "b", "d"]);
  const round = chainOrder(picked, true);
  const at = Object.fromEntries(picked.map(item => [item.id, item]));
  assert.equal(polygonArea(round.map(id => at[id])), 100, "the full square, not a bow tie");
});

test("a length is tagged halfway along the path", () => {
  assert.deepEqual(halfway([{ x: 0, y: 0 }, { x: 10, y: 0 }, { x: 10, y: 10 }, { x: 10, y: 20 }]), { x: 10, y: 5 });
});
