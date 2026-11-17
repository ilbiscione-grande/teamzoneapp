import assert from "node:assert/strict";
import { test } from "node:test";
import { createPlayer, newDocument } from "../lib/tactics/document.ts";
import { deadlineFrom, groupBoard, groupCounts, groupError, groupPreview, groupSolution, groupTopic, mergeGroupMoves, strokesAsFreehand, timeLeft } from "../lib/tactics/live-groups.ts";

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
  const group = { id: "g", number: 1, board_id: start.id, frame_index: 1, members: [], board: start, moves: { 1: { [player.id]: { x: 40, y: 30 } } }, edits: {}, strokes: [], messages: [], ends_in: null };
  const preview = groupPreview(group);
  assert.deepEqual([preview.objects.length, preview.objects[0].x, preview.view], [1, 40, start.view]);
  assert.deepEqual(groupPreview({ ...group, frame_index: 9 }).objects, [], "a frame that is gone shows nothing");
});

const stroke = (points: number[]) => ({ id: "s", board_id: "b", profile_id: "p", name: "Mats", color: "#ff0000", points, created_at: "" });

test("live groups: strokes become freehand lines placed at their first point", () => {
  const [line] = strokesAsFreehand([stroke([10, 20, 15, 22, 18, 30]), stroke([1, 1])]);
  assert.deepEqual([line.type, line.x, line.y, line.points, line.color, line.arrow], ["freehand", 10, 20, [0, 0, 5, 2, 8, 10], "#ff0000", "none"]);
  assert.equal(strokesAsFreehand([stroke([1, 1])]).length, 0, "a dot is not a line");
});

test("live groups: a group's solution is a new board with the moves and the drawing on its frame", () => {
  const board = newDocument("Tavla 1").boards[0];
  const player = createPlayer({ x: 10, y: 10 }, "home", []);
  const start = { ...board, frames: [{ ...board.frames[0], objects: [player] }, { ...board.frames[0], objects: [player] }] };
  const group = { id: "g", number: 2, board_id: start.id, frame_index: 1, members: [], board: start, moves: { 1: { [player.id]: { x: 40, y: 30 } } },
    edits: {}, strokes: [stroke([5, 5, 9, 9])], messages: [], ends_in: null };
  const saved = groupSolution(group, "Tavla 1 – grupp 2");
  assert.notEqual(saved.id, start.id);
  assert.equal(saved.name, "Tavla 1 – grupp 2");
  assert.deepEqual(saved.frames[1].objects.map(item => [item.type, item.x]), [["player", 40], ["freehand", 5]]);
  assert.deepEqual(saved.frames[0].objects.map(item => [item.type, item.x]), [["player", 10]], "other frames as they were");
});

test("live groups: the time left counts down to 0:00", () => {
  assert.equal(deadlineFrom(null), null);
  assert.equal(deadlineFrom(90, 1000), 91000);
  assert.equal(timeLeft(91000, 1000), "1:30");
  assert.equal(timeLeft(91000, 90500), "0:01");
  assert.equal(timeLeft(1000, 5000), "0:00");
});
