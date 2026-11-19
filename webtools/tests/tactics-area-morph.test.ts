import assert from "node:assert/strict";
import { test } from "node:test";
import { areasGone } from "../lib/tactics/area-morph.ts";
import type { Frame, ShapeObject, ZoneObject } from "../lib/tactics/model.ts";
import { blendFrames } from "../lib/tactics/timeline.ts";
import { cornersOf, zoneOutline } from "../lib/tactics/zone.ts";

const base = { rotation: 0, locked: false, hidden: false, color: "#facc15", fill: 0.3, dashed: false };
const circle: ShapeObject = { ...base, id: "circle", type: "ellipse", x: 20, y: 30, width: 10, height: 10 };
const triangle: ZoneObject = { ...base, id: "triangle", type: "zone", x: 40, y: 30, points: [0, -6, 6, 6, -6, 6], morphFrom: "circle" };
const frame = (objects: Frame["objects"]) => ({ objects }) as Frame;

test("a triangle formed out of the circle of the frame before: the one turns into the other", () => {
  const half = blendFrames(frame([circle]), frame([triangle]), 0.5);
  assert.equal(half.length, 1, "no circle fading out beside it");
  const shape = half[0] as ZoneObject;
  assert.equal(shape.id, "triangle");
  assert.equal(shape.type, "zone");
  assert.ok(shape.x > 20 && shape.x < 40, "on its way");
  assert.equal(half[0].opacity ?? 1, 1, "not faded");
  assert.ok(cornersOf(shape).length > 8, "between the two shapes");
  const edge = zoneOutline(blendFrames(frame([circle]), frame([triangle]), 0)[0] as ZoneObject);
  assert.ok(edge.every(point => Math.abs(Math.hypot(point.x, point.y) - 5) < 0.3), "it starts as the circle");
});

test("only areas linked so turn; the others fade, and a gone area is taken once", () => {
  const unlinked = { ...triangle, morphFrom: null };
  assert.equal(blendFrames(frame([circle]), frame([unlinked]), 0.5).length, 2);
  const still = blendFrames(frame([circle]), frame([circle, { ...triangle, id: "other" }]), 0.5);
  assert.equal(still.length, 2, "an area still there is not formed into another");
  const twice = blendFrames(frame([circle]), frame([triangle, { ...triangle, id: "second" }]), 0.5);
  assert.equal(twice.filter(item => item.opacity === undefined || item.opacity === 1).length, 1, "the second comes in by itself");
  assert.deepEqual(areasGone(frame([circle, { ...circle, id: "kept" }]), frame([{ ...circle, id: "kept" }])).map(item => item.id), ["circle"]);
});
