import assert from "node:assert/strict";
import test from "node:test";
import { createObject, newBoard, newFrame } from "../lib/tactics/document.ts";
import { drills } from "../lib/tactics/drills.ts";
import { copiesOf, oneGroup, setGroup, withGroups } from "../lib/tactics/grouping.ts";
import type { Board, TacticsObject } from "../lib/tactics/model.ts";
import { blockFromBoard, blocksWithBoard, hasBoard, type TrainingSession } from "../lib/tactics/training-link.ts";

const cones = (): TacticsObject[] => ["a", "b", "c", "d"].map(id => ({ ...createObject("cone", { x: 0, y: 0 }), id }));

test("one of a group chooses the whole group", () => {
  const board = setGroup({ ...newBoard("T"), frames: [newFrame(cones()), newFrame(cones())] }, ["a", "b"], "g1");
  const objects = board.frames[0].objects;
  assert.deepEqual(withGroups(objects, ["a"]).sort(), ["a", "b"]);
  assert.deepEqual(withGroups(objects, ["c"]), ["c"]);
  assert.equal(oneGroup(objects, ["a", "b"]), true);
  assert.equal(oneGroup(objects, ["a", "c"]), false);
  // The group holds in every frame.
  assert.deepEqual(board.frames[1].objects.filter(item => item.group === "g1").map(item => item.id), ["a", "b"]);
  const parted = setGroup(board, ["a", "b"], null);
  assert.equal(parted.frames[0].objects.some(item => item.group), false);
});

test("copies of a group make a group of their own", () => {
  const objects = cones().map(item => (item.id === "a" || item.id === "b" ? { ...item, group: "g1", locked: true } : item));
  const copies = copiesOf(objects, ["a", "b", "c"]);
  assert.equal(copies.length, 3);
  assert.equal(copies.every(item => !item.locked && !["a", "b", "c"].includes(item.id)), true);
  assert.ok(copies[0].group && copies[0].group !== "g1");
  assert.equal(copies[0].group, copies[1].group);
  assert.equal(copies[2].group, undefined);
});

test("every drill lays out objects with ids of their own each time", () => {
  for (const drill of drills) {
    const first = drill.objects(), second = drill.objects();
    assert.ok(first.length > 0, drill.key);
    assert.equal(new Set(first.map(item => item.id)).size, first.length, drill.key);
    assert.equal(first.some(item => second.some(other => other.id === item.id)), false, drill.key);
  }
});

test("a board goes last in a training session, linked, the exercises there kept", () => {
  const board: Board = {
    ...newBoard("Rondo"), description: "Ruta 12 x 12",
    exercise: { part: "main", minutes: 15, players: 6, area: "", coachingPoints: "Vinkla dig", phase: "build_up", ageClasses: [], gameForms: [] },
  };
  const block = blockFromBoard(board, "project-1");
  assert.equal(block.title, "Rondo");
  assert.equal(block.minutes, 15);
  assert.equal(block.organisation, "Ruta 12 x 12");
  assert.equal(block.coaching_points, "Vinkla dig");
  assert.deepEqual(block.board, { source: "mine", ref: "project-1", board_id: board.id, name: "Rondo" });
  const session: TrainingSession = {
    event_id: "e", revision: 3, published: false, theme: "", goal: "",
    blocks: [{ part: "warmup", title: "Uppvärmning", minutes: 10, organisation: "", coaching_points: "", phase: null, source_kind: "own", source_id: null,
      players: [{ roster_id: "p1", person_id: "p1", team: "blue", name: "Anna" }], board: null }],
  };
  const blocks = blocksWithBoard(session, block);
  assert.equal(blocks.length, 2);
  assert.deepEqual(blocks[0].players, session.blocks[0].players);
  assert.equal(blocks[1].title, "Rondo");
  assert.equal(hasBoard({ ...session, blocks }, "project-1", board.id), true);
  assert.equal(hasBoard(session, "project-1", board.id), false);
});
