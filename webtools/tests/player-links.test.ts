import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// The migration as text, line endings as on a Unix checkout.
const sql = readFileSync(new URL("../../supabase/migrations/20270103090000_tactics_player_links.sql", import.meta.url), "utf8").replace(/\r\n/g, "\n");
const body = (name: string) => {
  const start = sql.indexOf(`create or replace function internal.${name}(`);
  assert.ok(start >= 0, name);
  return sql.slice(start, sql.indexOf("\n$$;", start));
};

test("a player's link is theirs, for six hours, and shows nothing after", () => {
  assert.match(body("issue_tactics_player_link"), /now\(\) \+ interval '6 hours'/);
  assert.match(body("issue_tactics_player_link"), /link\.issued_to = auth\.uid\(\)/);
  assert.match(body("get_shared_tactics"), /link\.expires_at is null or link\.expires_at > now\(\)/);
});

test("the owner's links never include a player's", () => {
  assert.match(body("create_tactics_share_link_for_actor"), /link\.issued_to is null/);
  assert.match(body("list_tactics_share_links_for_actor"), /link\.issued_to is null/);
});

test("no one asks for a player's link directly", () => {
  assert.match(sql, /revoke all on function internal\.issue_tactics_player_link\(uuid, text\) from public, anon, authenticated;/);
  assert.doesNotMatch(sql, /grant execute on function internal\.issue_tactics_player_link/);
});
