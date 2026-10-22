import assert from "node:assert/strict";
import { test } from "node:test";
import { createPlayer, newDocument, newBoard } from "../lib/tactics/document.ts";
import { applyBoard, applyMoves, joinError, liveLink, liveTopic, normalizeCode, throttle, viewChanged, type LiveView } from "../lib/tactics/live.ts";

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

test("live: objects dragged by the host move on the participant's board", () => {
  const document = newDocument("Tavla 1");
  const board = document.boards[0];
  const player = createPlayer({ x: 10, y: 10 }, "home", []);
  const withPlayer = { ...document, boards: [{ ...board, frames: [{ ...board.frames[0], objects: [player] }] }] };
  const moved = applyMoves(withPlayer, { boardId: board.id, frameIndex: 0, moves: { [player.id]: { x: 20, y: 15 } } });
  const after = moved.boards[0].frames[0].objects[0];
  assert.deepEqual([after.x, after.y], [20, 15]);
  assert.equal(applyMoves(withPlayer, { boardId: "other", frameIndex: 0, moves: { [player.id]: { x: 1, y: 1 } } }).boards[0].frames[0].objects[0].x, 10);
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

test("live chat: messages once and in order, refusals in words, hands in turn", async () => {
  const { chatError, mergeMessages, raisedHands } = await import("../lib/tactics/live-chat.ts");
  const message = (id: string, at: string) => ({ id, profile_id: "p", name: "Mats", from_host: false, to_host: false, body: id, created_at: at });
  const list = mergeMessages([message("b", "2026-10-22T10:01:00Z")], [message("a", "2026-10-22T10:00:00Z"), message("b", "2026-10-22T10:01:00Z")]);
  assert.deepEqual(list.map(item => item.id), ["a", "b"], "the echo of a sent message is not a second one");
  const many = mergeMessages([], Array.from({ length: 205 }, (_, i) => message(`m${i}`, new Date(Date.UTC(2026, 9, 22, 10, 0, i)).toISOString())));
  assert.deepEqual([many.length, many[0].id], [200, "m5"]);
  assert.match(chatError("ERROR: muted"), /för dig/);
  assert.match(chatError("too_fast"), /Vänta/);
  assert.deepEqual(raisedHands([{ n: 1, hand: 30 }, { n: 2, hand: null }, { n: 3, hand: 10 }]).map(person => person.n), [3, 1]);
});
