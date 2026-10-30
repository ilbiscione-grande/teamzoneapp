import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { versionErrorText, versionNote, versionTime, type VersionSummary } from "../lib/tactics/versions.ts";

// The migration as text, line endings as on a Unix checkout.
const sql = readFileSync(new URL("../../supabase/migrations/20270101090000_tactics_versions.sql", import.meta.url), "utf8").replace(/\r\n/g, "\n");
const body = (name: string) => {
  const start = sql.indexOf(`create or replace function internal.${name}(`);
  assert.ok(start >= 0, name);
  return sql.slice(start, sql.indexOf("\n$$;", start));
};

test("versions are the owner's alone, and kept by a trigger on every write", () => {
  assert.match(sql, /alter table core\.tactics_project_versions enable row level security/);
  assert.match(sql, /revoke all on core\.tactics_project_versions from public, anon, authenticated/);
  assert.match(sql, /references core\.tactics_projects\(id\) on delete cascade/);
  assert.match(sql, /before update on core\.tactics_projects\s+for each row execute function internal\.tactics_keep_version\(\)/);
  for (const name of ["list_tactics_versions_for_actor", "get_tactics_version_for_actor", "restore_tactics_version_for_actor"]) {
    assert.match(body(name), /internal\.tactics_owned_project\(/, name);
  }
  assert.match(body("restore_tactics_version_for_actor"), /stale_revision/);
});

test("the trigger is no function anyone calls", () => {
  const granted = sql.slice(sql.indexOf("grant execute on function"));
  assert.doesNotMatch(granted, /tactics_keep_version/);
});

test("a version's time reads as a day and a clock", () => {
  const now = new Date(2026, 9, 30, 20, 0);
  assert.equal(versionTime(new Date(2026, 9, 30, 19, 40).toISOString(), now), "I dag 19:40");
  assert.equal(versionTime(new Date(2026, 9, 29, 8, 5).toISOString(), now), "I går 08:05");
  assert.equal(versionTime(new Date(2026, 9, 27, 18, 0).toISOString(), now), "Tis 18:00");
  assert.equal(versionTime(new Date(2026, 9, 3, 18, 0).toISOString(), now), "3 okt 18:00");
  assert.equal(versionTime(new Date(2025, 11, 24, 9, 30).toISOString(), now), "24 dec 2025 09:30");
});

test("a version's note says who, how many boards and a restore", () => {
  const version: VersionSummary = { id: "v", revision: 3, name: "P", saved_at: "", reason: "edit", saved_by_me: true, saved_by_name: "Anna", boards: ["A"] };
  assert.equal(versionNote(version), "du · 1 tavla");
  assert.equal(versionNote({ ...version, saved_by_me: false, boards: ["A", "B"], reason: "before_restore" }), "Anna · 2 tavlor · före en återställning");
  assert.equal(versionNote({ ...version, saved_by_me: false, saved_by_name: null }), "en annan ledare · 1 tavla");
  assert.match(versionErrorText("stale_revision"), /sparats under tiden/);
});
