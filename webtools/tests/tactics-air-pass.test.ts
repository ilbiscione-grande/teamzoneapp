import assert from "node:assert/strict";
import { test } from "node:test";
import { airPoints } from "../lib/tactics/path.ts";

const pairs = (points: number[]) => Array.from({ length: points.length / 2 }, (_, index) => ({ x: points[index * 2], y: points[index * 2 + 1] }));

test("a pass in the air starts and lands where the pass does, highest halfway", () => {
  const arc = pairs(airPoints([0, 0, 40, 0]));
  assert.deepEqual(arc[0], { x: 0, y: 0 });
  const last = arc[arc.length - 1];
  assert.ok(Math.abs(last.x - 40) < 1e-9 && Math.abs(last.y) < 1e-9);
  const middle = arc[Math.floor(arc.length / 2)];
  assert.ok(Math.abs(middle.x - 20) < 1e-9);
  assert.equal(middle.y, -4, "a tenth of 40 m, bent up the pitch");
});

test("the arc is never more than 5 m high, and bends up the pitch whichever way the pass goes", () => {
  const long = pairs(airPoints([100, 30, 0, 30]));
  assert.equal(Math.min(...long.map(point => point.y)), 25);
  const across = pairs(airPoints([10, 60, 10, 20]));
  assert.ok(across.every(point => point.x <= 10), "a pass straight up the pitch bends left");
});

test("too short to arc, the pass is left as it is", () => {
  assert.deepEqual(airPoints([5, 5, 5, 5]), [5, 5, 5, 5]);
});
