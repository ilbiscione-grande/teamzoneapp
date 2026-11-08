import assert from "node:assert/strict";
import { test } from "node:test";
import { fitView, textTurn, viewRect } from "../lib/tactics/geometry.ts";
import { createObject } from "../lib/tactics/document.ts";

/** How a text lies on a screen: its turn on the pitch plus the pitch's turn on that screen. */
const onScreen = (turn: number, view: "full" | "attack", width: number, height: number) =>
  ((turn + fitView(viewRect(view), width, height).rotation) % 360 + 360) % 360;

test("a text on the pitch turns with the pitch", () => {
  const text = { rotation: 90, onPitch: true };
  assert.equal(textTurn(text, { view: "full" }), 90);
  assert.equal(textTurn(text, { view: "attack" }), 90);
});

test("a new text is on the pitch", () => {
  const text = createObject("text", { x: 10, y: 10 });
  assert.equal(text.type === "text" && text.onPitch, true);
});

test("an old text reads upright on a wide screen, where it was most likely written, and turns with the pitch elsewhere", () => {
  // Half a pitch is tall: a wide screen turns it, a phone does not.
  const old = { rotation: 0 };
  const turn = textTurn(old, { view: "attack" });
  assert.equal(onScreen(turn, "attack", 1600, 900), 0, "upright on the wide screen");
  assert.equal(onScreen(turn, "attack", 400, 800), 90, "turned with the pitch on a phone");
  // A whole pitch is wide: not turned on a wide screen, so an old text stays as it was.
  assert.equal(textTurn(old, { view: "full" }), 0);
});
