import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// The migration as text, line endings as on a Unix checkout.
const sql = readFileSync(new URL("../../supabase/migrations/20270102090000_tactics_leader_access.sql", import.meta.url), "utf8").replace(/\r\n/g, "\n");
const body = (name: string) => {
  const start = sql.indexOf(`create or replace function internal.${name}(`);
  assert.ok(start >= 0, name);
  return sql.slice(start, sql.indexOf("\n$$;", start));
};

test("a team's other leaders are those who lead it, and watch unless the owner lets them edit", () => {
  assert.match(sql, /leader_access text not null default 'view' check \(leader_access in \('view', 'edit'\)\)/);
  assert.match(body("tactics_project_access"), /internal\.tournament_actor_teams\(\)/);
  assert.match(body("set_tactics_leader_access_for_actor"), /owner_id = auth\.uid\(\)/);
});

test("another leader saves the boards only, and never reads the owner's notes", () => {
  const save = body("save_tactics_project_for_actor");
  assert.match(save, /access is null or access = 'view'/);
  assert.match(save, /if access = 'edit' then\s+update core\.tactics_projects set document = project_document, revision = revision \+ 1, updated_at = now\(\)/);
  assert.match(save, /stale_revision/);
  assert.match(body("get_tactics_project_for_actor"), /case when access = 'owner' then project\.host_notes else '\{\}'::jsonb end/);
});

test("versions are seen by those who may edit, put back by the owner alone", () => {
  assert.match(body("tactics_versions_project"), /coalesce\(internal\.tactics_project_access\(project\), 'view'\) = 'view'/);
  assert.doesNotMatch(sql, /restore_tactics_version_for_actor/);
});
