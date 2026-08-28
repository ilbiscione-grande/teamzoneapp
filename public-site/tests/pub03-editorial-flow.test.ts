import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const root = new URL("../../", import.meta.url);
const sql = readFileSync(new URL("supabase/migrations/20260827131955_pub03_editorial_news_flow.sql", root), "utf8");
const articlePage = readFileSync(new URL("public-site/app/[clubSlug]/nyheter/[articleSlug]/page.tsx", root), "utf8");

test("editorial lifecycle is revisioned, scoped and capability protected", () => {
  assert.match(sql, /publication\.manage/);
  assert.match(sql, /'draft','scheduled','published','unpublished'/);
  assert.match(sql, /expected_revision/);
  assert.match(sql, /core\.editorial_article_revisions/);
  assert.match(sql, /publish_to_club/);
  assert.match(sql, /content_team_channels/);
  assert.match(sql, /'media_status','not_configured'/);
  assert.doesNotMatch(sql, /hero_file_id|core\.file_objects/);
});

test("published content is structured and removed atomically on unpublish", () => {
  assert.match(sql, /block->>'type' not in\('heading','paragraph','link'\)/);
  assert.doesNotMatch(sql, /inner_html|raw_html|<script/i);
  assert.match(sql, /else delete from public_api\.content_projections/);
  assert.match(sql, /publication_projection_jobs/);
  assert.match(sql, /publish_due_editorial_articles/);
});

test("public article route renders only allowlisted blocks", () => {
  assert.match(articlePage, /block\.type === "heading"/);
  assert.match(articlePage, /block\.type === "link"/);
  assert.match(articlePage, /startsWith\("https:\/\/"\)/);
  assert.doesNotMatch(articlePage, /dangerouslySetInnerHTML/);
  assert.match(articlePage, /alternates: \{ canonical/);
});
