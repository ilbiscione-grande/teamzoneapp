import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { normalizedHostname, requestHostname, safeDomainDecision, validRoutingInput } from "../lib/domain-routing.ts";

const root = new URL("../../", import.meta.url);
const sql = readFileSync(new URL("supabase/migrations/20260827135707_pub05_automated_domain_routing.sql", root), "utf8");
const proxy = readFileSync(new URL("public-site/proxy.ts", root), "utf8");
const pageData = readFileSync(new URL("public-site/lib/page-data.ts", root), "utf8");

test("custom domain ownership, TLS and canonical changes are separate gates", () => {
  assert.match(sql, /verification_token_hash/);
  assert.match(sql, /commercial_state/);
  assert.match(sql, /new_state='active'.*new_tls_state<>'ready'/s);
  assert.match(sql, /publication_domains_one_canonical_idx/);
  assert.match(sql, /'status',308/);
  assert.match(sql, /observed_verification_token is null/);
  assert.match(sql, /state='active' and commercial_state='approved'/);
});

test("wildcard subdomains remain structurally disabled", () => {
  assert.match(sql, /wildcard_dns_ready boolean not null default false check\(wildcard_dns_ready=false\)/);
  assert.match(sql, /wildcard_tls_ready boolean not null default false check\(wildcard_tls_ready=false\)/);
  assert.match(sql, /automatic_tenant_routing_ready boolean not null default false check\(automatic_tenant_routing_ready=false\)/);
  assert.match(sql, /wildcard_domains_not_ready/);
});

test("hostname routing rejects unsafe input and unsafe decisions", () => {
  assert.equal(normalizedHostname(" Club.Example.SE.:443 "), "club.example.se");
  assert.equal(validRoutingInput("club.example.se", "/nyheter"), true);
  assert.equal(validRoutingInput("bad host", "/nyheter"), false);
  assert.deepEqual(safeDomainDecision({ mode: "redirect", status: 308, location: "http://bad.example" }), { mode: "not_found", not_found: true });
  assert.equal(safeDomainDecision({ mode: "redirect", status: 308, location: "https://club.example.se/" }).mode, "redirect");
  assert.match(proxy, /x-teamzone-canonical-origin/);
  assert.match(pageData, /url\.protocol !== "https:"/);
});

test("requestHostname prefers the trusted edge's forwarded host over the framework and Host header", () => {
  // 2026-09-05 regression: behind Firebase App Hosting's edge, the
  // framework-reported request URL hostname is the container's own bind
  // address (e.g. "0.0.0.0"), and the Host header is rewritten to the
  // internal Cloud Run service hostname rather than the hostname the
  // visitor actually requested. Only X-Forwarded-Host, set by the single
  // trusted edge hop, carries the real value.
  const headers = (values: Record<string, string>) => ({ get: (name: string) => values[name.toLowerCase()] ?? null });
  assert.equal(
    requestHostname(headers({ "x-forwarded-host": "public.teamzoneapp.se", host: "teamzoneapp-public--x.run.app" }), "0.0.0.0"),
    "public.teamzoneapp.se",
  );
  assert.equal(requestHostname(headers({ "x-forwarded-host": "Club.Example.SE, other.example" }), "0.0.0.0"), "club.example.se");
  assert.equal(requestHostname(headers({ host: "club.example.se" }), "0.0.0.0"), "club.example.se");
  assert.equal(requestHostname(headers({}), "localhost"), "localhost");
  assert.match(proxy, /requestHostname\(request\.headers/, "proxy.ts must resolve hostname via requestHostname(request.headers, ...)");
});

test("secondary TeamZone origins send pages to teamzoneapp.se", async () => {
  const { canonicalOriginRedirect } = await import("../lib/domain-routing.ts");
  const base = { publicOrigin: "https://teamzoneapp.se", siteOrigins: "https://public.teamzoneapp.se", method: "GET", search: "" };
  assert.equal(canonicalOriginRedirect({ ...base, hostname: "public.teamzoneapp.se", path: "/" }), "https://teamzoneapp.se/");
  assert.equal(canonicalOriginRedirect({ ...base, hostname: "PUBLIC.teamzoneapp.se:443", path: "/anmalan/abc", search: "?x=1" }),
    "https://teamzoneapp.se/anmalan/abc?x=1");
  // The canonical address itself, club domains and unknown hosts stay.
  assert.equal(canonicalOriginRedirect({ ...base, hostname: "teamzoneapp.se", path: "/" }), null);
  assert.equal(canonicalOriginRedirect({ ...base, hostname: "www.minklubb.se", path: "/" }), null);
  // API calls, assets, media and form posts are never redirected.
  for (const path of ["/api/public/v1/intake", "/_next/static/x.js", "/media/public/abc"]) {
    assert.equal(canonicalOriginRedirect({ ...base, hostname: "public.teamzoneapp.se", path }), null, path);
  }
  assert.equal(canonicalOriginRedirect({ ...base, hostname: "public.teamzoneapp.se", path: "/", method: "POST" }), null);
  // Without configuration nothing is redirected.
  assert.equal(canonicalOriginRedirect({ ...base, siteOrigins: undefined, hostname: "public.teamzoneapp.se", path: "/" }), null);
});
