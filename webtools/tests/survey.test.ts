import assert from "node:assert/strict";
import test from "node:test";
import { cleanAnswers, submitError, surveySender, validSurveyToken, type SurveyQuestion } from "../lib/survey.ts";
import { tacticsboardOnlyRedirect } from "../lib/site-scope.ts";

const questions: SurveyQuestion[] = [
  { id: "q1abc", kind: "scale", label: "Trivsel", required: true },
  { id: "q2abc", kind: "single", label: "Position", required: false, options: ["Back", "Mitt"] },
  { id: "q3abc", kind: "multi", label: "Utveckla", required: false, options: ["Pass", "Skott", "Löp"] },
  { id: "q4abc", kind: "long_text", label: "Mer", required: false },
];

test("answers are cleaned as the database keeps them", () => {
  const clean = cleanAnswers(questions, { q1abc: 4, q2abc: "Mål", q3abc: ["Löp", "Pass", "Annat"], q4abc: "  hej  ", other: 1 });
  assert.deepEqual(clean, { answers: { q1abc: 4, q3abc: ["Pass", "Löp"], q4abc: "hej" } });
  assert.deepEqual(cleanAnswers(questions, { q1abc: "5" }), { answers: { q1abc: 5 } });
});

test("a required question left out is named", () => {
  const clean = cleanAnswers(questions, { q1abc: 7, q4abc: "x" });
  assert.ok("missing" in clean && clean.missing.id === "q1abc");
});

test("links and messages", () => {
  assert.ok(validSurveyToken("a".repeat(32)));
  assert.ok(!validSurveyToken("A".repeat(32)));
  assert.ok(!validSurveyToken("../x"));
  assert.equal(submitError("ERROR: rate_limited"), "Många svar har skickats härifrån. Försök igen om en stund.");
  assert.equal(surveySender({ team_name: "P2012", club_name: "IF Test" }), "P2012 · IF Test");
  assert.equal(surveySender({ team_name: null, club_name: "IF Test" }), "IF Test");
});

test("the survey page stays open when only Tacticsboard is sold", () => {
  assert.equal(tacticsboardOnlyRedirect(`/enkat/${"a".repeat(32)}`), null);
});
