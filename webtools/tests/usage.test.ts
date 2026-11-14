import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { pagePattern } from "../lib/usage.ts";

// Support's statistics count pages by pattern, never by an address with
// ids, tokens or codes in it.
test("a page is counted by its pattern", () => {
  assert.equal(pagePattern("/"), "/");
  assert.equal(pagePattern("/tacticsboard"), "/tacticsboard");
  assert.equal(pagePattern("/tacticsboard/"), "/tacticsboard");
  assert.equal(pagePattern("/tacticsboard/bibliotek"), "/tacticsboard/bibliotek");
  assert.equal(pagePattern("/tacticsboard/3f1c2d4e-0000-4000-8000-000000000000"), "/tacticsboard/[id]");
  assert.equal(pagePattern("/tacticsboard/mapp/abc?x=1"), "/tacticsboard/mapp/[id]");
  assert.equal(pagePattern("/delad/0123456789abcdef"), "/delad/[token]");
  assert.equal(pagePattern("/live/ABC234"), "/live/[code]");
  assert.equal(pagePattern("/nagot/annat/helt"), "other");
});

test("every pattern passes the server's check", () => {
  const routes = readFileSync(new URL("../lib/usage.ts", import.meta.url), "utf8").match(/"\/[^"]*"/g) ?? [];
  assert.ok(routes.length > 15);
  for (const route of routes) assert.match(route.slice(1, -1), /^[a-z0-9._/\[\]-]{1,100}$/);
});

test("the tracker is in the layout and skips live-lesson guests", () => {
  const layout = readFileSync(new URL("../app/layout.tsx", import.meta.url), "utf8");
  assert.match(layout, /<UsageTracker \/>/);
  const tracker = readFileSync(new URL("../components/usage-tracker.tsx", import.meta.url), "utf8");
  assert.match(tracker, /!session\.user\.is_anonymous/);
  assert.match(tracker, /visibilityState === "visible"/);
});
