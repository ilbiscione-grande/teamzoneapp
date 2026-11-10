import assert from "node:assert/strict";
import { test } from "node:test";
import { useEditor } from "../components/tactics/store.ts";
import { newBoard, newDocument, newFrame } from "../lib/tactics/document.ts";
import { viewChanged, type LiveView } from "../lib/tactics/live.ts";
import type { Project } from "../lib/tactics/model.ts";

function load(frames: number) {
  const board = { ...newBoard("Tavla"), frames: Array.from({ length: frames }, () => newFrame([])) };
  useEditor.getState().load({ id: "p", name: "P", kind: "match", teamzone_team_id: null, team_name: null, revision: 1 } as Project, { ...newDocument(), boards: [board] });
}

test("step by step plays one move and stops on the next frame", () => {
  load(3);
  const state = useEditor.getState();
  state.setStepwise(true);
  state.play();
  assert.equal(useEditor.getState().stopAt, 1);
  state.scrub(1.4);
  state.play();
  assert.equal(useEditor.getState().stopAt, 2, "from between two frames, to the next whole one");
  state.scrub(2);
  state.play();
  assert.equal(useEditor.getState().playhead, 0, "at the end it starts over");
  assert.equal(useEditor.getState().stopAt, 1);
  state.pause();
  state.setStepwise(false);
  state.play();
  assert.equal(useEditor.getState().stopAt, null, "otherwise it plays to the end");
  state.pause();
});

test("live: the host's step is sent, so participants stop on the same frame", () => {
  const view: LiveView = { boardId: "b", frameIndex: 0, playhead: 0, playing: true, speed: 1, loop: false, stopAt: null };
  assert.equal(viewChanged(view, { ...view, stopAt: 1 }), true);
  assert.equal(viewChanged({ ...view, stopAt: undefined }, view), false, "an older host sends none");
});
