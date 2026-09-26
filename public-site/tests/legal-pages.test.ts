import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const terms = readFileSync(new URL("../app/villkor/page.tsx", import.meta.url), "utf8");
const privacy = readFileSync(new URL("../app/integritet/page.tsx", import.meta.url), "utf8");
const shared = readFileSync(new URL("../components/legal-document.tsx", import.meta.url), "utf8");

test("legal placeholders are public pages with explicit draft disclosure", () => {
  assert.match(terms, /Användarvillkor/);
  assert.match(privacy, /Integritetspolicy/);
  assert.match(shared, /Juridiskt utkast för teknisk testning/);
  assert.match(terms, /robots: \{ index: false, follow: false \}/);
  assert.match(privacy, /robots: \{ index: false, follow: false \}/);
});

test("legal placeholders cover core technical acceptance topics", () => {
  for (const source of [terms, privacy]) {
    assert.match(source, /\[PLACEHOLDER:/);
    assert.match(source, /minderår|Barns personuppgifter/);
    assert.match(source, /Kontakt/);
  }
  assert.match(privacy, /Dina rättigheter/);
  assert.match(privacy, /Lagring och radering/);
  assert.match(terms, /Tillåten användning/);
  assert.match(terms, /Avstängning och avslut/);
});
