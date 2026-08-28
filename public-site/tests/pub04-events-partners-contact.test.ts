import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const root = new URL("../../", import.meta.url);
const sql = readFileSync(new URL("supabase/migrations/20260827134457_pub04_events_partners_contact.sql", root), "utf8");
const clubPage = readFileSync(new URL("public-site/app/[clubSlug]/page.tsx", root), "utf8");
const contactRoute = readFileSync(new URL("public-site/app/api/public/v1/contact/route.ts", root), "utf8");
const contactBase = readFileSync(new URL("supabase/migrations/20260815170442_s09_public_api_contact_boundary.sql", root), "utf8");

test("events publish only explicit allowlisted fields", () => {
  assert.match(sql, /new_publish_location/);
  assert.match(sql, /published_fields/);
  assert.match(sql, /event_row\.state not in\('scheduled','completed'\)/);
  assert.doesNotMatch(sql, /event_row\.description/);
  assert.match(sql, /else delete from public_api\.event_projections/);
});

test("partners require HTTPS and a clean ready public media variant", () => {
  assert.match(sql, /website_url!~'\^https:\/\//);
  assert.match(sql, /asset\.scan_state<>'clean'/);
  assert.match(sql, /asset\.variant_state<>'ready'/);
  assert.match(sql, /\^\/media\/public\//);
  assert.match(clubPage, /rel="noopener noreferrer"/);
});

test("contact remains same-origin, captcha protected, limited and retained", () => {
  assert.match(contactRoute, /assertSameOrigin/);
  assert.match(contactRoute, /verifyCaptcha/);
  assert.match(contactBase, /max_requests:=5/);
  assert.match(contactBase, /interval '30 days'/);
  assert.match(sql, /setting\.mode='published'/);
  assert.match(sql, /confirmation\.expires_at>now\(\)/);
  assert.match(sql, /return jsonb_build_object\('accepted',true\)/);
});
