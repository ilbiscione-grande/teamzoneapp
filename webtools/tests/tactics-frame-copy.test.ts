import assert from "node:assert/strict";
import { test } from "node:test";
import { createObject, createPlayer, duplicateFrame, newBoard, newFrame } from "../lib/tactics/document.ts";
import type { Board, Effect, TacticsObject } from "../lib/tactics/model.ts";

const player = { ...createPlayer({ x: 10, y: 10 }, "home", []), effects: ["pulse"] as Effect[], zoomLevel: "close", pathControl: { x: 5, y: 5 } } as TacticsObject;
const ball = { ...createObject("ball", { x: 20, y: 20 }), flight: "chip", pathControl: { x: 8, y: 8 } } as TacticsObject;
const first = { ...newFrame([createPlayer({ x: 1, y: 1 }, "home", [])]) };
const second = { ...newFrame([player, ball]), durationMs: 3000, easing: "linear", note: "Pressen" } as Board["frames"][number];
const board: Board = { ...newBoard("Tavla"), frames: [first, second, newFrame([])] };

test("a frame is copied right after itself, with all it holds", () => {
  const copied = duplicateFrame(board, 1);
  assert.equal(copied.frames.length, 4);
  assert.equal(copied.frames[1], second, "the frame copied stays");
  const copy = copied.frames[2];
  assert.notEqual(copy.id, second.id);
  assert.deepEqual([copy.durationMs, copy.easing, copy.note], [3000, "linear", "Pressen"]);
  assert.deepEqual(copy.objects.map(item => item.id), [player.id, ball.id], "the same objects, so they carry on");
  assert.deepEqual(copy.objects[0].effects, ["pulse"]);
  assert.equal(copy.objects[0].zoomLevel, "close");
  assert.equal(copied.frames[3], board.frames[2], "the next frame comes after the copy");
});

test("nothing swings or lifts into a copy, where nothing moves", () => {
  const [copiedPlayer, copiedBall] = duplicateFrame(board, 1).frames[2].objects;
  assert.equal(copiedPlayer.pathControl, null);
  assert.equal(copiedBall.pathControl, null);
  assert.equal((copiedBall as { flight?: string }).flight, undefined);
});
