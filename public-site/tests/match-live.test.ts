import assert from "node:assert/strict";
import test from "node:test";
import { clockLabel, elapsedSeconds, matchStory, ordinal, type LiveFeedItem } from "../lib/match-live.ts";

const item = (n: number, minute: number, type: string, extra: Partial<LiveFeedItem> = {}): LiveFeedItem =>
  ({ n, minute, type, side: "us", result: null, player: null, second: null, ...extra });

// The same events as the app's report test (test/match_report_text_test.dart),
// as the public feed has them: the public story reads as the app's draft.
const feed: LiveFeedItem[] = [
  item(1, 12, "goal", { player: "Mia", second: "Ali" }),
  item(2, 13, "shot", { player: "Ali", result: "on_target" }),
  item(3, 25, "goal", { side: "opponent" }),
  item(4, 35, "substitution", { player: "Ali", second: "Noa" }),
  item(5, 40, "goal", { player: "Mia" }),
  item(6, 44, "card", { side: "opponent", result: "yellow" }),
  item(7, 45, "card", { player: "Ali", result: "none" }),
  item(8, 52, "shot", { result: "woodwork" }),
];

test("the public story words the match as the app's report does", () => {
  assert.deepEqual(matchStory(feed, { team: "P2012", opponent: "Aneby SK", homeAway: "home" }), [
    "I matchens 12:e spelminut slog hemmalagets Mia till efter en fin passning från Ali och gav P2012 ledningen med 1–0.",
    "I matchens 13:e spelminut fick hemmalagets Ali iväg ett skott på mål, men gästernas målvakt var med och räddade.",
    "Aneby SK kvitterade i 25:e minuten, och det stod 1–1.",
    "I matchens 35:e spelminut gjorde P2012 ett byte: Noa kom in och ersatte Ali.",
    "Jublet var stort i 40:e minuten när Mia hittade nätet för P2012. Det stod nu 2–1.",
    "I matchens 44:e spelminut fick gästerna ett gult kort.",
    "Det var nära i matchens 52:a spelminut när P2012 sköt i ramen. Där saknades bara några centimeter.",
  ]);
});

test("without a name consent the team stands in, and a substitution stays out", () => {
  const story = matchStory([
    item(1, 10, "goal"),
    item(2, 20, "substitution", { player: "Ali" }),
    item(3, 30, "save"),
  ], { team: "P2012", opponent: "Aneby SK", homeAway: "away" });
  assert.equal(story.length, 2);
  assert.ok(story[0].includes("P2012") && !story[0].includes("P2012 P2012"));
  assert.ok(story[1].startsWith("I matchens 30:e spelminut gjorde bortalagets målvakt en viktig räddning"));
});

test("minutes and the clock as the app counts them", () => {
  assert.deepEqual([1, 2, 11, 12, 21, 22, 31].map(ordinal), ["1:a", "2:a", "11:e", "12:e", "21:a", "22:a", "31:a"]);
  const started = "2026-10-24T10:00:00Z";
  const now = new Date("2026-10-24T10:20:30Z");
  assert.equal(elapsedSeconds({ started_at: started, paused_seconds: 30 }, now), 20 * 60);
  // After half time the clock picks up at the scheduled minute.
  assert.equal(elapsedSeconds({ started_at: started, period_end: { scheduled_minute: 30, elapsed_seconds: 28 * 60 } }, now), 20 * 60 + 30 + 120);
  assert.deepEqual(clockLabel({ state: "live", clock: { started_at: started, current_period: 1, period_minutes: [30, 30] } }, now), { time: "20:30", phase: "1:a halvlek" });
  assert.equal(clockLabel({ state: "live", clock: { started_at: started, paused_at: started, period_ended: true, current_period: 1, period_minutes: [30, 30] } }, now).phase, "Halvtid");
  assert.equal(clockLabel({ state: "completed", clock: { started_at: started, completed_at: now.toISOString() } }, now).phase, "Slutresultat");
});
