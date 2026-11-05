import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { english } from "../lib/i18n/en/index.ts";
import { browserLocale, localeCookieValue, pickLocale } from "../lib/i18n/locale.ts";
import { translator } from "../lib/i18n/translate.ts";

const root = new URL("..", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");

// Parts of Webtools that are done: no Swedish outside t() is allowed here.
const finished = ["components/shell.tsx", "components/welcome.tsx", "components/sign-in.tsx", "components/password.tsx",
  "components/account.tsx", "components/account-page.tsx", "components/account-deletion.tsx", "components/app-card.tsx",
  "app/page.tsx", "app/not-found.tsx", "app/logga-in/page.tsx", "app/konto/page.tsx",
  "components/tactics/TacticsProduct.tsx", "components/tactics/RequireTacticsboard.tsx", "components/tactics/TacticsboardSubscription.tsx",
  "components/tactics/WithdrawPurchase.tsx", "components/tactics/use-tacticsboard-access.ts", "app/tacticsboard/page.tsx"];

// Data shown through t(variable): its Swedish needs English too.
const shownAsData = ["lib/account.ts", "lib/tactics/access.ts", "lib/tactics/withdrawal.ts"];

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap(name => {
    if (name === "node_modules" || name === ".next" || name === "tests" || name === "en") return [];
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return sourceFiles(path);
    return /\.tsx?$/.test(name) ? [path] : [];
  });
}

test("the browser decides until the person has chosen", () => {
  assert.equal(browserLocale("sv-SE,sv;q=0.9,en;q=0.8"), "sv");
  assert.equal(browserLocale("en-GB,en;q=0.9,sv;q=0.8"), "en");
  assert.equal(browserLocale("de-DE,de;q=0.9,sv;q=0.5,en;q=0.7"), "en");
  assert.equal(browserLocale("de-DE"), "en");
  assert.equal(browserLocale(null), "en");
  assert.equal(pickLocale("sv", "en-GB", true), "sv");
  assert.equal(pickLocale("xx", "sv-SE", true), "sv");
});

test("while English is closed everyone gets Swedish", () => {
  assert.equal(pickLocale("en", "en-GB", false), "sv");
});

test("the choice is shared across the domain, and stays local on other hosts", () => {
  assert.match(localeCookieValue("en", "webtools.teamzoneapp.se"), /tz_lang=en;.*domain=\.teamzoneapp\.se/);
  assert.doesNotMatch(localeCookieValue("en", "localhost"), /domain/);
  assert.doesNotMatch(localeCookieValue("en", "teamzoneapp.se.example.com"), /domain/);
});

test("text is translated and values are filled in", () => {
  assert.equal(translator("sv")("Logga in"), "Logga in");
  assert.equal(translator("en")("Logga in"), "Sign in");
  assert.equal(translator("sv")("Hej {name}", { name: "Kim" }), "Hej Kim");
  assert.equal(translator("en")("Saknas {name}", { name: "Kim" }), "Saknas Kim");
  assert.equal(translator("en")("Hej {name}"), "Hej {name}");
});

test("every t() has its English, with the same values", () => {
  const texts = new Set<string>();
  for (const file of sourceFiles(root)) {
    for (const match of readFileSync(file, "utf8").matchAll(/\bt\(\s*"((?:[^"\\]|\\.)+)"/g)) texts.add(JSON.parse(`"${match[1]}"`));
  }
  assert.ok(texts.size > 0);
  assert.deepEqual([...texts].filter(text => !english[text]), []);
  const names = (text: string) => [...text.matchAll(/\{(\w+)\}/g)].map(match => match[1]).sort();
  for (const [swedish, translated] of Object.entries(english)) assert.deepEqual(names(translated), names(swedish), swedish);
});

test("texts shown from data have their English", () => {
  for (const file of shownAsData) {
    const code = readFileSync(join(root, file), "utf8").replace(/\/\/.*$/gm, "").replace(/\/\*[\s\S]*?\*\//g, "");
    const texts = [...code.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map(match => match[1]).filter(text => /[åäöÅÄÖ]/.test(text));
    assert.deepEqual(texts.filter(text => !english[text]), [], file);
  }
});

test("finished parts keep their Swedish inside t()", () => {
  for (const file of finished) {
    const code = readFileSync(join(root, file), "utf8")
      .replace(/\/\/.*$/gm, "")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/\bt\(\s*"(?:[^"\\]|\\.)*"/g, "");
    // A constant above the components, shown through t(variable), only needs its English.
    const start = Math.max(0, code.search(/^(export )?(default )?(async )?function /m));
    const constants = code.slice(0, start).replace(/"((?:[^"\\]|\\.)*)"/g, (whole, text: string) => english[text] ? '""' : whole);
    assert.deepEqual((constants + code.slice(start)).split("\n").filter(line => /[åäöÅÄÖ]/.test(line)), [], file);
  }
});
