import assert from "node:assert/strict";
import { test } from "node:test";
import { newDocument, newBoard } from "../lib/tactics/document.ts";
import { applyBoard, joinError, liveLink, liveTopic, normalizeCode, throttle, viewChanged, type LiveView } from "../lib/tactics/live.ts";

test("live: codes, links and topics", () => {
  assert.equal(normalizeCode(" k7p-2qx "), "K7P2QX");
  assert.equal(normalizeCode("K7P2Q"), null, "too short");
  assert.equal(normalizeCode("K7P2Q0"), null, "0 is not used");
  assert.equal(liveLink("https://x.se", "K7P2QX"), "https://x.se/live/K7P2QX");
  assert.equal(liveTopic("abc"), "tactics-live:abc");
  assert.match(joinError("ERROR: login_required"), /inloggning/);
  assert.match(joinError("not_found"), /ingen pågående/i);
});

test("live: a board from the host replaces the participant's, or is added", () => {
  const document = newDocument("Tavla 1");
  const changed = { ...document.boards[0], name: "Ändrad" };
  const replaced = applyBoard(document, changed);
  assert.deepEqual(replaced.boards.map(board => board.name), ["Ändrad"]);
  const added = applyBoard(document, newBoard("Ny"));
  assert.deepEqual(added.boards.map(board => board.name), ["Tavla 1", "Ny"]);
  assert.equal(document.boards[0].name, "Tavla 1", "the old document is untouched");
});

test("live: what is worth sending of the host's view", () => {
  const view: LiveView = { boardId: "b", frameIndex: 0, playhead: 0, playing: false, speed: 1, loop: false };
  assert.equal(viewChanged(null, view), true);
  assert.equal(viewChanged(view, { ...view }), false);
  assert.equal(viewChanged(view, { ...view, playhead: 0.4 }), true, "scrubbed");
  const playing = { ...view, playing: true };
  assert.equal(viewChanged(view, playing), true);
  assert.equal(viewChanged(playing, { ...playing, playhead: 1.3, frameIndex: 1 }), false, "played on locally");
  assert.equal(viewChanged(playing, { ...playing, boardId: "c" }), true);
});

test("live: throttle sends at once, then the last call at the end", async () => {
  const sent: number[] = [];
  const throttled = throttle((value: number) => sent.push(value), 40);
  throttled.call(1);
  throttled.call(2);
  throttled.call(3);
  assert.deepEqual(sent, [1]);
  await new Promise(resolve => setTimeout(resolve, 60));
  assert.deepEqual(sent, [1, 3]);
  throttled.call(4);
  throttled.cancel();
  await new Promise(resolve => setTimeout(resolve, 60));
  assert.ok(sent.length <= 3);
});
