import assert from "node:assert/strict";
import { test } from "node:test";
import { PITCH_LENGTH as L, PITCH_WIDTH as W } from "../lib/tactics/model.ts";
import { wavePoints } from "../lib/tactics/path.ts";
import { inkFor, lookOf, patternLabels, patternPieces, styleOf, themes, type PitchPattern } from "../lib/tactics/pitch-style.ts";

test("a board without a style, or with an unknown one, has grass in stripes", () => {
  assert.deepEqual(styleOf(undefined), { theme: "grass", pattern: "stripes" });
  assert.deepEqual(styleOf({ theme: "moon" as never, pattern: "checks" }), { theme: "grass", pattern: "checks" });
  assert.equal(lookOf(null), themes.grass);
});

test("white drawing turns to the theme's ink on a light pitch only; other colours stay", () => {
  assert.equal(inkFor("#ffffff", themes.whiteboard), themes.whiteboard.ink);
  assert.equal(inkFor("#FFF", themes.whiteboard), themes.whiteboard.ink);
  assert.equal(inkFor("#ef4444", themes.whiteboard), "#ef4444");
  assert.equal(inkFor("#ffffff", themes.grass), "#ffffff");
});

test("every pattern but plain lays pieces, and the mown ones stay on the pitch", () => {
  for (const pattern of Object.keys(patternLabels) as PitchPattern[]) {
    const pieces = patternPieces(pattern, L, W);
    assert.equal(pieces.length === 0, pattern === "plain", pattern);
    for (const piece of pieces) {
      if (piece.kind !== "rect") continue;
      assert.ok(piece.x >= 0 && piece.y >= 0 && piece.x + piece.width <= L + 1e-9 && piece.y + piece.height <= W + 1e-9, pattern);
    }
  }
  // Checks: half the squares lighter.
  assert.equal(patternPieces("checks", L, W).length, 48);
});

test("a dribble swings to both sides of its way, starts and ends on it, and runs straight at the end", () => {
  const wave = wavePoints([0, 0, 20, 0]);
  const ys = wave.filter((_, i) => i % 2 === 1);
  assert.ok(Math.max(...ys) > 0.3 && Math.min(...ys) < -0.3, "both sides");
  assert.deepEqual(wave.slice(0, 2), [0, 0]);
  assert.deepEqual(wave.slice(-2), [20, 0]);
  // The last metre is straight, so an arrowhead points along the way.
  const tail = wave.filter((_, i) => i % 2 === 0 ? false : wave[i - 1] > 19);
  assert.ok(tail.every(y => Math.abs(y) < 1e-9));
  assert.deepEqual(wavePoints([0, 0, 1, 0]), [0, 0, 1, 0], "too short to swing");
});

test("an arena or a training ground shows more round the pitch; a project keeps its logo through loading", async () => {
  const { marginFor, viewRect, MARGIN } = await import("../lib/tactics/geometry.ts");
  const { normalizeDocument, newDocument } = await import("../lib/tactics/document.ts");
  assert.equal(marginFor(undefined), MARGIN);
  assert.ok(marginFor("arena") > marginFor("training") && marginFor("training") > MARGIN);
  assert.equal(viewRect("full", marginFor("arena")).x, -marginFor("arena"));
  const branding = { logo: "data:image/png;base64,AAAA", place: "centre" as const };
  assert.deepEqual(normalizeDocument({ ...newDocument(), branding }).branding, branding);
  assert.equal(normalizeDocument(newDocument()).branding, undefined);
});
