import assert from "node:assert/strict";
import { test } from "node:test";
import { createObject, createPlayer, newDocument } from "../lib/tactics/document.ts";
import { applyFrameEdit, applyGroupEdits, boardEdits, mergeGroupEdits, splitEdit, EDITS_PER_CALL } from "../lib/tactics/live-group-edits.ts";
import { groupBoard } from "../lib/tactics/live-groups.ts";
import type { Board } from "../lib/tactics/model.ts";

function start(): { board: Board; player: ReturnType<typeof createPlayer> } {
  const board = newDocument("Tavla 1").boards[0];
  const player = createPlayer({ x: 10, y: 10 }, "home", []);
  return { board: { ...board, frames: [{ ...board.frames[0], objects: [player] }, { ...board.frames[0], objects: [player] }] }, player };
}

test("group edits: changed in place, new ones last, removed ones gone, per frame", () => {
  const { board, player } = start();
  const cone = createObject("cone", { x: 50, y: 30 });
  const edited = applyGroupEdits(board, { 0: { [player.id]: { ...player, x: 20 }, [cone.id]: cone }, 1: { [player.id]: null }, 9: { [cone.id]: cone } });
  assert.deepEqual(edited.frames[0].objects.map(item => [item.type, item.x]), [["player", 20], ["cone", 50]]);
  assert.deepEqual(edited.frames[1].objects, []);
  assert.equal(board.frames[0].objects[0].x, 10, "the starting board is untouched");
});

test("group edits: a later move stands over the edit", () => {
  const { board, player } = start();
  const stood = groupBoard(board, { 0: { [player.id]: { x: 40, y: 41 } } }, { 0: { [player.id]: { ...player, x: 20, number: 9 } } });
  const moved = stood.frames[0].objects[0];
  assert.deepEqual([moved.x, moved.y, moved.type === "player" && moved.number], [40, 41, 9]);
});

test("group edits: what changed between two boards is what is sent", () => {
  const { board, player } = start();
  assert.deepEqual(boardEdits(board, board), []);
  const cone = createObject("cone", { x: 50, y: 30 });
  const after = { ...board, frames: [{ ...board.frames[0], objects: [{ ...player, x: 30 }, cone] }, { ...board.frames[1], objects: [] }] };
  assert.deepEqual(boardEdits(board, after), [
    { frameIndex: 0, objects: { [player.id]: { ...player, x: 30 }, [cone.id]: cone }, removed: [] },
    { frameIndex: 1, objects: {}, removed: [player.id] },
  ]);
  // And applied elsewhere, the same board comes out.
  let document = { ...newDocument("x"), boards: [board] };
  for (const edit of boardEdits(board, after)) document = applyFrameEdit(document, board.id, edit);
  assert.deepEqual(document.boards[0].frames.map(frame => frame.objects.map(item => item.x)), [[30, 50], []]);
});

test("group edits: big changes go in several calls; merging keeps the latest", () => {
  const objects = Object.fromEntries(Array.from({ length: EDITS_PER_CALL + 5 }, (_, index) => {
    const cone = createObject("cone", { x: index, y: 1 });
    return [cone.id, cone];
  }));
  const parts = splitEdit({ frameIndex: 2, objects, removed: ["gone"] });
  assert.deepEqual(parts.map(part => [part.frameIndex, Object.keys(part.objects).length, part.removed.length]), [[2, EDITS_PER_CALL, 0], [2, 5, 1]]);
  const cone = createObject("cone", { x: 1, y: 1 });
  const merged = mergeGroupEdits(mergeGroupEdits({}, { frameIndex: 0, objects: { [cone.id]: cone }, removed: [] }), { frameIndex: 0, objects: {}, removed: [cone.id] });
  assert.deepEqual(merged, { 0: { [cone.id]: null } });
});
