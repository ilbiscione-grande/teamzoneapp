import assert from "node:assert/strict";
import { test } from "node:test";
import { createObject, createPlayer, newFrame } from "../lib/tactics/document.ts";
import { blendViewport, fitView, pitchToFrame, viewRect, zoomTo } from "../lib/tactics/geometry.ts";
import { arrowOf, cameraAt, movesInto, zoomScales } from "../lib/tactics/marks.ts";
import type { Effect, Frame, TacticsObject } from "../lib/tactics/model.ts";
import { objectsAt, type Rendered } from "../lib/tactics/timeline.ts";

const near = (a: number, b: number, tolerance = 1e-9) => assert.ok(Math.abs(a - b) < tolerance, `${a} ≈ ${b}`);
const frame = (objects: TacticsObject[]): Frame => ({ ...newFrame(objects), durationMs: 1000, easing: "linear" });
const withEffects = <T extends TacticsObject>(item: T, ...effects: Effect[]): T => ({ ...item, effects });

test("an arrow draws out ahead along the way, curve and all, and goes as the object passes", () => {
  const player = createPlayer({ x: 0, y: 0 }, "home", []);
  const there = withEffects({ ...player, x: 10, y: 0, pathControl: { x: 5, y: 6 } }, "arrow");
  const [from, to] = [frame([player]), frame([there])];
  const early = arrowOf(from, to, player.id, 0.1)!;
  assert.ok(early.length > 4);
  const tip = early.slice(-2);
  assert.ok(tip[0] > 0 && tip[0] < 10, "not yet at the end");
  const drawn = arrowOf(from, to, player.id, 0.5)!;
  near(drawn[0], 5, 1e-9);
  near(drawn[1], 3, 1e-9);
  near(drawn.at(-2)!, 10);
  near(drawn.at(-1)!, 0);
  // The middle of the drawn part follows the bend, off the straight line.
  assert.ok(drawn[Math.floor(drawn.length / 4) * 2 + 1] > 0);
  assert.equal(arrowOf(from, to, player.id, 1), null, "there: no arrow");
  assert.equal(arrowOf(from, frame([{ ...there, effects: [] }]), player.id, 0.5), null, "without the effect");
  const shown = objectsAt([from, to], 0.5)[0] as Rendered;
  assert.equal(shown.trails?.[0].arrow, true);
  assert.equal((objectsAt([from, to], 1)[0] as Rendered).trails, undefined, "gone on reaching the frame");
});

test("a ring comes on over the move, stays at its frame and fades over the next", () => {
  const cone = createObject("cone", { x: 3, y: 3 });
  const ringed = withEffects(cone, "ring");
  const frames = [frame([cone]), frame([ringed]), frame([cone])];
  const coming = objectsAt(frames, 0.1)[0] as Rendered;
  assert.ok(coming.ring && coming.ring.opacity > 0 && coming.ring.opacity < 1 && coming.ring.grow > 1);
  assert.deepEqual((objectsAt(frames, 1)[0] as Rendered).ring, { opacity: 1, grow: 1 });
  near((objectsAt(frames, 1.25)[0] as Rendered).ring!.opacity, 0.75);
  assert.equal((objectsAt(frames, 0)[0] as Rendered).ring, undefined);
});

test("zoom: in quickly on the object and stays; a next zoom keeps it in, otherwise out again", () => {
  const a = createPlayer({ x: 10, y: 10 }, "home", []);
  const b = createPlayer({ x: 40, y: 30 }, "away", []);
  const frames = [frame([a, b]), frame([withEffects(a, "zoom"), b]), frame([a, withEffects(b, "zoom")]), frame([a, b])];
  const at = (playhead: number) => cameraAt(frames, playhead, objectsAt(frames, playhead));
  assert.equal(at(0), null);
  const zoomingIn = at(0.1)!;
  assert.ok(zoomingIn.amount > 0 && zoomingIn.amount < 1);
  assert.deepEqual(at(0.5), { at: { x: 10, y: 10 }, amount: 1, scale: zoomScales.medium });
  assert.deepEqual(at(1), { at: { x: 10, y: 10 }, amount: 1, scale: zoomScales.medium }, "stays on the frame");
  const gliding = at(1.1)!;
  assert.equal(gliding.amount, 1, "the next frame zooms too: stays in");
  assert.ok(gliding.at.x > 10 && gliding.at.x < 40);
  assert.deepEqual(at(1.5)!.at, { x: 40, y: 30 });
  const out = at(2.1)!;
  assert.ok(out.amount < 1 && out.amount > 0, "the next does not zoom: out again");
  near(at(2.5)!.amount, 0);
  assert.equal(at(3), null);
});

test("the view zoomed in on a pitch point has it in the middle", () => {
  const fit = fitView(viewRect("full"), 1000, 700);
  const view = zoomTo({ x: 30, y: 20 }, fit, 1000, 700, 2);
  const onScreen = pitchToFrame({ x: 30, y: 20 }, fit);
  near(view.x + onScreen.x * view.scale, 500);
  near(view.y + onScreen.y * view.scale, 350);
  assert.deepEqual(blendViewport({ x: 0, y: 0, scale: 1 }, view, 0), { x: 0, y: 0, scale: 1 });
  // At the touchline the view stops at the edge instead of showing beyond it.
  const edge = zoomTo({ x: 50, y: 0 }, fit, 1000, 700, 2);
  near(edge.y, 0);
  const corner = zoomTo({ x: 105, y: 68 }, fit, 1000, 700, 2);
  near(corner.x, 1000 - 2000);
  near(corner.y, 700 - 1400);
  near(blendViewport({ x: 0, y: 0, scale: 1 }, view, 0.5).scale, 1.5);
});

test("duplicating a board puts a copy right after it, frames and effects alike, with new ids", async () => {
  const { newDocument, newBoard } = await import("../lib/tactics/document.ts");
  const { duplicateBoard } = await import("../lib/tactics/templates.ts");
  const document = newDocument("Inspark");
  const cone = withEffects(createObject("cone", { x: 1, y: 1 }), "ring");
  const first = { ...document.boards[0], frames: [frame([cone]), frame([cone])] };
  const other = newBoard("Avspark");
  const { document: copied, copyId } = duplicateBoard({ ...document, boards: [first, other] }, first.id);
  assert.deepEqual(copied.boards.map(board => board.name), ["Inspark", "Inspark (kopia)", "Avspark"]);
  const copy = copied.boards[1];
  assert.equal(copy.id, copyId);
  assert.notEqual(copy.id, first.id);
  assert.equal(copy.frames.length, 2);
  assert.notEqual(copy.frames[0].id, first.frames[0].id);
  assert.deepEqual(copy.frames[1].objects[0].effects, ["ring"]);
  assert.equal(duplicateBoard(copied, "unknown").copyId, null);
});

test("a still picture shows every move into its frame as a whole arrow, passes told apart", async () => {
  const { dropBall } = await import("../lib/tactics/ball.ts");
  const runner = createPlayer({ x: 10, y: 10 }, "home", []);
  const passer = createPlayer({ x: 20, y: 30 }, "home", []);
  const still = createPlayer({ x: 40, y: 40 }, "away", []);
  const ball = dropBall(createObject("ball", { x: 21, y: 30 }) as Parameters<typeof dropBall>[0], { x: 21, y: 30 }, [passer]);
  const text = createObject("text", { x: 5, y: 5 });
  const start = frame([runner, passer, still, ball, text]);
  const moved = { ...runner, x: 30, y: 10, pathControl: { x: 20, y: 0 } };
  const passed = dropBall(ball, { x: 31, y: 10 }, [moved, passer]);
  const end = frame([moved, passer, still, passed, { ...text, x: 50 }]);
  const moves = movesInto([start, end], 1);
  assert.equal(moves.length, 2, "the runner and the pass; not the still player or the text");
  const run = moves.find(move => !move.ball)!;
  assert.equal(run.arrow, true);
  near(run.points[0], 10);
  near(run.points.at(-2)!, 30);
  assert.ok(Math.min(...run.points.filter((_, i) => i % 2 === 1)) < 10, "follows the bend");
  assert.ok(moves.some(move => move.ball));
  assert.deepEqual(movesInto([start, end], 0), [], "the first frame has no moves");
});

test("each zoomed object chooses how close the view goes; gliding between two blends it", () => {
  const a = { ...createPlayer({ x: 10, y: 10 }, "home", []), zoomLevel: "close" as const };
  const b = { ...createPlayer({ x: 40, y: 30 }, "away", []), zoomLevel: "wide" as const };
  const frames = [frame([a, b]), frame([withEffects(a, "zoom"), b]), frame([a, withEffects(b, "zoom")])];
  const at = (playhead: number) => cameraAt(frames, playhead, objectsAt(frames, playhead))!;
  assert.equal(at(1).scale, zoomScales.close);
  assert.equal(at(2).scale, zoomScales.wide);
  const gliding = at(1.1).scale;
  assert.ok(gliding < zoomScales.close && gliding > zoomScales.wide);
  const unchosen = [frame([a]), frame([{ ...withEffects(a, "zoom"), zoomLevel: undefined }])];
  assert.equal(cameraAt(unchosen, 1, unchosen[1].objects)!.scale, zoomScales.medium);
});
