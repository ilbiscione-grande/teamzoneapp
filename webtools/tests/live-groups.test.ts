import assert from "node:assert/strict";
import { test } from "node:test";
import { createPlayer, newDocument } from "../lib/tactics/document.ts";
import { groupBoard, groupCounts, groupError, groupTopic, mergeGroupMoves } from "../lib/tactics/live-groups.ts";

test("live groups: topics, counts and errors", () => {
  assert.equal(groupTopic("g1"), "tactics-live-group:g1");
  assert.deepEqual(groupCounts(0), [2]);
  assert.deepEqual(groupCounts(4), [2, 3, 4]);
  assert.deepEqual(groupCounts(12), [2, 3, 4, 5, 6]);
  assert.match(groupError("ERROR: invalid_group_count"), /2 och 6/);
  assert.match(groupError("no_group"), /någon grupp/);
});

test("live groups: the group's board is the starting board with the moves in place", () => {
  const board = newDocument("Tavla 1").boards[0];
  const player = createPlayer({ x: 10, y: 10 }, "home", []);
  const start = { ...board, frames: [{ ...board.frames[0], objects: [player] }] };
  const moved = groupBoard(start, { 0: { [player.id]: { x: 30, y: 20 } }, 7: { [player.id]: { x: 1, y: 1 } } });
  assert.deepEqual([moved.frames[0].objects[0].x, moved.frames[0].objects[0].y], [30, 20]);
  assert.equal(start.frames[0].objects[0].x, 10, "the starting board is untouched");
  assert.equal(groupBoard(start, {}).frames[0].objects[0].x, 10);
});

test("live groups: moves merge per frame, the latest winning", () => {
  const first = mergeGroupMoves({}, 0, { a: { x: 1, y: 1 } });
  const second = mergeGroupMoves(first, 0, { b: { x: 2, y: 2 }, a: { x: 3, y: 3 } });
  assert.deepEqual(mergeGroupMoves(second, 1, { a: { x: 4, y: 4 } }), { 0: { a: { x: 3, y: 3 }, b: { x: 2, y: 2 } }, 1: { a: { x: 4, y: 4 } } });
  assert.deepEqual(first, { 0: { a: { x: 1, y: 1 } } }, "the old moves are untouched");
});
