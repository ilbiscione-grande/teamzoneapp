import assert from "node:assert/strict";
import { test } from "node:test";
import { newFrame } from "../lib/tactics/document.ts";
import type { Frame, ZoneObject } from "../lib/tactics/model.ts";
import { objectsAt, type Rendered } from "../lib/tactics/timeline.ts";
import { cornersOf, moveCorner, tapCorner, zoneFrom } from "../lib/tactics/zone.ts";

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
