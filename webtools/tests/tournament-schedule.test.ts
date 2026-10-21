import assert from "node:assert/strict";
import { test } from "node:test";
import { assignTimes, distributeTeams, groupMatches, groupName, matchesByDay, playoffBracket, roundRobin, scoreLabel, tournamentDays, type ScheduleMatch } from "../lib/tournament-schedule.ts";

test("teams spread over groups in a snake; groups are lettered", () => {
  assert.deepEqual(distributeTeams([1, 2, 3, 4, 5, 6, 7], 3), [[1, 6, 7], [2, 5], [3, 4]]);
  assert.deepEqual(distributeTeams([1, 2], 5), [[1], [2]]);
  assert.deepEqual([groupName(0), groupName(25), groupName(26)], ["A", "Z", "AA"]);
});

test("a round-robin meets everyone once, a team at most once a round", () => {
  for (const size of [2, 3, 4, 5, 6, 7]) {
    const teams = Array.from({ length: size }, (_, i) => i);
    const rounds = roundRobin(teams);
    const pairs = rounds.flat().map(([a, b]) => [Math.min(a, b), Math.max(a, b)].join("-"));
    assert.equal(new Set(pairs).size, size * (size - 1) / 2, `${size} teams`);
    assert.equal(pairs.length, size * (size - 1) / 2);
    for (const round of rounds) {
      const playing = round.flat();
      assert.equal(new Set(playing).size, playing.length);
    }
  }
  // Home and away are shared out.
  const homes = roundRobin([0, 1, 2, 3]).flat().map(([home]) => home);
  for (const team of [0, 1, 2, 3]) assert.ok(homes.filter(home => home === team).length <= 2);
});

test("group matches run round by round across the groups", () => {
  const matches = groupMatches([["a", "b", "c"], ["d", "e", "f"]]);
  assert.equal(matches.length, 6);
  assert.deepEqual(matches.map(m => [m.round, m.group]), [[1, 0], [1, 1], [2, 0], [2, 1], [3, 0], [3, 1]]);
});

test("a play-off crosses the groups and follows its winners", () => {
  const semis = playoffBracket(2, [1, 2], "", true)!;
  assert.deepEqual(semis.map(m => m.label), ["Semifinal 1", "Semifinal 2", "Bronsmatch", "Final"]);
  assert.deepEqual([semis[0].home_source, semis[0].away_source], [{ kind: "group_place", group: 0, place: 1 }, { kind: "group_place", group: 1, place: 2 }]);
  assert.deepEqual([semis[1].home_source, semis[1].away_source], [{ kind: "group_place", group: 1, place: 1 }, { kind: "group_place", group: 0, place: 2 }]);
  assert.deepEqual([semis[3].home_source, semis[3].away_source], [{ kind: "winner", match: 0 }, { kind: "winner", match: 1 }]);
  assert.deepEqual(semis[2].home_source, { kind: "loser", match: 0 });
  // A B play-off after the A one: its sources count from where it starts.
  const b = playoffBracket(2, [3], "B-", false, 4)!;
  assert.deepEqual(b.map(m => [m.label, m.home_source, m.away_source]), [["B-final", { kind: "group_place", group: 0, place: 3 }, { kind: "group_place", group: 1, place: 3 }]]);
  const quarters = playoffBracket(4, [1, 2], "A-", false)!;
  assert.deepEqual(quarters.map(m => m.label), ["A-kvartsfinal 1", "A-kvartsfinal 2", "A-kvartsfinal 3", "A-kvartsfinal 4", "A-semifinal 1", "A-semifinal 2", "A-final"]);
  assert.equal(playoffBracket(3, [1, 2], "", false), null, "six teams is no bracket");
});

test("times fill the earliest pitch, rest teams and keep play-offs after", () => {
  const options = { pitches: ["p1", "p2"], days: [{ date: "2026-11-14", start: "09:00", end: "10:00" }], minutes: 10, gap: 5, rest: true, busy: [] };
  const times = assignTimes([{ teams: ["a", "b"] }, { teams: ["c", "d"] }, { teams: ["a", "c"] }, { teams: ["b", "d"] }], options);
  const local = (iso: string | undefined) => iso ? new Date(iso).toTimeString().slice(0, 5) : null;
  assert.deepEqual(times.map(t => [t?.pitch_id, local(t?.starts_at)]), [["p1", "09:00"], ["p2", "09:00"], ["p1", "09:30"], ["p2", "09:30"]], "a rest slot between");
  // A busy pitch is skipped; what depends on a match waits for it.
  const busy = [{ pitch_id: "p1", starts_at: new Date(2026, 10, 14, 9, 0).toISOString(), ends_at: new Date(2026, 10, 14, 9, 10).toISOString() }];
  const next = assignTimes([{ teams: ["a", "b"] }, { teams: [], dependsOn: [0] }], { ...options, busy });
  assert.deepEqual(next.map(t => [t?.pitch_id, local(t?.starts_at)]), [["p2", "09:00"], ["p1", "09:15"]]);
  // Out of time: null.
  const full = assignTimes(Array.from({ length: 9 }, (_, i) => ({ teams: [`t${i}`, `u${i}`] })), options);
  assert.equal(full.filter(t => t === null).length, 1);
});

test("days, scores and the list by day", () => {
  assert.deepEqual(tournamentDays("2026-11-14", "2026-11-16"), ["2026-11-14", "2026-11-15", "2026-11-16"]);
  assert.deepEqual(tournamentDays("2026-12-31", "2027-01-01"), ["2026-12-31", "2027-01-01"]);
  const match = (id: string, starts: string | null, extra: Partial<ScheduleMatch> = {}): ScheduleMatch => ({
    id, class_id: "c", group_id: null, stage: "group", round: 1, label: null, sort_order: 0, home_registration_id: null, away_registration_id: null,
    home_name: null, away_name: null, pitch_id: null, starts_at: starts, ends_at: null, status: "scheduled",
    home_score: null, away_score: null, home_penalties: null, away_penalties: null, ...extra,
  });
  assert.equal(scoreLabel(match("a", null)), null);
  assert.equal(scoreLabel(match("a", null, { status: "played", home_score: 1, away_score: 1, home_penalties: 4, away_penalties: 3 })), "1–1 (4–3 str.)");
  const days = matchesByDay([match("late", new Date(2026, 10, 15, 9).toISOString()), match("none", null), match("early", new Date(2026, 10, 14, 9).toISOString())]);
  assert.deepEqual(days.map(d => [d.day, d.matches.map(m => m.id)]), [["2026-11-14", ["early"]], ["2026-11-15", ["late"]], [null, ["none"]]]);
});

test("the public page groups by Swedish day, whatever the server's zone", async () => {
  const { publicMatchesByDay, swedishClock, swedishDayLabel } = await import("../lib/public-tournament.ts");
  const match = (id: string, starts: string) => ({
    id, class_id: "c", group_id: null, stage: "group" as const, round: 1, label: null, sort_order: 0, home_registration_id: null, away_registration_id: null,
    home_name: null, away_name: null, pitch_id: null, starts_at: starts, ends_at: null, status: "scheduled" as const,
    home_score: null, away_score: null, home_penalties: null, away_penalties: null,
  });
  // 23:30 UTC is already the next day in Stockholm.
  const days = publicMatchesByDay([match("late", "2026-11-14T23:30:00Z"), match("early", "2026-11-14T08:00:00Z")]);
  assert.deepEqual(days.map(d => [d.day, d.matches.map(m => m.id)]), [["2026-11-14", ["early"]], ["2026-11-15", ["late"]]]);
  assert.equal(swedishClock("2026-11-14T08:00:00Z"), "09:00");
  assert.equal(swedishDayLabel("2026-11-14"), "lördag 14 november");
});
