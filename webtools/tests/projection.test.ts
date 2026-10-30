import assert from "node:assert/strict";
import { test } from "node:test";
import { facingToRotation, normalAngle, snapAngle } from "../lib/tactics/facing.ts";
import { fitView, viewRect } from "../lib/tactics/geometry.ts";
import { groundReach, projectStage, projector, TILT, unproject } from "../lib/tactics/projection.ts";

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

test("a screen point back to the ground and out again lands where it was; the far side needs the most canvas", () => {
  const [width, height] = [1250, 700];
  for (const at of [{ x: 0, y: 0 }, { x: 625, y: 350 }, { x: 1250, y: 700 }, { x: 300, y: 120 }]) {
    const ground = unproject(at, width, height);
    const back = projectStage(ground, 0, width, height);
    near(back.x, at.x, 1e-6);
    near(back.y, at.y, 1e-6);
  }
  const reach = groundReach(width, height);
  assert.ok(reach.top > reach.bottom && reach.top > 0, "more beyond the far side than the near");
  assert.equal(reach.left, reach.right);
  assert.ok(reach.left > 0);
});

test("the canvas reaches no further than what is drawn, in whole steps", () => {
  const small = groundReach(1250, 700, { x: 100, y: 100, width: 1050, height: 500 });
  assert.deepEqual(small, { left: 0, top: 0, right: 0, bottom: 0 });
  const zoomed = groundReach(1250, 700, { x: -3000, y: -3000, width: 7000, height: 7000 });
  assert.deepEqual(zoomed, groundReach(1250, 700));
  assert.equal(zoomed.top % 64, 0);
});
