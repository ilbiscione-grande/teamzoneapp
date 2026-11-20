import assert from "node:assert/strict";
import test from "node:test";
import { initials, playerLabel, positionName, positionShort, shortName } from "../lib/tactics/player-label.ts";

type Player = { number: number | null; name: string; position: string | null };
const karl: Player = { number: 7, name: "Karl Svensson", position: "defensive_midfielder" };
const shown = (number: boolean, name: boolean, position: boolean) => ({ showNumbers: number, showNames: name, showPositions: position });
const label = (number: boolean, name: boolean, position: boolean, player = karl) => playerLabel(player, shown(number, name, position), "sv");

test("names shortened and as initials, three for a double first name", () => {
  assert.equal(shortName("Karl Svensson"), "K. Svensson");
  assert.equal(shortName("Niman abdirahman Ali"), "N. Ali");
  assert.equal(shortName("Zlatan"), "Zlatan");
  assert.equal(initials("Karl Svensson"), "KS");
  assert.equal(initials("Niman abdirahman Ali"), "NAA");
  assert.equal(initials("Anna Maria Eva Lind"), "AML");
  assert.equal(shortName("  "), null);
});

test("positions shortened: TeamZone's codes and own ones by their words", () => {
  assert.equal(positionShort("defensive_midfielder"), "CDM");
  assert.equal(positionShort("goalkeeper"), "GK");
  assert.equal(positionShort("mv"), "MV");
  assert.equal(positionShort("Central defensiv mittfältare"), "CDM");
  assert.equal(positionName("defensive_midfielder", "sv"), "Defensiv mittfältare");
  assert.equal(positionName("defensive_midfielder", "en"), "Defensive midfielder");
  assert.equal(positionName("Libero", "sv"), "Libero");
});

test("one choice: one thing in the disc and nothing under", () => {
  assert.deepEqual(label(false, false, false), { inside: "7", below: null });
  assert.deepEqual(label(true, false, false), { inside: "7", below: null });
  assert.deepEqual(label(false, true, false), { inside: "KS", below: null });
  assert.deepEqual(label(false, false, true), { inside: "CDM", below: null });
});

test("several choices: the disc and the text under it", () => {
  assert.deepEqual(label(true, false, true), { inside: "7", below: "Defensiv mittfältare" });
  assert.deepEqual(label(false, true, true), { inside: "CDM", below: "K. Svensson" });
  assert.deepEqual(label(true, true, false), { inside: "7", below: "K. Svensson" });
  assert.deepEqual(label(true, true, true), { inside: "CDM", below: "K. Svensson (7)" });
});

test("what a player lacks falls back, and old boards show the number", () => {
  const bare = { number: null, name: "Karl Svensson", position: null };
  assert.deepEqual(label(false, false, true, bare), { inside: "KS", below: null });
  assert.deepEqual(label(true, true, true, { ...karl, position: null }), { inside: "7", below: "K. Svensson" });
  assert.deepEqual(playerLabel(karl, { showNames: true }, "sv"), { inside: "7", below: "K. Svensson" });
});
