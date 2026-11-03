import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { accountDeletionErrorText, deletionWord } from "../lib/account.ts";

test("the confirmation word is the one the function expects", () => {
  const fn = readFileSync(new URL("../../supabase/functions/account-deletion/index.ts", import.meta.url), "utf8");
  assert.match(fn, new RegExp(`confirmation = "${deletionWord}"`));
});

test("each refusal explains what to do", () => {
  assert.match(accountDeletionErrorText("club_linked"), /TeamZone-appen/);
  assert.match(accountDeletionErrorText("needs_support"), /support@teamzoneapp\.se/);
  assert.match(accountDeletionErrorText("billing_cancel_failed"), /Inget är borttaget/);
  assert.match(accountDeletionErrorText("unavailable"), /just nu/);
});
