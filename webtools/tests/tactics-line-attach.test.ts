import assert from "node:assert/strict";
import { test } from "node:test";
import { PLAYER_RADIUS } from "../lib/tactics/ball.ts";
import { createPlayer, updateFrame, newDocument } from "../lib/tactics/document.ts";
import { attachLine, settleLines } from "../lib/tactics/line-attach.ts";
import type { LineObject, TacticsObject } from "../lib/tactics/model.ts";

const pass = (x: number, y: number, dx: number, dy: number): LineObject => ({
  id: "pass", type: "line", x, y, rotation: 0, locked: false, hidden: false,
  points: [0, 0, dx, dy], control: null, arrow: "end", dashed: false, color: "#ffffff", width: 0.3,
});
const player = { ...createPlayer({ x: 10, y: 10 }, "home", []), id: "p1" };
const end = (line: LineObject) => ({ x: line.x + line.points[2], y: line.y + line.points[3] });
const close = (a: number, b: number) => Math.abs(a - b) < 1e-9;

test("an arrow drawn from a player sticks to them and starts at their ring, facing its end", () => {
  const line = attachLine(pass(10.5, 10, 20, 0), [player]);
  assert.equal(line.from, "p1");
  assert.ok(close(line.x, 10 + PLAYER_RADIUS) && close(line.y, 10));
  assert.ok(close(end(line).x, 30.5) && close(end(line).y, 10), "the end stays where it was drawn");
});

test("an arrow drawn away from players, or without a head, stays loose", () => {
  assert.equal(attachLine(pass(30, 30, 5, 0), [player]).from, undefined);
  assert.equal(attachLine({ ...pass(10, 10, 5, 0), arrow: "none" }, [player]).from, undefined);
  assert.equal(attachLine({ ...pass(30, 30, 5, 0), from: "p1" }, [player]).from, null, "a start dragged off the player lets go");
});

test("the start follows the player; the end stays put; a removed player lets go", () => {
  const line = attachLine(pass(10, 10, 20, 0), [player]);
  const moved: TacticsObject[] = [{ ...player, x: 10, y: 30 }, line];
  const settled = settleLines(moved)[1] as LineObject;
  assert.ok(close(end(settled).x, end(line).x) && close(end(settled).y, end(line).y));
  assert.ok(close(Math.hypot(settled.x - 10, settled.y - 30), PLAYER_RADIUS), "on the moved player's ring");
  assert.equal((settleLines([line])[0] as LineObject).from, null);
});

test("a frame changed through the document keeps arrows on their players", () => {
  const document = newDocument();
  const board = document.boards[0];
  const line = attachLine(pass(10, 10, 20, 0), [player]);
  const placed = updateFrame(document, board.id, 0, () => [player, line]);
  const moved = updateFrame(placed, board.id, 0, objects => objects.map(item => item.id === "p1" ? { ...item, x: 20, y: 10 } : item));
  const after = moved.boards[0].frames[0].objects.find(item => item.id === "pass") as LineObject;
  assert.ok(close(after.x, 20 + PLAYER_RADIUS));
});
