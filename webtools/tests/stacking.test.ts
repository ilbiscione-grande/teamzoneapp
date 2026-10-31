import assert from "node:assert/strict";
import test from "node:test";
import { createObject, createPlayer, layered, moveNextTo, stack } from "../lib/tactics/document.ts";
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

test("a dragged object is put next to another", () => {
  assert.equal(ids(moveNextTo(objects(), "a", "d", true)), "bcdae");
  assert.equal(ids(moveNextTo(objects(), "e", "a", false)), "eabcd");
});

test("objects are drawn in layers and ordered within their own", () => {
  const ball = { ...createObject("ball", { x: 0, y: 0 }), id: "B" };
  const player: TacticsObject = { ...createPlayer({ x: 0, y: 0 }, "home", []), id: "P" };
  const mixed = [ball, ...objects().slice(0, 2), player];
  assert.equal(ids(layered(mixed)), "abPB");
  // Top of its layer: under the players still.
  assert.equal(ids(stack(mixed, ["a"], "top")), "baPB");
  // A player cannot be dragged among the cones.
  assert.equal(moveNextTo(mixed, "P", "a", true), mixed);
  // Already as drawn: nothing to change.
  assert.equal(stack(mixed, ["P"], "top"), mixed);
});
