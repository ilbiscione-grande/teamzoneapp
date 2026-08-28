import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const clubPage = readFileSync(new URL("../app/[clubSlug]/page.tsx", import.meta.url), "utf8");
const teamPage = readFileSync(new URL("../app/[clubSlug]/[teamSlug]/page.tsx", import.meta.url), "utf8");
const notFoundPage = readFileSync(new URL("../app/not-found.tsx", import.meta.url), "utf8");

test("club page exposes the approved official-site structure", () => {
  for (const anchor of ["#om", "#nyheter", "#lag", "#handelser", "#partners", "#kontakt"]) {
    assert.match(clubPage, new RegExp(`href=\\"${anchor}\\"`));
  }
  assert.match(clubPage, /alternates: \{ canonical(?::| \})/);
  assert.match(clubPage, /Officiell klubbsida/);
  assert.match(clubPage, /Verifierad publicering/);
});

test("team page remains an official channel below its club", () => {
  assert.match(teamPage, /Officiell lagkanal/);
  assert.match(teamPage, /getPublications\(club\.id, team\.id\)/);
  assert.match(teamPage, /getTeamEvents\(team\.id\)/);
  assert.match(teamPage, /href=\{`\/\$\{clubSlug\}`\}/);
});

test("unknown public routes have a professional 404", () => {
  assert.match(clubPage, /notFound\(\)/);
  assert.match(teamPage, /notFound\(\)/);
  assert.match(notFoundPage, /404/);
  assert.match(notFoundPage, /Sidan kunde inte hittas/);
});
