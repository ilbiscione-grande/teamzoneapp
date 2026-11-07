import assert from "node:assert/strict";
import { test } from "node:test";
import { useEditor } from "../components/tactics/store.ts";
import { createObject, createPlayer, insertFrame, newBoard, newDocument, newFrame, toggleEffect } from "../lib/tactics/document.ts";
import { effectsLast, hasEffectEveryFrame, patchEveryFrame, setEffectEveryFrame, setLastingEffects } from "../lib/tactics/every-frame.ts";
import { cameraAt } from "../lib/tactics/marks.ts";
import type { Board, Effect, Project, TacticsObject } from "../lib/tactics/model.ts";
import { effectsOf } from "../lib/tactics/motion.ts";

const player = createPlayer({ x: 10, y: 10 }, "home", []);
const cone = createObject("cone", { x: 20, y: 20 });

/** A board of frames holding the given objects. */
const boardOf = (...frames: TacticsObject[][]): Board => ({ ...newBoard("Tavla"), frames: frames.map(objects => newFrame(objects)) });

function load(board: Board) {
  const document = { ...newDocument(), boards: [board] };
  useEditor.getState().load({ id: "p", name: "P", kind: "match", teamzone_team_id: null, team_name: null, revision: 1 } as Project, document);
}
const colorOf = (board: Board, frame: number, id: string) => (board.frames[frame].objects.find(item => item.id === id) as { color?: string | null }).color;

test("what is chosen stays chosen on going to a frame it is in", () => {
  load(boardOf([player, cone], [player, cone], [cone]));
  const state = useEditor.getState();
  state.select([player.id, cone.id]);
  state.setFrame(1);
  assert.deepEqual(useEditor.getState().selection, [player.id, cone.id]);
  state.scrub(0);
  assert.deepEqual(useEditor.getState().selection, [player.id, cone.id], "a tap on a frame's dot");
  state.setFrame(2);
  assert.deepEqual(useEditor.getState().selection, [cone.id], "the player is not in that frame");
  state.scrub(1.5);
  assert.deepEqual(useEditor.getState().selection, [], "nothing is edited between two frames");
});

test("a colour goes for every frame only when that is chosen", () => {
  load(boardOf([player], [player], [cone]));
  const state = useEditor.getState();
  state.patchLook({ [player.id]: { color: "#111111" } });
  let board = useEditor.getState().document!.boards[0];
  assert.equal(colorOf(board, 0, player.id), "#111111");
  assert.equal(colorOf(board, 1, player.id), null, "this frame only");

  state.setAllFrames(true);
  state.patchLook({ [player.id]: { color: "#222222" } });
  board = useEditor.getState().document!.boards[0];
  assert.equal(colorOf(board, 0, player.id), "#222222");
  assert.equal(colorOf(board, 1, player.id), "#222222");
  assert.equal(colorOf(board, 2, cone.id), (cone as { color: string }).color, "others are left alone");
  useEditor.getState().undo();
  assert.equal(colorOf(useEditor.getState().document!.boards[0], 1, player.id), null, "one step to undo");
});

test("a locked copy keeps its colour", () => {
  const board = patchEveryFrame(boardOf([player], [{ ...player, locked: true }]), { [player.id]: { color: "#333333" } });
  assert.equal(colorOf(board, 0, player.id), "#333333");
  assert.equal(colorOf(board, 1, player.id), null);
});

test("an effect for every frame also goes for frames added later", () => {
  const kind: Effect = "ring";
  let board = setEffectEveryFrame(boardOf([player], [player], [cone]), [player.id], kind, true);
  assert.ok(effectsOf(board.frames[1].objects[0]).includes(kind));
  assert.ok(hasEffectEveryFrame(board, player.id, kind));
  assert.equal(effectsOf(board.frames[2].objects[0]).length, 0, "not on another object");

  board = insertFrame(board, 1);
  assert.deepEqual(effectsOf(board.frames[2].objects[0]), [kind]);

  board = setEffectEveryFrame(board, [player.id], kind, false);
  assert.equal(hasEffectEveryFrame(board, player.id, kind), false);
  assert.equal(effectsOf(insertFrame(board, 1).frames[2].objects[0]).length, 0);
});

test("an effect for one frame is not carried into a new one, and taking one away here stops it", () => {
  const single = { ...player, ...toggleEffect(player, "pulse", true) } as TacticsObject;
  assert.equal(effectsOf(insertFrame(boardOf([single]), 0).frames[1].objects[0]).length, 0);
  const lasting = setEffectEveryFrame(boardOf([player]), [player.id], "pulse", true).frames[0].objects[0];
  const taken = { ...lasting, ...toggleEffect(lasting, "pulse", false) } as TacticsObject;
  assert.equal(effectsOf(insertFrame(boardOf([taken]), 0).frames[1].objects[0]).length, 0);
});

test("all frames is chosen per object: it goes off when others are chosen", () => {
  load(boardOf([player, cone], [player, cone]));
  const state = useEditor.getState();
  state.select([player.id]);
  state.setAllFrames(true);
  state.select([player.id]);
  assert.equal(useEditor.getState().allFrames, true, "the same object");
  state.setFrame(1);
  assert.equal(useEditor.getState().allFrames, true, "another frame");
  state.select([cone.id]);
  assert.equal(useEditor.getState().allFrames, false, "another object");
});

test("one object's effects can stay out of frames added later, the others' not", () => {
  let board = setEffectEveryFrame(boardOf([player, cone], [player, cone]), [player.id, cone.id], "ring", true);
  assert.ok(effectsLast(board.frames[1].objects[0]));
  board = setLastingEffects(board, player.id, []);
  assert.equal(effectsLast(board.frames[0].objects[0]), false, "in every frame");
  const added = insertFrame(board, 1).frames[2].objects;
  assert.equal(effectsOf(added[0]).length, 0, "not on the player");
  assert.deepEqual(effectsOf(added[1]), ["ring"], "still on the cone");
  assert.ok(hasEffectEveryFrame(board, player.id, "ring"), "the frames there keep it");
  board = setLastingEffects(board, player.id, ["ring"]);
  assert.deepEqual(effectsOf(insertFrame(board, 1).frames[2].objects[0]), ["ring"], "and back on");
});

test("the zoom goes in and out at the chosen speed", () => {
  const zoomed = (speeds: Partial<TacticsObject>) => ({ ...player, effects: ["zoom"] as Effect[], ...speeds }) as TacticsObject;
  const at = (frames: Board["frames"], playhead: number) => cameraAt(frames, playhead, [])!.amount;

  const fast = boardOf([player], [zoomed({})], [player]).frames;
  assert.equal(at(fast, 0.5), 1, "in after a third of the move");
  assert.equal(at(fast, 1.5), 0, "and out as fast");

  const slow = boardOf([player], [zoomed({ zoomIn: "slow", zoomOut: "slow" })], [player]).frames;
  assert.ok(at(slow, 0.25) < 0.1, "only started");
  assert.ok(at(slow, 0.75) > 0.9, "nearly in");
  assert.ok(at(slow, 1.25) > 0.9, "only started out");
  assert.ok(at(slow, 1.75) < 0.1, "nearly out");
});
