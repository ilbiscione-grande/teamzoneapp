import assert from "node:assert/strict";
import { test } from "node:test";
import { facingToRotation, normalAngle, snapAngle } from "../lib/tactics/facing.ts";
import { fitView, viewRect } from "../lib/tactics/geometry.ts";
import { projectStage, projector, TILT } from "../lib/tactics/projection.ts";

const near = (a: number, b: number, tolerance = 1e-6) => assert.ok(Math.abs(a - b) < tolerance, `${a} ≈ ${b}`);

test("on the turning line the tilt only scales; the far side is narrower and the near side wider", () => {
  const [width, height] = [1000, 700];
  const onLine = projectStage({ x: 500, y: height * TILT.originY }, 0, width, height);
  near(onLine.depth, 1);
  near(onLine.x, 500);
  const farLeft = projectStage({ x: 100, y: 100 }, 0, width, height), farRight = projectStage({ x: 900, y: 100 }, 0, width, height);
  const nearLeft = projectStage({ x: 100, y: 650 }, 0, width, height), nearRight = projectStage({ x: 900, y: 650 }, 0, width, height);
  assert.ok(farRight.x - farLeft.x < nearRight.x - nearLeft.x, "perspective");
  assert.ok(farLeft.depth < 1 && nearLeft.depth > 1);
});

test("something up off the ground shows higher on the screen than its foot", () => {
  const foot = projectStage({ x: 500, y: 400 }, 0, 1000, 700);
  const head = projectStage({ x: 500, y: 400 }, 40, 1000, 700);
  assert.ok(head.y < foot.y);
  near(head.x, foot.x, 1e-6);
});

test("the pitch through the board's fit and zoom: the far touchline above the near, the middle between", () => {
  const fit = fitView(viewRect("full"), 1000, 700);
  const project = projector(fit, { x: 0, y: 0, scale: 1 }, 1000, 700);
  const far = project({ x: 52.5, y: 0 }), middle = project({ x: 52.5, y: 34 }), nearSide = project({ x: 52.5, y: 68 });
  assert.ok(far.y < middle.y && middle.y < nearSide.y);
  near(project.metre, fit.scale);
});

test("turning a player: angles snap to 15° and the away side's turn counts from the home goal", () => {
  assert.equal(snapAngle(52), 45);
  assert.equal(snapAngle(-5), 0);
  assert.equal(snapAngle(-8), 345, "nearer -15 than 0");
  assert.equal(normalAngle(-90), 270);
  assert.equal(facingToRotation(0, "home"), 0);
  assert.equal(facingToRotation(0, "away"), 180);
  assert.equal(facingToRotation(180, "away"), 0);
});
