import assert from "node:assert/strict";
import test from "node:test";
import { withdrawalFacts, withdrawalReceivedText } from "../lib/tactics/withdrawal.ts";

test("the purchase and the last day are named", () => {
  const text = withdrawalFacts({
    state: "open", interval: "year", purchased_at: "2026-11-05T06:34:16Z", last_day: "2026-11-19", email: "a@b.se",
  });
  assert.equal(text, "Årsprenumeration på Tacticsboard, köpt 5 november 2026. Du kan ångra köpet till och med 19 november 2026.");
});

test("the time received is shown, with or without the mail", () => {
  const received = { state: "received", received_at: "2026-11-05T09:00:00Z" } as const;
  assert.match(withdrawalReceivedText({ ...received, receipt_sent: true }), /5 november 2026.*10:00.*skickat/);
  assert.match(withdrawalReceivedText({ ...received, receipt_sent: false }), /spara den här texten/);
});
