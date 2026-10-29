import assert from "node:assert/strict";
import { test } from "node:test";
import { createPlayer, newDocument, newFrame } from "../lib/tactics/document.ts";
import type { PlayerObject, ProjectDocument } from "../lib/tactics/model.ts";
import { exportFileName, exportProject, FILE_FORMAT, parseImport } from "../lib/tactics/transfer.ts";

const withPlayer = (): ProjectDocument => {
  const document = newDocument("Inspark");
  const player = { ...createPlayer({ x: 5, y: 34 }, "home", []), personId: "person-1", name: "Kim" };
  return { ...document, squad: [{ personId: "person-1", name: "Kim", number: 1, position: null }],
    boards: [{ ...document.boards[0], frames: [newFrame([player])] }] };
};

test("an exported project imports as it was, named and of its kind, without ties to a team's players", () => {
  const document = withPlayer();
  const result = parseImport(exportProject("Speluppbyggnad", "education", document), "x.json");
  assert.ok(!("error" in result));
  assert.equal(result.name, "Speluppbyggnad");
  assert.equal(result.kind, "education");
  assert.equal(result.document.boards[0].name, "Inspark");
  assert.deepEqual(result.document.squad, []);
  const player = result.document.boards[0].frames[0].objects[0] as PlayerObject;
  assert.equal(player.personId, null);
  assert.equal(player.name, "Kim", "names drawn on the board stay");
});

test("a bare document imports too, named after the file", () => {
  const result = parseImport(JSON.stringify(withPlayer()), "Min spelidé.tacticsboard.json");
  assert.ok(!("error" in result));
  assert.equal(result.name, "Min spelidé");
  assert.equal(result.kind, "match");
});

test("what is not a project is refused with a reason", () => {
  for (const [text, reason] of [
    ["not json", /JSON/],
    ["[]", /inga tavlor/],
    ["{\"boards\": []}", /inga tavlor/],
    ["{\"boards\": [{\"name\": \"A\"}]}", /frames/],
    [JSON.stringify({ format: FILE_FORMAT, version: 99, name: "A", kind: "match", document: withPlayer() }), /nyare version/],
  ] as const) {
    const result = parseImport(text);
    assert.ok("error" in result, text);
    assert.match(result.error, reason);
  }
});

test("export file names keep letters and digits", () => {
  assert.equal(exportFileName("Spelidé 2026: inspark"), "Spelidé_2026_inspark.tacticsboard.json");
  assert.equal(exportFileName("  "), "projekt.tacticsboard.json");
});
