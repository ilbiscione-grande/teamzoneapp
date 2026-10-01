import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { clubThemeCss, clubThemeHref, normalizeColor } from "../lib/club-theme.ts";

const route = readFileSync(new URL("../app/api/public/v1/club-theme/route.ts", import.meta.url), "utf8");
const clubPage = readFileSync(new URL("../app/[clubSlug]/page.tsx", import.meta.url), "utf8");

test("only plain hex colours are accepted", () => {
  assert.equal(normalizeColor("#0A3D2A"), "0a3d2a");
  assert.equal(normalizeColor("ffd100"), "ffd100");
  assert.equal(normalizeColor("red"), null);
  assert.equal(normalizeColor("#000000;}body{x:y"), null);
  assert.equal(clubThemeHref(null, undefined), null);
  assert.equal(clubThemeHref("#0A3D2A", "#FFD100"), "/api/public/v1/club-theme?p=0a3d2a&a=ffd100");
  assert.equal(clubThemeCss("}{", "x"), null);
});

test("theme keeps dark surfaces and readable accents", () => {
  const css = clubThemeCss("#7ec8ff", "#ffffff")!;
  assert.match(css, /^\.cs\.cs-theme\{/);
  // A light sky blue becomes a dark surface.
  const ink = /--cs-ink:#([0-9a-f]{6})/.exec(css)![1];
  assert.ok(Number.parseInt(ink.slice(0, 2), 16) < 90, ink);
  // White accent: dark text on accent fills.
  assert.match(css, /--cs-accent-ink:#0b111c/);
  // A dark accent on a dark surface falls back to white text.
  assert.match(clubThemeCss("#101010", "#202020")!, /--cs-accent-text:#ffffff/);
  assert.doesNotMatch(css, /[<>"']/);
});

test("the theme is a same-origin stylesheet, not inline style", () => {
  assert.match(route, /text\/css/);
  assert.match(route, /clubThemeCss/);
  assert.match(clubPage, /<ClubTheme club=\{club\} \/>/);
  assert.doesNotMatch(clubPage, /style=\{/);
});
