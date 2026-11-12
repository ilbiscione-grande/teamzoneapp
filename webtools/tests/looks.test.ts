import assert from "node:assert/strict";
import { test } from "node:test";
import { dropBall } from "../lib/tactics/ball.ts";
import { createObject, createPlayer, newBoard, newFrame, setBallFlight } from "../lib/tactics/document.ts";
import { spotlightAt } from "../lib/tactics/marks.ts";
import type { BallObject, Effect, Frame, TacticsObject } from "../lib/tactics/model.ts";
import { objectsAt, standingFacing, type Rendered } from "../lib/tactics/timeline.ts";

const near = (a: number, b: number, tolerance = 1e-6) => assert.ok(Math.abs(a - b) < tolerance, `${a} ≈ ${b}`);
const frame = (objects: TacticsObject[]): Frame => ({ ...newFrame(objects), durationMs: 1000, easing: "linear" });
const withEffects = <T extends TacticsObject>(item: T, ...effects: Effect[]): T => ({ ...item, effects });

function pass(flight?: BallObject["flight"]) {
  const from = createPlayer({ x: 10, y: 30 }, "home", []);
  const to = createPlayer({ x: 40, y: 30 }, "home", []);
  const ball = dropBall(createObject("ball", { x: 11, y: 30 }) as BallObject, { x: 11, y: 30 }, [from]);
  const passed = { ...dropBall(ball, { x: 39, y: 30 }, [to]), ...(flight ? { flight } : {}) };
  return [frame([from, to, ball]), frame([from, to, passed])];
}
const ballAt = (frames: Frame[], playhead: number) => objectsAt(frames, playhead).find(item => item.type === "ball") as Rendered;

test("a lofted pass rises highest halfway and lands; a ground pass stays down", () => {
  assert.equal(ballAt(pass(), 0.5).lift, undefined);
  const chip = pass("chip"), high = pass("high");
  near(ballAt(chip, 0.5).lift!, 3);
  near(ballAt(high, 0.5).lift!, 7);
  assert.ok(ballAt(high, 0.25).lift! < 7 && ballAt(high, 0.25).lift! > 0);
  assert.equal(ballAt(high, 1).lift, undefined, "landed");
});

test("a ball in the air bends off its shadow to the side up on the pitch, the way a pass arrow in the air does", () => {
  assert.equal(ballAt(pass(), 0.5).rise, undefined);
  const high = ballAt(pass("high"), 0.5);
  near(high.rise!.x, 0);
  near(high.rise!.y, -7 * 0.45);
  assert.ok(Math.abs(ballAt(pass("chip"), 0.5).rise!.y) < Math.abs(high.rise!.y), "a chip bends less");
  assert.equal(ballAt(pass("high"), 1).rise, undefined, "landed on its shadow");
});

test("a long ball slows its frame down, a chip less, and back on the ground the frame has its time again", () => {
  const frames = pass();
  const board = { ...newBoard("Tavla"), frames };
  const ballId = frames[1].objects.find(item => item.type === "ball")!.id;
  const high = setBallFlight(board, 1, ballId, "high");
  assert.equal(high.frames[1].durationMs, 1500);
  assert.equal((high.frames[1].objects.find(item => item.id === ballId) as BallObject).flight, "high");
  assert.equal(high.frames[0], board.frames[0], "the frame before is left as it was");
  const chip = setBallFlight(high, 1, ballId, "chip");
  assert.equal(chip.frames[1].durationMs, 1300);
  assert.equal(setBallFlight(setBallFlight(board, 1, ballId, "high"), 1, ballId, "ground").frames[1].durationMs, 1000);
});

test("a running player faces the way of the run, then turns to their own facing as they arrive", () => {
  const player = createPlayer({ x: 10, y: 10 }, "home", []);
  const there = { ...player, x: 10, y: 40, rotation: 0 };
  const frames = [frame([player]), frame([there])];
  near((objectsAt(frames, 0.4)[0] as Rendered).facing!, 90, 1e-3);
  near((objectsAt(frames, 0.999)[0] as Rendered).facing!, 0, 1);
  assert.equal(standingFacing({ ...player, side: "away" }), 180, "the away side faces the home goal");
  assert.equal((objectsAt([frame([player]), frame([{ ...player, x: 10.1 }])], 0.5)[0] as Rendered).facing, undefined, "a step is not a run");
});

test("the spotlight darkens round its objects, stays on the frame and lifts over the next move", () => {
  const a = createPlayer({ x: 10, y: 10 }, "home", []);
  const b = createPlayer({ x: 40, y: 30 }, "away", []);
  const frames = [frame([a, b]), frame([withEffects(a, "spotlight"), b]), frame([a, b])];
  const at = (playhead: number) => spotlightAt(frames, playhead, objectsAt(frames, playhead));
  assert.equal(at(0), null);
  const coming = at(0.1)!;
  assert.ok(coming.amount > 0 && coming.amount < 1);
  assert.deepEqual(at(1), { amount: 1, spots: [{ x: 10, y: 10 }] });
  near(at(1.5)!.amount, 0);
  assert.equal(at(2), null);
});
