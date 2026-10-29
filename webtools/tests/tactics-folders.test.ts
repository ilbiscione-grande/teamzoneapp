import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { folderErrorText, joinNames, moveInOrder, removalNote, toggleFolder } from "../lib/tactics/folders.ts";

// The migration as text, line endings as on a Unix checkout.
const sql = readFileSync(new URL("../../supabase/migrations/20261223090000_tactics_folders.sql", import.meta.url), "utf8").replace(/\r\n/g, "\n");
const body = (name: string) => {
  const start = sql.indexOf(`create or replace function internal.${name}(`);
  assert.ok(start >= 0, name);
  return sql.slice(start, sql.indexOf("\n$$;", start));
};

test("a project moves a step up or down in its folder, not past an end", () => {
  const ids = ["build-up", "finish", "transition"];
  assert.deepEqual(moveInOrder(ids, 2, -1), ["build-up", "transition", "finish"]);
  assert.deepEqual(moveInOrder(ids, 0, 1), ["finish", "build-up", "transition"]);
  assert.deepEqual(moveInOrder(ids, 0, -1), ids);
  assert.deepEqual(moveInOrder(ids, 2, 1), ids);
  assert.deepEqual(ids, ["build-up", "finish", "transition"], "the order given is kept");
});

test("ticking a folder adds it once, unticking takes only it away", () => {
  assert.deepEqual(toggleFolder(["2026"], "2027", true), ["2026", "2027"]);
  assert.deepEqual(toggleFolder(["2026", "2027"], "2027", true), ["2026", "2027"]);
  assert.deepEqual(toggleFolder(["2026", "2027"], "2026", false), ["2027"]);
});

test("removing a project names the folders it leaves", () => {
  assert.equal(joinNames(["A", "B", "C"]), "A, B och C");
  assert.equal(removalNote([]), "");
  assert.equal(removalNote([{ id: "1", name: "Spelidé 2026" }]), " Det tas också bort ur mappen Spelidé 2026.");
  assert.equal(removalNote([{ id: "1", name: "Spelidé 2026" }, { id: "2", name: "Spelidé 2027" }]),
    " Det tas också bort ur mapparna Spelidé 2026 och Spelidé 2027.");
});

test("a folder's limits get their own messages", () => {
  assert.match(folderErrorText("too_many_folders", "x"), /200 mappar/);
  assert.match(folderErrorText("too_many_projects", "x"), /100 projekt/);
  assert.equal(folderErrorText("boom", "Mappen kunde inte skapas."), "Mappen kunde inte skapas.");
});

test("a project can be linked into many folders, each once, and links go with folder or project", () => {
  assert.match(sql, /primary key \(folder_id, project_id\)/);
  assert.match(sql, /folder_id uuid not null references core\.tactics_folders\(id\) on delete cascade/);
  assert.match(sql, /project_id uuid not null references core\.tactics_projects\(id\) on delete cascade/);
  // No column ties a project to a single folder.
  assert.doesNotMatch(sql, /alter table core\.tactics_projects/);
});

test("folders are private: no table access, and every function checks the owner", () => {
  assert.match(sql, /alter table core\.tactics_folders enable row level security/);
  assert.match(sql, /alter table core\.tactics_folder_projects enable row level security/);
  assert.match(sql, /revoke all on core\.tactics_folders, core\.tactics_folder_projects from public, anon, authenticated/);
  for (const name of ["get_tactics_folder_for_actor", "update_tactics_folder_for_actor", "remove_tactics_folder_project_for_actor",
    "order_tactics_folder_for_actor"]) {
    assert.match(body(name), /tactics_require_folder_owner\(target_folder_id\)/, name);
  }
  assert.match(body("add_tactics_folder_project_for_actor"), /tactics_require_folder_owner[\s\S]*tactics_require_owner\(target_project_id\)/);
  assert.match(body("set_tactics_project_folders_for_actor"), /tactics_require_owner\(target_project_id\)[\s\S]*folder\.owner_id = auth\.uid\(\)/);
  assert.match(body("delete_tactics_folder_for_actor"), /owner_id = auth\.uid\(\)/);
  assert.match(body("list_my_tactics_folders_for_actor"), /folder\.owner_id = auth\.uid\(\)/);
});

test("removing a folder or taking a project out never removes a project", () => {
  assert.doesNotMatch(body("delete_tactics_folder_for_actor"), /tactics_projects/);
  assert.doesNotMatch(body("remove_tactics_folder_project_for_actor"), /delete from core\.tactics_projects/);
  assert.doesNotMatch(body("set_tactics_project_folders_for_actor"), /delete from core\.tactics_projects/);
});

test("every api function is granted to signed-in people only", () => {
  const apis = [...sql.matchAll(/create or replace function (api\.\w+)\(/g)].map(match => match[1]);
  assert.equal(apis.length, 9);
  const [revoked, granted] = [sql.slice(sql.indexOf("revoke all on function")), sql.slice(sql.indexOf("grant execute on function"))];
  for (const name of apis) {
    assert.ok(revoked.includes(`${name}(`), `${name} revoked`);
    assert.ok(granted.includes(`${name}(`), `${name} granted`);
  }
  assert.match(granted, /\nto authenticated;/);
  // Helpers run inside the definer functions only.
  assert.doesNotMatch(granted.slice(0, granted.indexOf(";")), /tactics_link_folder_project|tactics_require_folder_owner/);
});

test("the library's search gives each project its folders", () => {
  assert.match(body("search_my_tactics_projects_for_actor"), /'folders', coalesce\(/);
});
