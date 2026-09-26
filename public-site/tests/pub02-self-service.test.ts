import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const catalog = readFileSync(new URL("../app/klubbar/page.tsx", import.meta.url), "utf8");
const migration = readFileSync(new URL("../../supabase/migrations/20260925104508_pub02_self_service_club_team_pages.sql", import.meta.url), "utf8");

test("catalog distinguishes unofficial and verified clubs without linking listed-only entries", () => {
  assert.match(catalog, /Inofficiell klubb/);
  assert.match(catalog, /Officiellt verifierad klubb/);
  assert.match(catalog, /club\.visibility === "published"/);
  assert.match(migration, /where visibility in\('listed','published'\)/);
  assert.doesNotMatch(migration, /where visibility in\('listed','published'\) and official/);
});
