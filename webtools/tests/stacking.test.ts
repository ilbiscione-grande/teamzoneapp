import assert from "node:assert/strict";
import test from "node:test";
import { createObject, moveTo, stack } from "../lib/tactics/document.ts";
import type { TacticsObject } from "../lib/tactics/model.ts";

const objects = (): TacticsObject[] => ["a", "b", "c", "d", "e"].map(id => ({ ...createObject("cone", { x: 0, y: 0 }), id }));
const ids = (list: TacticsObject[]) => list.map(item => item.id).join("");

test("chosen objects move a step together, keeping their order", () => {
  assert.equal(ids(stack(objects(), ["b", "c"], "up")), "adbce");
  assert.equal(ids(stack(objects(), ["b", "d"], "down")), "badce");
  assert.equal(ids(stack(objects(), ["b", "c"], "down")), "bcade");
});

test("to the top or the bottom", () => {
  assert.equal(ids(stack(objects(), ["d", "a"], "top")), "bcead");
  assert.equal(ids(stack(objects(), ["d", "b"], "bottom")), "bdace");
});

test("nothing changes where they cannot go further", () => {
  const list = objects();
  assert.equal(stack(list, ["e"], "up"), list);
  assert.equal(stack(list, ["a"], "bottom"), list);
  assert.equal(stack(list, ["x"], "top"), list);
});

test("a dragged object is put in its place", () => {
  assert.equal(ids(moveTo(objects(), "a", 3)), "bcdae");
  assert.equal(ids(moveTo(objects(), "e", 0)), "eabcd");
});
