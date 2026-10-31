import assert from "node:assert/strict";
import { test } from "node:test";
import { noHomeFilters, teamMatches } from "../lib/tactics/home.ts";

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
