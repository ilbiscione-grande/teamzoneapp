import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { validWorkerBearer } from "../lib/worker-auth.ts";

const root = new URL("../../", import.meta.url);
const sql = readFileSync(new URL("supabase/migrations/20260827141825_pub06_web_quality_cache_seo.sql", root), "utf8");
const proxy = readFileSync(new URL("public-site/proxy.ts", root), "utf8");
const config = readFileSync(new URL("public-site/next.config.ts", root), "utf8");
const smoke = readFileSync(new URL("public-site/scripts/synthetic-smoke.mjs", root), "utf8");

test("published HTML is bounded while APIs remain no-store", () => {
  assert.match(proxy, /s-maxage=60, must-revalidate/);
  assert.doesNotMatch(proxy, /stale-while-revalidate/);
  assert.match(config, /source: "\/api\/:path\*"[\s\S]*"no-store"/);
  assert.match(sql, /invalidation_worker_timeout/);
  assert.match(sql, /finish_publication_invalidation/);
  assert.match(proxy, /"\/media\/public\/"/);
});

test("invalidation worker bearer comparison is strict", () => {
  const secret = "a".repeat(32);
  assert.equal(validWorkerBearer(`Bearer ${secret}`, secret), true);
  assert.equal(validWorkerBearer(`Bearer ${"b".repeat(32)}`, secret), false);
  assert.equal(validWorkerBearer(null, secret), false);
  assert.equal(validWorkerBearer("Bearer short", "short"), false);
});

test("SEO, security and synthetic smoke are explicit", () => {
  assert.match(config, /Strict-Transport-Security/);
  assert.match(config, /Content-Security-Policy/);
  assert.match(smoke, /robots\.txt/);
  assert.match(smoke, /sitemap\.xml/);
  assert.match(smoke, /service_role\|SUPABASE_/);
  assert.match(sql, /public_sitemap_entries/);
});

test("live match reporting is not introduced", () => {
  const sources = `${sql}\n${proxy}\n${smoke}`;
  assert.doesNotMatch(sources, /live_match|match_clock|score_event|realtime_channel/i);
});
