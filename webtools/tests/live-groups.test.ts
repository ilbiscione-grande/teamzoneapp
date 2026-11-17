import assert from "node:assert/strict";
import { test } from "node:test";
import { createPlayer, newDocument } from "../lib/tactics/document.ts";
import { groupBoard, groupCounts, groupError, groupPreview, groupTopic, mergeGroupMoves } from "../lib/tactics/live-groups.ts";

test("live groups: topics, counts and errors", () => {
  assert.equal(groupTopic("g1"), "tactics-live-group:g1");
  assert.deepEqual(groupCounts(0), [2]);
  assert.deepEqual(groupCounts(4), [2, 3, 4]);
  assert.deepEqual(groupCounts(12), [2, 3, 4, 5, 6]);
  assert.match(groupError("ERROR: invalid_group_count"), /2 och 6/);
  assert.match(groupError("no_group"), /någon grupp/);
  assert.match(groupError("invalid_participant"), /finns inte längre/);
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

test("live groups: the picture shows the group's frame as it stands", () => {
  const board = newDocument("Tavla 1").boards[0];
  const player = createPlayer({ x: 10, y: 10 }, "home", []);
  const start = { ...board, frames: [{ ...board.frames[0], objects: [] }, { ...board.frames[0], objects: [player] }] };
  const group = { id: "g", number: 1, board_id: start.id, frame_index: 1, members: [], board: start, moves: { 1: { [player.id]: { x: 40, y: 30 } } } };
  const preview = groupPreview(group);
  assert.deepEqual([preview.objects.length, preview.objects[0].x, preview.view], [1, 40, start.view]);
  assert.deepEqual(groupPreview({ ...group, frame_index: 9 }).objects, [], "a frame that is gone shows nothing");
});
