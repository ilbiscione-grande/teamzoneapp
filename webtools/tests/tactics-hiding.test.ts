import assert from "node:assert/strict";
import { test } from "node:test";
import { createObject, createPlayer, newBoard, newFrame } from "../lib/tactics/document.ts";
import { hideSide, sideHidden } from "../lib/tactics/hiding.ts";
import type { Frame, TacticsObject } from "../lib/tactics/model.ts";
import { objectsAt, type Rendered } from "../lib/tactics/timeline.ts";

const home = createPlayer({ x: 10, y: 10 }, "home", []);
const away = createPlayer({ x: 50, y: 30 }, "away", []);
const cone = createObject("cone", { x: 5, y: 5 });
const frame = (objects: TacticsObject[]): Frame => ({ ...newFrame(objects), durationMs: 1000, easing: "linear" });
const boardOf = (...frames: TacticsObject[][]) => ({ ...newBoard("Tavla"), frames: frames.map(frame) });

test("a team is hidden in one frame or in every frame, the other team and the rest left as they are", () => {
  const board = boardOf([home, away, cone], [home, away, cone], [home, cone]);
  const once = hideSide(board, 1, "away", true);
  assert.deepEqual(once.frames.map(each => sideHidden(each.objects, "away")), ["none", "all", null]);
  assert.equal(sideHidden(once.frames[1].objects, "home"), "none");
  assert.equal(once.frames[1].objects[2], cone);
  const all = hideSide(board, "all", "away", true);
  assert.deepEqual(all.frames.map(each => sideHidden(each.objects, "away")), ["all", "all", null]);
  assert.deepEqual(hideSide(all, "all", "away", false).frames.map(each => sideHidden(each.objects, "away")), ["none", "none", null]);
});

test("a team hidden from a frame on fades out on the way there, and fades in when shown again", () => {
  const hidden = { ...away, hidden: true };
  const frames = [frame([home, away]), frame([home, hidden]), frame([home, away])];
  const at = (playhead: number) => objectsAt(frames, playhead).find(item => item.id === away.id) as Rendered;
  assert.equal(at(0.25).opacity, 0.75);
  assert.equal(at(0.25).hidden, false, "still drawn while it fades");
  assert.equal(at(1).hidden, true);
  assert.equal(at(1.25).opacity, 0.25);
  assert.equal(at(1.25).hidden, false);
});
