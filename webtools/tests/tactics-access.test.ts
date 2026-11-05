import assert from "node:assert/strict";
import { test } from "node:test";
import {
  accessNote,
  billingErrorText,
  daysLeft,
  isLockedError,
  launchOfferOpen,
  lockedText,
  subscriptionSummary,
  type TacticsAccess,
} from "../lib/tactics/access.ts";

const now = Date.parse("2026-11-03T12:00:00Z");
const base: TacticsAccess = {
  access_mode: "write", source: "trial", trial_available: false, trial_ends_at: "2026-11-10T12:00:00Z",
  subscription_state: null, billing_interval: null, current_period_ends_at: null, cancel_at_period_end: false, grace_ends_at: null,
};

test("the trial's days are rounded up, and the last day says so", () => {
  assert.equal(daysLeft("2026-11-10T12:00:00Z", now), 7);
  assert.equal(daysLeft("2026-11-04T13:00:00Z", now), 2);
  assert.equal(daysLeft("2026-11-01T12:00:00Z", now), 0);
  assert.equal(daysLeft(null, now), 0);
  assert.equal(accessNote(base, now), "7 dagar kvar av provperioden.");
  assert.equal(accessNote({ ...base, trial_ends_at: "2026-11-03T20:00:00Z" }, now), "Sista dagen av provperioden.");
});

test("a failed payment and a cancellation are explained, a running subscription is not", () => {
  const grace = { ...base, source: "grace" as const, subscription_state: "grace" as const, grace_ends_at: "2026-11-17T12:00:00Z" };
  assert.match(accessNote(grace, now), /^Betalningen gick inte igenom\. Uppdatera kortet senast 17 november/);
  const cancelled = { ...base, source: "subscription" as const, subscription_state: "active" as const,
    cancel_at_period_end: true, current_period_ends_at: "2026-12-03T12:00:00Z" };
  assert.equal(accessNote(cancelled, now), "Prenumerationen avslutas 3 december.");
  assert.equal(accessNote({ ...cancelled, cancel_at_period_end: false }, now), "");
});

test("the locked page says why", () => {
  const locked = { ...base, access_mode: "denied" as const, source: "none" as const };
  assert.equal(lockedText(locked).title, "Provperioden är slut");
  assert.match(lockedText(locked).text, /finns kvar/);
  assert.equal(lockedText({ ...locked, subscription_state: "ended" }).title, "Prenumerationen har upphört");
  assert.equal(lockedText({ ...locked, trial_ends_at: null }).title, "Prenumerera på Tacticsboard");
});

test("the launch offer ends with 2026", () => {
  assert.equal(launchOfferOpen(new Date("2026-12-31T22:59:00Z")), true);
  assert.equal(launchOfferOpen(new Date("2026-12-31T23:00:00Z")), false);
});

test("the account page: subscription, cancelled, failed payment, trial, never tried, ended", () => {
  const paid = { ...base, source: "subscription" as const, subscription_state: "active" as const,
    billing_interval: "month" as const, current_period_ends_at: "2026-11-10T16:52:11Z" };
  assert.deepEqual(subscriptionSummary(paid, now),
    { lines: ["Månadsabonnemang, 39 kr/mån.", "Nästa betalning 10 november."], subscribe: false, manage: "manage", tryIt: false });
  assert.deepEqual(subscriptionSummary({ ...paid, billing_interval: "year", cancel_at_period_end: true }, now).lines,
    ["Årsabonnemang, 390 kr/år.", "Uppsagt. Gäller till och med 10 november."]);
  const grace = subscriptionSummary({ ...paid, source: "grace", subscription_state: "grace", grace_ends_at: "2026-11-17T12:00:00Z" }, now);
  assert.equal(grace.manage, "card");
  assert.match(grace.lines[0], /Betalningen gick inte igenom/);
  const trial = subscriptionSummary(base, now);
  assert.deepEqual([trial.subscribe, trial.manage], [true, null]);
  assert.equal(trial.lines[0], "Provperiod (till och med 10 november). 7 dagar kvar av provperioden.");
  const fresh = { ...base, access_mode: "denied" as const, source: "none" as const, trial_available: true, trial_ends_at: null };
  assert.deepEqual([subscriptionSummary(fresh, now).tryIt, subscriptionSummary(fresh, now).subscribe], [true, false]);
  const ended = subscriptionSummary({ ...fresh, trial_available: false, subscription_state: "ended" }, now);
  assert.deepEqual([ended.subscribe, ended.manage, ended.lines[0]], [true, "manage", "Prenumerationen har upphört. Dina projekt finns kvar."]);
  const trialOver = subscriptionSummary({ ...fresh, trial_available: false, trial_ends_at: "2026-11-01T12:00:00Z" }, now);
  assert.deepEqual([trialOver.subscribe, trialOver.manage], [true, null]);
});

test("errors", () => {
  assert.equal(isLockedError("tacticsboard_locked"), true);
  assert.equal(isLockedError("not_found"), false);
  assert.equal(isLockedError(undefined), false);
  assert.match(billingErrorText("already_subscribed"), /redan/);
  assert.match(billingErrorText("billing_unavailable"), /just nu/);
});
