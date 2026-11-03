import assert from "node:assert/strict";
import { test } from "node:test";
import { groupConnections, requiresAcceptance, validCredentials, validNewPassword, type Connection } from "../lib/account.ts";
import { findApp, safeReturnTo, webtoolApps } from "../lib/apps.ts";

test("the catalog has the four planned apps with unique slugs", () => {
  assert.deepEqual(webtoolApps.map(app => app.name), ["Tacticsboard", "Video Analyzer", "Bokningshanterare", "Turneringsplanerare"]);
  assert.equal(new Set(webtoolApps.map(app => app.slug)).size, webtoolApps.length);
  for (const app of webtoolApps) assert.match(app.slug, /^[a-z0-9-]+$/);
  assert.equal(findApp("tacticsboard")?.name, "Tacticsboard");
  assert.equal(findApp("nope"), undefined);
});

test("only Webtools' own pages are returned to after sign-in", () => {
  assert.equal(safeReturnTo("/appar/tacticsboard"), "/appar/tacticsboard");
  assert.equal(safeReturnTo("/konto"), "/konto");
  assert.equal(safeReturnTo("/live/K7P2QX"), "/live/K7P2QX");
  assert.equal(safeReturnTo("/tacticsboard/bibliotek"), "/tacticsboard/bibliotek");
  assert.equal(safeReturnTo("/tacticsboard/granska"), "/tacticsboard/granska");
  assert.equal(safeReturnTo("/tacticsboard/mapp/3f2b8c1e-5a4d-4e6f-9b7a-0c1d2e3f4a5b"), "/tacticsboard/mapp/3f2b8c1e-5a4d-4e6f-9b7a-0c1d2e3f4a5b");
  assert.equal(safeReturnTo("/tacticsboard/mapp/x"), "/");
  assert.equal(safeReturnTo("/live/k7p2qx"), "/");
  assert.equal(safeReturnTo(null), "/");
  assert.equal(safeReturnTo("/appar/okand"), "/");
  assert.equal(safeReturnTo("https://evil.example"), "/");
  assert.equal(safeReturnTo("//evil.example"), "/");
  assert.equal(safeReturnTo("/appar/tacticsboard?x=1"), "/");
});

test("credentials are checked before they are sent", () => {
  assert.equal(validCredentials("a@b.se", "x", false), null);
  assert.match(validCredentials("nope", "secret12", false) ?? "", /e-postadress/);
  assert.match(validCredentials("a@b.se", "kort", true) ?? "", /8 tecken/);
  assert.match(validCredentials("a@b.se", "hemligt123", true) ?? "", /specialtecken/);
  assert.equal(validCredentials("a@b.se", "Hemligt12!", true), null);
  assert.match(validCredentials("a@b.se", "", false) ?? "", /lösenord/);
});

test("a new password is long enough and written the same twice", () => {
  assert.equal(validNewPassword("Hemligt12!", "Hemligt12!"), null);
  assert.match(validNewPassword("Kort1!", "Kort1!") ?? "", /8 tecken/);
  for (const weak of ["HEMLIGT12!", "hemligt12!", "Hemligtxx!", "Hemligt123", "Hemligt12§"]) assert.match(validNewPassword(weak, weak) ?? "", /specialtecken/);
  assert.match(validNewPassword("Hemligt12!", "Hemligt12?") ?? "", /likadana/);
});

test("terms must both be accepted", () => {
  const base = { terms_version: "1", terms_url: "t", privacy_version: "1", privacy_url: "p" };
  assert.equal(requiresAcceptance({ ...base, terms_accepted: true, privacy_accepted: true }), false);
  assert.equal(requiresAcceptance({ ...base, terms_accepted: true, privacy_accepted: false }), true);
});

test("connections group by club, the whole club first, roles merged", () => {
  const row = (club: string, team: string | null, role: string): Connection => ({
    context_id: `${club}-${team}-${role}`, club_id: club, club_name: club === "b" ? "Bollklubben" : "Demoklubben IF",
    team_id: team, team_name: team, role_package: role,
  });
  const groups = groupConnections([
    row("d", "P2012", "leader"), row("d", null, "club_functionary"), row("d", "P2012", "player"), row("b", "F14", "guardian"),
  ]);
  assert.deepEqual(groups.map(group => group.club), ["Bollklubben", "Demoklubben IF"]);
  assert.deepEqual(groups[1].items, [
    { name: "Hela klubben", roles: ["Klubbfunktionär"] },
    { name: "P2012", roles: ["Ledare", "Spelare"] },
  ]);
});
