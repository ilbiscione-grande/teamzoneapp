import assert from "node:assert/strict";
import { test } from "node:test";
import { dropBall } from "../lib/tactics/ball.ts";
import { createObject, createPlayer, newFrame } from "../lib/tactics/document.ts";
import type { BallObject, Frame, LineObject, TacticsObject } from "../lib/tactics/model.ts";
import { blendFrames, curvePoint, easeInOut, objectsAt, playheadAt, totalTime, type Rendered } from "../lib/tactics/timeline.ts";

const near = (a: number, b: number, tolerance = 1e-9) => assert.ok(Math.abs(a - b) < tolerance, `${a} ≈ ${b}`);
const frame = (objects: TacticsObject[], durationMs = 1000): Frame => ({ ...newFrame(objects), durationMs });

test("the playhead walks the moves and stops, or loops", () => {
  const frames = [frame([]), frame([], 1000), frame([], 2000)];
  assert.equal(totalTime(frames), 3000);
  assert.equal(totalTime(frames, 2), 1500);
  assert.equal(playheadAt(frames, 0), 0);
  assert.equal(playheadAt(frames, 500), 0.5);
  assert.equal(playheadAt(frames, 2000), 1.5);
  assert.equal(playheadAt(frames, 3000), null, "over");
  assert.equal(playheadAt(frames, 3500, 1, true), 0.5, "round again");
  assert.equal(playheadAt(frames, 500, 2), 1, "twice as fast");
  assert.equal(playheadAt(frames, 1000, 1, false, 1), 1.5, "from frame 1");
  assert.equal(playheadAt([frame([])], 0), null, "one frame does not play");
});

test("players glide, eased, and bend through their path's control", () => {
  const player = createPlayer({ x: 0, y: 0 }, "home", []);
  const from = frame([player]);
  const to = frame([{ ...player, x: 10, y: 0 }]);
  const mid = blendFrames(from, to, 0.5)[0];
  near(mid.x, 5);
  near(easeInOut(0.25), 0.0625);
  near(blendFrames(from, to, 0.25)[0].x, 10 * easeInOut(0.25));
  const bent = frame([{ ...player, x: 10, y: 0, pathControl: { x: 5, y: 10 } }]);
  near(blendFrames(from, bent, 0.5)[0].y, 5, 1e-9);
  near(curvePoint({ x: 0, y: 0 }, { x: 10, y: 0 }, null, 0.3).x, 3);
  // Turning takes the short way round.
  const cone = createObject("cone", { x: 0, y: 0 });
  const turned = blendFrames(frame([{ ...cone, rotation: 350 }]), frame([{ ...cone, rotation: 10 }]), 0.5)[0];
  near(turned.rotation % 360, 0);
});

test("new objects come in by their effect, gone ones fade out", () => {
  const stays = createObject("cone", { x: 0, y: 0 });
  const goes = createObject("pole", { x: 1, y: 1 });
  const comes = createObject("text", { x: 2, y: 2 });
  const pops = { ...createObject("goal", { x: 3, y: 3 }), effect: "pop" as const };
  const result = blendFrames(frame([stays, goes]), frame([stays, comes, pops]), 0.5);
  const byId = (id: string) => result.find(item => item.id === id) as Rendered;
  assert.equal(byId(stays.id).opacity, undefined);
  assert.equal(byId(comes.id).opacity, 0.5);
  assert.equal(byId(goes.id).opacity, 0.5);
  assert.ok((byId(pops.id).grow ?? 0) > 1, "a pop overshoots");
  const arrow: LineObject = { id: "l", x: 0, y: 0, rotation: 0, locked: false, hidden: false, type: "line", points: [0, 0, 10, 0], control: null, arrow: "end", dashed: false, color: "#fff", width: 0.3, effect: "draw" };
  assert.equal((blendFrames(frame([]), frame([arrow]), 0.3)[0] as Rendered).drawn, 0.3);
  const pulsing = { ...stays, effect: "pulse" as const };
  assert.notEqual(blendFrames(frame([stays]), frame([pulsing]), 0.1)[0].grow, undefined);
});

test("a held ball rides with its player; a pass travels between players", () => {
  const a = createPlayer({ x: 10, y: 10 }, "home", []);
  const b = createPlayer({ x: 30, y: 10 }, "home", [a]);
  const ball = createObject("ball", { x: 0, y: 0 }) as BallObject;
  const held = dropBall(ball, { x: 12, y: 10 }, [a, b]);
  // A runs with the ball.
  const run = blendFrames(frame([a, b, held]), frame([{ ...a, x: 20 }, b, { ...held, x: 20 + held.offset!.x }]), 0.5);
  const runner = run.find(item => item.id === a.id)!;
  const rolling = run.find(item => item.id === ball.id)!;
  near(rolling.x - runner.x, held.offset!.x);
  // A passes to B: the ball goes from A's edge to B's.
  const passed = dropBall(held, { x: 28, y: 10 }, [a, b]);
  const pass = blendFrames(frame([a, b, held]), frame([a, b, passed]), 1);
  near(pass.find(item => item.id === ball.id)!.x, passed.x);
  const halfway = blendFrames(frame([a, b, held]), frame([a, b, passed]), 0.5).find(item => item.id === ball.id)!;
  near(halfway.x, (held.x + passed.x) / 2);
});

test("the board at a playhead is a frame or a move", () => {
  const player = createPlayer({ x: 0, y: 0 }, "home", []);
  const frames = [frame([player]), frame([{ ...player, x: 10 }])];
  assert.equal(objectsAt(frames, 0)[0].x, 0);
  assert.equal(objectsAt(frames, 1)[0].x, 10);
  near(objectsAt(frames, 0.5)[0].x, 5);
  assert.deepEqual(objectsAt([], 0), []);
});

test("frames are copied after, removed, moved and timed", async () => {
  const { insertFrame, moveFrame, newBoard, removeFrame, setFrameDuration } = await import("../lib/tactics/document.ts");
  const player = { ...createPlayer({ x: 0, y: 0 }, "home", []), effect: "pop" as const, pathControl: { x: 1, y: 1 } };
  let board = newBoard("Tavla");
  board = { ...board, frames: [{ ...board.frames[0], objects: [player] }] };
  board = insertFrame(board, 0);
  assert.equal(board.frames.length, 2);
  assert.equal(board.frames[1].objects[0].id, player.id, "the same object moves between frames");
  assert.equal(board.frames[1].objects[0].effect, null);
  assert.notEqual(board.frames[1].id, board.frames[0].id);
  const second = board.frames[1].id;
  board = moveFrame(board, 1, -1);
  assert.equal(board.frames[0].id, second);
  assert.equal(moveFrame(board, 0, -1), board);
  board = setFrameDuration(board, 1, 50);
  assert.equal(board.frames[1].durationMs, 200, "at least 200 ms");
  board = removeFrame(board, 0);
  assert.equal(board.frames.length, 1);
  assert.equal(removeFrame(board, 0), board, "the last frame stays");
});

test("curves pass through their middle point and lines draw out by length", async () => {
  const { controlThrough, curveMiddle, partialPolyline, sampleCurve } = await import("../lib/tactics/path.ts");
  const from = { x: 0, y: 0 }, to = { x: 10, y: 0 }, through = { x: 5, y: 4 };
  const middle = curveMiddle(from, to, controlThrough(from, to, through));
  near(middle.x, 5); near(middle.y, 4);
  const points = sampleCurve(from, to, through, 24);
  assert.equal(points.length, 50);
  near(points[24], 5); near(points[25], 4);
  assert.deepEqual(sampleCurve(from, to, null), [0, 0, 10, 0]);
  assert.deepEqual(partialPolyline([0, 0, 10, 0], 0.3), [0, 0, 3, 0]);
  assert.deepEqual(partialPolyline([0, 0, 10, 0, 10, 10], 0.75), [0, 0, 10, 0, 10, 5]);
  assert.deepEqual(partialPolyline([0, 0, 10, 0], 0), [0, 0, 0, 0]);
  assert.deepEqual(partialPolyline([0, 0, 10, 0], 1), [0, 0, 10, 0]);
});

test("PDF pages: one picture a page, four frames to a page, or the last frame", async () => {
  const { layoutPages, PAGE, pdfFileName } = await import("../lib/tactics/pdf-layout.ts");
  const { newBoard, insertFrame } = await import("../lib/tactics/document.ts");
  let animated = newBoard("Anfall");
  for (let i = 0; i < 4; i++) animated = insertFrame(animated, i);
  animated = { ...animated, frames: animated.frames.map((frame, i) => i === 1 ? { ...frame, note: " Djupledslöpning " } : frame) };
  const still = newBoard("Uppställning");
  const boards = [still, animated];
  const grid = layoutPages(boards, [0, 1], "grid");
  assert.deepEqual(grid.map(page => [page.title, page.placements.length]), [["Uppställning", 1], ["Anfall", 4], ["Anfall", 1]]);
  assert.equal(grid[0].placements[0].caption, null, "a still board has no frame captions");
  assert.equal(grid[1].placements[1].caption, "Frame 2 av 5");
  assert.equal(grid[1].placements[1].note, "Djupledslöpning");
  for (const page of grid) for (const item of page.placements) {
    assert.ok(item.x >= PAGE.margin - 1e-9 && item.x + item.width <= PAGE.width - PAGE.margin + 1e-9, "inside the margins");
    assert.ok(item.y + item.height <= PAGE.height - PAGE.margin - PAGE.footer + 1e-9);
    near(item.width / item.height, 1.5);
  }
  assert.equal(layoutPages(boards, [1], "each").length, 5);
  const last = layoutPages(boards, [1], "last");
  assert.deepEqual([last.length, last[0].placements[0].frameIndex, last[0].placements[0].caption], [1, 4, null]);
  // A description takes a column on the board's first page only, the pictures narrower there.
  const described = [{ ...still, description: " Organisation: 11 mot 11. " }, { ...animated, description: "Coachpunkter" }];
  const withText = layoutPages(described, [0, 1], "grid");
  assert.deepEqual(withText.map(page => page.description?.text ?? null), ["Organisation: 11 mot 11.", "Coachpunkter", null]);
  for (const page of withText) for (const item of page.placements) {
    if (page.description) assert.ok(item.x + item.width <= page.description.x - 1e-9, "left of the description");
    near(item.width / item.height, 1.5);
  }
  assert.ok(withText[0].description!.x + withText[0].description!.width <= PAGE.width - PAGE.margin + 1e-9);
  assert.equal(layoutPages(described, [1], "each").filter(page => page.description).length, 1);
  assert.equal(pdfFileName(" Match mot Aneby SK! "), "Match_mot_Aneby_SK.pdf");
  assert.equal(pdfFileName("??"), "tavla.pdf");
});
