import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// The migration as text, line endings as on a Unix checkout.
const sql = readFileSync(new URL("../../supabase/migrations/20270104090000_tactics_event_boards.sql", import.meta.url), "utf8").replace(/\r\n/g, "\n");
const body = (name: string) => {
  const start = sql.indexOf(`create or replace function internal.${name}(`);
  assert.ok(start >= 0, name);
  return sql.slice(start, sql.indexOf("\n$$;", start));
};

test("a board on the plan is a project the editor may open, and goes with it", () => {
  assert.match(sql, /project_id uuid references core\.tactics_projects\(id\) on delete cascade/);
  const add = body("add_match_plan_board_for_actor");
  assert.match(add, /internal\.match_plan_can_edit\(event_row\)/);
  assert.match(add, /internal\.tactics_project_access\(project\) is null/);
});

test("the players open a shown board of a published plan, through a link of their own", () => {
  const open = body("open_match_plan_board_for_actor");
  assert.match(open, /internal\.match_plan_event\(board\.owner_id\)/);
  assert.match(open, /board\.visible_to_players\s+and exists \(select 1 from core\.match_plans plan where plan\.event_id = event_row\.id and plan\.published\)/);
  assert.match(open, /internal\.issue_tactics_player_link\(board\.project_id, board\.board_id\)/);
  const training = body("open_training_block_board_for_actor");
  assert.match(training, /internal\.training_session_event\(block\.event_id\)/);
  assert.match(training, /session\.published/);
});

test("links and boards are listed apart", () => {
  const plan = body("match_plan_json");
  assert.match(plan, /link\.kind = 'link'/);
  assert.match(plan, /board\.kind = 'tactics'/);
});
