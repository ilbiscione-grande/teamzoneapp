import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { appFor, pagePattern, recordAppActivity } from "../lib/usage.ts";

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

test("a page counts as Tacticsboard or Webtools in TeamZone's apps", () => {
  assert.equal(appFor("/tacticsboard"), "tacticsboard");
  assert.equal(appFor("/tacticsboard/[id]"), "tacticsboard");
  assert.equal(appFor("/live/[code]"), "tacticsboard");
  assert.equal(appFor("/delad/[token]"), "tacticsboard");
  assert.equal(appFor("/support/tacticsboard"), "tacticsboard");
  assert.equal(appFor("/bokningar/[org]"), "webtools");
  assert.equal(appFor("/turneringar"), "webtools");
  assert.equal(appFor("/"), "webtools");
  assert.equal(appFor("/tacticsboardx"), "webtools");
});

test("an app's active day is sent once a day", () => {
  const calls: unknown[] = [];
  const client = { schema: () => ({ rpc: (name: string, args: unknown) => { calls.push([name, args]); return Promise.resolve({}); } }) };
  const day = new Date("2026-11-15T10:00:00Z");
  assert.equal(recordAppActivity(client as never, "webtools", day), true);
  assert.equal(recordAppActivity(client as never, "webtools", day), false);
  assert.equal(recordAppActivity(client as never, "tacticsboard", day), true);
  assert.equal(recordAppActivity(client as never, "webtools", new Date("2026-11-16T10:00:00Z")), true);
  assert.deepEqual(calls[0], ["record_app_activity", { app: "webtools" }]);
  assert.equal(calls.length, 3);
});

test("every Webtools site sends the app day with the page", () => {
  const tracker = readFileSync(new URL("../components/usage-tracker.tsx", import.meta.url), "utf8");
  assert.ok(tracker.includes("    recordAppActivity(client, appFor(pattern));"));
  assert.ok(!tracker.includes("tacticsboardOnly"));
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
