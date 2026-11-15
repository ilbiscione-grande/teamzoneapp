import assert from "node:assert/strict";
import { test } from "node:test";
import { createPlayer, newBoard, newFrame } from "../lib/tactics/document.ts";
import { PICTURE_MAX_BYTES, pictureData, pictureKey, pictureSize } from "../lib/tactics/board-picture.ts";

test("a board's picture is drawn again only when its first frame or its look changes", () => {
  const player = createPlayer({ x: 10, y: 10 }, "home", []);
  const board = { ...newBoard("Tavla"), frames: [newFrame([player]), newFrame([{ ...player, x: 40 }])] };
  const key = pictureKey(board, undefined);
  assert.equal(pictureKey({ ...board, name: "Nytt namn", description: "Mer text" }, undefined), key, "the name and text are not in it");
  assert.equal(pictureKey({ ...board, frames: [board.frames[0], newFrame([])] }, undefined), key, "later frames are not in it");
  assert.notEqual(pictureKey({ ...board, frames: [newFrame([{ ...player, x: 12 }]), board.frames[1]] }, undefined), key);
  assert.notEqual(pictureKey({ ...board, view: "attack" }, undefined), key);
  assert.notEqual(pictureKey(board, { logo: "data:image/png;base64,AA", place: "corner" }), key);
});

test("a picture goes to the server as its type and base64, landscape or at the crop's shape, and not when too large", () => {
  assert.deepEqual(pictureData("data:image/webp;base64,UklGR"), { media_type: "image/webp", data: "UklGR" });
  assert.deepEqual(pictureData("data:image/png;base64,iVBOR"), { media_type: "image/png", data: "iVBOR" });
  assert.equal(pictureData("data:image/jpeg;base64,/9j/"), null, "the server takes WebP or PNG");
  assert.equal(pictureData(`data:image/webp;base64,${"A".repeat(Math.ceil((PICTURE_MAX_BYTES * 4) / 3) + 4)}`), null);
  assert.deepEqual(pictureSize({ crop: null }, 640), { width: 640, height: 427 });
  assert.deepEqual(pictureSize({ crop: { x: 0, y: 0, width: 30, height: 60 } }, 640), { width: 320, height: 640 });
});
