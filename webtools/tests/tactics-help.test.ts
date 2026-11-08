import assert from "node:assert/strict";
import { test } from "node:test";
import { questionGroups } from "../lib/tactics/help/faq.ts";
import { guides } from "../lib/tactics/help/guides.ts";
import type { Text } from "../lib/tactics/help/model.ts";

const texts: Text[] = [
  ...questionGroups.flatMap(group => [group.title, ...group.questions.flatMap(item => [item.q, ...item.a])]),
  ...guides.flatMap(guide => [guide.title, guide.summary, ...guide.sections.flatMap(section => [section.title, section.text, section.tip, ...(section.steps ?? [])].filter((part): part is Text => !!part))]),
];

test("every help text is there in Swedish and in English", () => {
  for (const text of texts) {
    assert.ok(text.sv.trim() && text.en.trim(), `missing a language: ${JSON.stringify(text)}`);
    // A word or two may be the same in both (Frames, 3D); a sentence is not.
    if (text.sv.split(" ").length > 2) assert.notEqual(text.sv, text.en, `not translated: ${text.sv}`);
  }
});

test("the support address shows in both languages or neither", () => {
  for (const text of texts) assert.equal(text.sv.includes("{email}"), text.en.includes("{email}"), text.sv);
});

test("guides and questions have their own addresses", () => {
  const slugs = guides.map(guide => guide.slug);
  assert.equal(new Set(slugs).size, slugs.length);
  assert.ok(slugs.every(slug => /^[a-z0-9-]+$/.test(slug)));
  const ids = questionGroups.flatMap(group => group.questions.map(item => item.id));
  assert.equal(new Set(ids).size, ids.length);
});
