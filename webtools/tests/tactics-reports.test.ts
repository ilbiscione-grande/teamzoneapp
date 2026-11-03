import assert from "node:assert/strict";
import { test } from "node:test";
import type { Board } from "../lib/tactics/model.ts";
import { boardTexts, noteReady, openReports, reportReady, reportText, reviewErrorText, reviewStatus, type ReportEntry } from "../lib/tactics/reports.ts";

const report = (resolved: boolean): ReportEntry => ({
  reason: "Kopierat från någon annan", created_at: "2026-11-03T10:00:00Z",
  resolution: resolved ? "dismissed" : null, resolved_at: resolved ? "2026-11-03T12:00:00Z" : null,
});

test("a report is the reason, then the reporter's words, at most 500 characters", () => {
  assert.equal(reportText("spam", ""), "Reklam eller skräp");
  assert.equal(reportText("copyright", "  från   en bok "), "Kopierat från någon annan: från en bok");
  assert.equal(reportText("other", "x".repeat(600)).length, 500);
});

test("something else needs words; the other reasons do not", () => {
  assert.equal(reportReady("", "text"), false);
  assert.equal(reportReady("offensive", ""), true);
  assert.equal(reportReady("other", "  "), false);
  assert.equal(reportReady("other", "Fel sport"), true);
});

test("where an item stands for support", () => {
  assert.equal(reviewStatus({ hidden: false, hidden_by_support: false, reports: [report(false)] }), "1 anmälan, syns i biblioteket");
  assert.equal(reviewStatus({ hidden: true, hidden_by_support: false, reports: [report(false), report(false), report(false)] }),
    "Dold efter 3 anmälningar, väntar på beslut");
  assert.equal(reviewStatus({ hidden: true, hidden_by_support: true, reports: [report(true)] }), "Dold av supporten");
  assert.equal(reviewStatus({ hidden: false, hidden_by_support: false, reports: [report(true)] }), "Behållen");
  assert.equal(openReports({ reports: [report(true), report(false)] }).length, 1);
});

test("support's note is 5 to 1000 characters", () => {
  assert.equal(noteReady(" ok "), false);
  assert.equal(noteReady("Inget olämpligt"), true);
  assert.equal(noteReady("x".repeat(1001)), false);
});

test("every text a board shows, once each", () => {
  const board = {
    id: "b1", name: "Rondo", description: "Fem mot två", exercise: { coachingPoints: "Vinkla kroppen" },
    frames: [
      { objects: [{ type: "text", text: "Press!" }, { type: "player", label: "Butez" }, { type: "ball" }] },
      { objects: [{ type: "text", text: "Press!" }] },
    ],
  } as unknown as Board;
  assert.deepEqual(boardTexts(board), ["Rondo", "Fem mot två", "Vinkla kroppen", "Press!", "Butez"]);
});

test("the server's refusals in words", () => {
  assert.match(reviewErrorText("not_found"), /rätt att granska/);
  assert.match(reviewErrorText("invalid_input"), /minst 5 tecken/);
});
