import assert from "node:assert/strict";
import { test } from "node:test";
import { newFrame } from "../lib/tactics/document.ts";
import type { Frame, ZoneObject } from "../lib/tactics/model.ts";
import { objectsAt, type Rendered } from "../lib/tactics/timeline.ts";
import { addCorner, bendSide, bendsAfterCorner, blendZones, reshapeZone, shapePoints, sideMiddle as middleOfSide, zoneOfShape, cornersOf, insertCorner, moveCorner, removeCorner, sideMiddle, tapCorner, zoneFrom, zoneOutline } from "../lib/tactics/zone.ts";

const corners = [{ x: 10, y: 10 }, { x: 30, y: 10 }, { x: 20, y: 30 }];

test("a zone is placed at the middle of its corners, which it keeps relative to that", () => {
  const zone = zoneFrom(corners)!;
  assert.deepEqual([zone.x, zone.y], [20, 20]);
  assert.deepEqual(cornersOf(zone).map(point => ({ x: point.x + zone.x, y: point.y + zone.y })), corners);
  assert.equal(zoneFrom(corners.slice(0, 2)), null, "two corners are no zone");
  assert.equal(zoneFrom([corners[0], corners[0], corners[1]]), null, "nor three where two are one");
  assert.deepEqual(moveCorner(zone, 1, { x: 0, y: 0 }), [-10, -10, 0, 0, 0, 10]);
});

test("taps add corners; the first corner or the last one tapped again closes, once there are three", () => {
  let state = { corners: [] as typeof corners, close: false };
  for (const at of corners) state = tapCorner(state.corners, at, 1);
  assert.equal(state.corners.length, 3);
  assert.equal(tapCorner(state.corners, { x: 10.5, y: 10.2 }, 1).close, true, "on the first corner");
  assert.equal(tapCorner(state.corners, { x: 20, y: 30.4 }, 1).close, true, "the last one again: a double tap");
  assert.deepEqual(tapCorner(corners.slice(0, 2), { x: 30, y: 10.3 }, 1), { corners: corners.slice(0, 2), close: false }, "two corners and a double tap: nothing added");
  assert.equal(tapCorner(state.corners, { x: 40, y: 40 }, 1).corners.length, 4);
});

test("a zone's corners move between frames", () => {
  const zone = zoneFrom(corners)!;
  const frame = (item: ZoneObject): Frame => ({ ...newFrame([item]), durationMs: 1000, easing: "linear" });
  const frames = [frame(zone), frame({ ...zone, points: moveCorner(zone, 2, { x: 0, y: 30 }) })];
  const half = objectsAt(frames, 0.5)[0] as Rendered & ZoneObject;
  assert.deepEqual(half.points.slice(4), [0, 20]);
});

test("a side is bent through the point its handle is dragged to, straightened again, and keeps its bend as a corner moves", () => {
  const zone = zoneFrom(corners)!;
  assert.equal(zoneOutline(zone).length, 3, "straight sides: the corners alone");
  const through = { x: 0, y: -14 };
  const bent = { ...zone, bends: bendSide(zone, 0, through) };
  assert.deepEqual(sideMiddle(bent, 0), through);
  assert.deepEqual(bent.bends.slice(1), [null, null]);
  assert.ok(zoneOutline(bent).length > 3, "a bent side in steps");
  assert.ok(zoneOutline(bent).some(point => point.y < -10), "bowing out past the straight side");
  assert.deepEqual(bendSide(bent, 0, null), [null, null, null]);
  const moved = bendsAfterCorner(bent, 1, { x: 14, y: -10 })!;
  assert.deepEqual(moved[0], { x: bent.bends[0]!.x + 2, y: bent.bends[0]!.y });
  assert.equal(bendsAfterCorner(zone, 1, { x: 0, y: 0 }), undefined, "nothing to move on a straight zone");
});

test("a side bends from straight between frames", () => {
  const zone = zoneFrom(corners)!;
  const bent = { ...zone, bends: bendSide(zone, 0, { x: 0, y: -14 }) };
  const frame = (item: ZoneObject): Frame => ({ ...newFrame([item]), durationMs: 1000, easing: "linear" });
  const half = objectsAt([frame(zone), frame(bent)], 0.5)[0] as Rendered & ZoneObject;
  const middle = sideMiddle(half, 0);
  assert.ok(middle.y < -10 && middle.y > -14, "part of the way");
});

test("a corner put on a side splits it there; a bent side into two halves that keep its shape", () => {
  const zone = zoneFrom(corners)!; // corners relative: (-10,-10) (10,-10) (0,10)
  const straight = insertCorner(zone, { x: 0, y: -9 });
  assert.equal(cornersOf(straight).length, 4);
  assert.deepEqual(cornersOf(straight)[1], { x: 0, y: -10 }, "on the top side, not off it");
  assert.equal(straight.bends, undefined, "no bends made where there were none");
  const last = insertCorner(zone, { x: -6, y: 1 });
  assert.equal(cornersOf(last).length, 4);
  assert.ok(Math.abs(cornersOf(last)[3].x + 5) < 0.3 && Math.abs(cornersOf(last)[3].y) < 0.6, "the closing side gets it at the end");
  const bent = { ...zone, bends: bendSide(zone, 0, { x: 0, y: -16 }) };
  const top = sideMiddle(bent, 0);
  const split = insertCorner(bent, top);
  assert.ok(Math.hypot(cornersOf(split)[1].x - top.x, cornersOf(split)[1].y - top.y) < 0.05);
  assert.equal(split.bends!.length, 4);
  assert.ok(split.bends![0] && split.bends![1] && !split.bends![2] && !split.bends![3]);
  const before = zoneOutline(bent, 800), after = zoneOutline(split, 16);
  const off = Math.max(...after.map(point => Math.min(...before.map(other => Math.hypot(point.x - other.x, point.y - other.y)))));
  assert.ok(off < 0.05, `the edge stays where it was (${off})`);
});

test("a corner more goes in the middle of the longest side", () => {
  const zone = zoneFrom([{ x: 0, y: 0 }, { x: 40, y: 0 }, { x: 0, y: 10 }])!; // relative: (-20,-5) (20,-5) (-20,5)
  const more = addCorner(zone);
  assert.equal(cornersOf(more).length, 4);
  assert.deepEqual(cornersOf(more)[2], { x: 0, y: 0 }, "the long slanted side, at its middle");
  assert.equal(cornersOf(addCorner(more)).length, 5);
});

test("a corner taken away joins its two sides into one straight side, never below three corners", () => {
  const zone = zoneFrom([{ x: 0, y: 0 }, { x: 20, y: 0 }, { x: 20, y: 20 }, { x: 0, y: 20 }])!; // relative: (-10,-10) (10,-10) (10,10) (-10,10)
  assert.equal(removeCorner(zoneFrom(corners)!, 0), null, "a three-cornered zone keeps its corners");
  const three = removeCorner(zone, 1)!;
  assert.deepEqual(three.points, [-10, -10, 10, 10, -10, 10]);
  assert.equal(three.bends, undefined);
  const bent = { ...zone, bends: [{ x: 0, y: -14 }, { x: 14, y: 0 }, { x: 0, y: 14 }, null] };
  assert.deepEqual(removeCorner(bent, 1)!.bends, [null, { x: 0, y: 14 }, null], "the joined side straight, the others as they were");
  assert.deepEqual(removeCorner(bent, 0)!.bends, [{ x: 14, y: 0 }, { x: 0, y: 14 }, null], "the first corner: the closing side is the joined one");
});

test("a zone flows into a shape of other corners: ends as it was and as it will be, between them in between", () => {
  const square = { points: [-10, -10, 10, -10, 10, 10, -10, 10] };
  const triangle = { points: [0, -12, 12, 10, -12, 10] }; // drawn the same way round
  assert.deepEqual(blendZones(square, triangle, 0), square);
  assert.deepEqual(blendZones(square, triangle, 1), triangle);
  const half = blendZones(square, triangle, 0.5);
  assert.equal(half.points.length % 2, 0);
  assert.ok(half.points.length / 2 > 20, "drawn in many points");
  const ring = cornersOf(half);
  const top = Math.min(...ring.map(point => point.y)), bottom = Math.max(...ring.map(point => point.y));
  assert.ok(top < -10 && top > -12, `the top between the two (${top})`);
  assert.ok(Math.abs(bottom - 10) < 0.01, "the bottom where both have it");
  const backwards = blendZones({ points: [-10, 10, 10, 10, 10, -10, -10, -10] }, triangle, 0.5);
  const area = (points: { x: number; y: number }[]) => Math.abs(points.reduce((sum, point, index) => { const next = points[(index + 1) % points.length]; return sum + point.x * next.y - next.x * point.y; }, 0)) / 2;
  assert.ok(Math.abs(area(cornersOf(backwards)) - area(ring)) < 1, "drawn the other way round, it does not turn inside out");
});

test("a zone made round, square or three-cornered keeps its size; a rectangle or ellipse becomes a zone as it was", () => {
  const round = shapePoints("circle", 20, 10);
  assert.equal(cornersOf(round).length, 8);
  assert.deepEqual(cornersOf(round)[0], { x: 0, y: -5 });
  for (let side = 0; side < 8; side++) {
    const at = middleOfSide(round, side);
    assert.ok(Math.abs((at.x / 10) ** 2 + (at.y / 5) ** 2 - 1) < 0.01, "each side's middle on the curve");
  }
  const square = { x: 30, y: 20, rotation: 0, ...shapePoints("square", 20, 10) };
  const triangle = reshapeZone(square, "triangle");
  assert.deepEqual([triangle.x, triangle.y], [30, 20]);
  assert.deepEqual(triangle.points, [0, -5, 10, 5, -10, 5]);
  const ellipse = { id: "e", type: "ellipse" as const, x: 5, y: 6, rotation: 30, locked: false, hidden: false, width: 12, height: 8, color: "#fff", fill: 0.3, dashed: true, dim: true };
  const zone = zoneOfShape(ellipse);
  assert.equal(zone.type, "zone");
  assert.deepEqual([zone.id, zone.x, zone.y, zone.rotation, zone.dashed, zone.dim], ["e", 5, 6, 30, true, true]);
  assert.ok(!("width" in zone) && !("height" in zone));
  assert.equal(cornersOf(zone).length, 8);
});
