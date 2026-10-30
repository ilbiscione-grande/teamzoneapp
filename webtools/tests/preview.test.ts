import assert from "node:assert/strict";
import { test } from "node:test";
import { newDocument } from "../lib/tactics/document.ts";
import { previewOf, previewSummary } from "../lib/tactics/preview.ts";
import type { Board, TacticsObject } from "../lib/tactics/model.ts";

const player = (id: string, x: number, y: number, side: "home" | "away", number: number): TacticsObject =>
  ({ id, type: "player", x, y, rotation: 0, locked: false, hidden: false, side, number, name: null, personId: null, color: null }) as TacticsObject;

test("the preview has the first frame's players and free ball, inside the picture, in the teams' colours", () => {
  const board: Board = newDocument().boards[0];
  board.frames[0].objects = [
    player("a", 52.5, 34, "home", 10),
    player("b", 30, 20, "away", 4),
    { ...player("c", 60, 30, "home", 7), hidden: true },
    { id: "ball", type: "ball", x: 55, y: 34, rotation: 0, locked: false, hidden: false, attachedTo: null, offset: null } as TacticsObject,
  ];
  const preview = previewOf(board);
  assert.equal(preview.dots.length, 3, "the hidden one is left out");
  const ten = preview.dots.find(dot => dot.label === "10")!;
  assert.ok(Math.abs(ten.left - 0.5) < 1e-9 && Math.abs(ten.top - 0.5) < 1e-9, "the centre spot in the middle");
  assert.equal(ten.fill, board.teams.home.color);
  assert.ok(preview.dots.every(dot => dot.left >= 0 && dot.left <= 1 && dot.top >= 0 && dot.top <= 1));
  assert.ok(preview.dots.some(dot => dot.ball));
  assert.ok(preview.aspect > 1.4);
});

test("half a pitch leaves out what is off it; the summary counts boards", () => {
  const board: Board = { ...newDocument().boards[0], view: "attack" };
  board.frames[0].objects = [player("a", 90, 34, "home", 9), player("b", 10, 34, "away", 1)];
  assert.deepEqual(previewOf(board).dots.map(dot => dot.label), ["9"]);
  assert.equal(previewSummary("Match", 1, null), "Match · 1 tavla");
  assert.equal(previewSummary("Träning", 3, "P12"), "Träning · 3 tavlor · P12");
});
