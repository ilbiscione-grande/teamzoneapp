import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { normalizedHostname, safeDomainDecision, validRoutingInput } from "../lib/domain-routing.ts";

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
