import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// The migration as text, line endings as on a Unix checkout.
const sql = readFileSync(new URL("../../supabase/migrations/20261224090000_tactics_folder_share_links.sql", import.meta.url), "utf8").replace(/\r\n/g, "\n");
const body = (name: string) => {
  const start = sql.indexOf(`create or replace function internal.${name}(`);
  assert.ok(start >= 0, name);
  return sql.slice(start, sql.indexOf("\n$$;", start));
};

test("only the folder's owner makes, reads and takes back its link", () => {
  assert.match(sql, /alter table core\.tactics_folder_share_links enable row level security/);
  assert.match(sql, /revoke all on core\.tactics_folder_share_links from public, anon, authenticated/);
  for (const name of ["create_tactics_folder_share_link_for_actor", "get_tactics_folder_share_link_for_actor", "revoke_tactics_folder_share_link_for_actor"]) {
    assert.match(body(name), /tactics_require_folder_owner\(/, name);
  }
  assert.match(sql, /folder_id uuid not null references core\.tactics_folders\(id\) on delete cascade/);
});

test("the shared pages show live links only, and only the folder's own projects", () => {
  assert.match(body("get_shared_tactics_folder"), /link\.revoked_at is null/);
  const project = body("get_shared_tactics_folder_project");
  assert.match(project, /link\.revoked_at is null/);
  assert.match(project, /member\.folder_id = folder\.id and member\.project_id = target_project_id/);
});

test("the shared pages are read by Webtools' server only", () => {
  const granted = sql.slice(sql.indexOf("grant execute on function"));
  const toSignedIn = granted.slice(0, granted.indexOf("to authenticated;"));
  assert.doesNotMatch(toSignedIn, /get_shared_tactics_folder/);
  assert.match(granted, /api\.get_shared_tactics_folder\(text\), api\.get_shared_tactics_folder_project\(text, uuid\)\nto service_role;/);
});
