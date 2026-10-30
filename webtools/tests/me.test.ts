import assert from "node:assert/strict";
import { test } from "node:test";
import { newDocument } from "../lib/tactics/document.ts";
import { isMe, numbersOn } from "../lib/tactics/me.ts";
import type { Board, TacticsObject } from "../lib/tactics/model.ts";

const player = (id: string, side: "home" | "away", number: number | null, name: string | null = null): TacticsObject =>
  ({ id, type: "player", x: 10, y: 10, rotation: 0, locked: false, hidden: false, side, number, name, personId: null, color: null }) as TacticsObject;

test("the home team's numbers, each once, named where any board names them", () => {
  const first: Board = newDocument().boards[0];
  first.frames[0].objects = [player("a", "home", 7), player("b", "home", 3), player("c", "away", 9), player("d", "home", null)];
  const second: Board = { ...newDocument().boards[0], id: "second" };
  second.frames[0].objects = [player("e", "home", 7, "Perrone")];
  assert.deepEqual(numbersOn([first, second]), [{ number: 3, name: null }, { number: 7, name: "Perrone" }]);
});

test("only the home player with the number is me", () => {
  assert.equal(isMe(player("a", "home", 7), 7), true);
  assert.equal(isMe(player("a", "away", 7), 7), false);
  assert.equal(isMe(player("a", "home", 7), null), false);
});
