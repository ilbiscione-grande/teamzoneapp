import assert from "node:assert/strict";
import { test } from "node:test";
import { noDetails, noHomeFilters, teamMatches, withDetails } from "../lib/tactics/home.ts";
import type { Board } from "../lib/tactics/model.ts";

const press = { name: "Pressspel", kind: "match" as const, team_name: "P2012", owner_name: "Anna Ek" };

test("the team's projects are found by every word, in name, team or maker", () => {
  assert.equal(teamMatches(press, noHomeFilters), true);
  assert.equal(teamMatches(press, { ...noHomeFilters, text: "press anna" }), true);
  assert.equal(teamMatches(press, { ...noHomeFilters, text: "p2012" }), true);
  assert.equal(teamMatches(press, { ...noHomeFilters, text: "press olle" }), false);
});

test("the team's projects follow the kind, and the library's other filters leave them out", () => {
  assert.equal(teamMatches(press, { ...noHomeFilters, kind: "match" }), true);
  assert.equal(teamMatches(press, { ...noHomeFilters, kind: "training" }), false);
  assert.equal(teamMatches(press, { ...noHomeFilters, phase: "defence" as never }), false);
});

test("a new project's details go on every board, each keeping its own part", () => {
  const plain = { id: "a", name: "Uppvärmning" } as unknown as Board;
  const told = { id: "b", name: "Spel", exercise: { part: "finish", minutes: 20, players: 8, area: "", coachingPoints: "Djup", phase: null, ageClasses: ["7-9"], gameForms: [] } } as unknown as Board;
  assert.deepEqual(withDetails([plain, told], noDetails), [plain, told], "nothing told, nothing changed");
  const [first, second] = withDetails([plain, told], { phase: "build_up", ageClasses: ["10-12"], gameForms: ["7v7"] }, ["warmup", undefined]);
  assert.equal(first.exercise?.part, "warmup");
  assert.equal(first.exercise?.phase, "build_up");
  assert.deepEqual(second.exercise && [second.exercise.part, second.exercise.coachingPoints, second.exercise.ageClasses, second.exercise.gameForms],
    ["finish", "Djup", ["10-12"], ["7v7"]]);
});
