import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const terms = readFileSync(new URL("../app/villkor/page.tsx", import.meta.url), "utf8");
const privacy = readFileSync(new URL("../app/integritet/page.tsx", import.meta.url), "utf8");
const shared = readFileSync(new URL("../components/legal-document.tsx", import.meta.url), "utf8");
const english = ["terms", "privacy", "terms/tacticsboard"].map(path => readFileSync(new URL(`../app/en/${path}/page.tsx`, import.meta.url), "utf8"));

test("legal pages are public and published, with no draft notice", () => {
  assert.match(terms, /Användarvillkor/);
  assert.match(privacy, /Integritetspolicy/);
  assert.doesNotMatch(shared, /utkast/i);
  assert.doesNotMatch(terms + privacy, /draft/);
  assert.match(terms, /robots: \{ index: false, follow: false \}/);
  assert.match(privacy, /robots: \{ index: false, follow: false \}/);
});

test("legal placeholders cover core technical acceptance topics", () => {
  for (const source of [terms, privacy]) {
    assert.doesNotMatch(source, /PLACEHOLDER|placeholder/);
    assert.match(source, /minderår|Barns personuppgifter/);
    assert.match(source, /Kontakt/);
  }
  assert.match(privacy, /Dina rättigheter/);
  assert.match(privacy, /Lagring och radering/);
  assert.match(terms, /Tillåten användning/);
  assert.match(terms, /Avstängning och avslut/);
});

test("each English legal page says the Swedish text applies, by way of the shared document", () => {
  assert.match(shared, /This is a translation/);
  for (const source of english) {
    assert.match(source, /locale="en"/);
    assert.match(source, /counterpart="\/(villkor|integritet)/);
    assert.match(source, /robots: \{ index: false, follow: false \}/);
  }
});
