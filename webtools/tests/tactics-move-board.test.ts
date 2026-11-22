import assert from "node:assert/strict";
import { test } from "node:test";
import { moveBoard } from "../lib/tactics/document.ts";
import type { ProjectDocument } from "../lib/tactics/model.ts";

const named = (...ids: string[]) => ({ boards: ids.map(id => ({ id })) }) as unknown as ProjectDocument;
const order = (document: ProjectDocument) => document.boards.map(board => board.id).join("");

test("a board dragged to a new place lands there, the others keeping their order", () => {
  assert.equal(order(moveBoard(named("a", "b", "c", "d"), 0, 2)), "bcad");
  assert.equal(order(moveBoard(named("a", "b", "c", "d"), 3, 1)), "adbc");
});

test("dropped on itself or outside the boards, nothing changes", () => {
  const document = named("a", "b");
  assert.equal(moveBoard(document, 1, 1), document);
  assert.equal(moveBoard(document, 0, 5), document);
});
