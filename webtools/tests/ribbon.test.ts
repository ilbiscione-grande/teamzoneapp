import assert from "node:assert/strict";
import test from "node:test";
import { arrowHeads, band, bandSizes, edgeFor, shortened, stripes } from "../lib/tactics/ribbon.ts";

test("a pass is a band that ends in its arrowhead's tip", () => {
  const outline = band([0, 0, 20, 0], 0.3, "end");
  const xs = outline.filter((_, index) => index % 2 === 0);
  const ys = outline.filter((_, index) => index % 2 === 1);
  assert.equal(Math.max(...xs), 20);
  assert.ok(Math.abs(Math.max(...ys) - bandSizes(0.3).headWidth / 2) < 1e-9);
  // Narrow where it starts.
  assert.ok(Math.abs(ys[0]) < bandSizes(0.3).body / 2);
});

test("a short pass keeps a head smaller than the line", () => {
  const outline = band([0, 0, 2, 0], 0.3, "end");
  assert.ok(outline.length >= 6);
  assert.ok(Math.min(...outline.filter((_, index) => index % 2 === 0)) >= 0);
});

test("a run's stroke stops short of its heads, which point both ways", () => {
  const line = shortened([0, 0, 20, 0], 0.3, "both");
  assert.ok(line[0] > 0 && line[line.length - 2] < 20);
  const heads = arrowHeads([0, 0, 20, 0], 0.3, true);
  assert.equal(heads.length, 2);
  assert.equal(heads[0][2], 20);
  assert.equal(heads[1][2], 0);
});

test("stripes cover the whole box", () => {
  const lines = stripes(10, 6, 1.6);
  const starts = lines.map(line => line[0]);
  assert.ok(Math.min(...starts) <= -5 - 4 && Math.max(...lines.map(line => line[2])) >= 5 + 4);
});

test("edges show against the colour", () => {
  assert.match(edgeFor("#ffffff"), /11,17,28/);
  assert.match(edgeFor("#1d4ed8"), /255,255,255/);
});
