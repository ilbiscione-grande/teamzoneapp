import { assertEquals } from "jsr:@std/assert@1.0.14";
import { parseTacticsboardBillingRequest } from "../_shared/tacticsboard_billing.ts";
import {
  latestPurchase,
  parseWithdrawalName,
  purchaseInterval,
  withdrawalLastDay,
  withdrawalOpen,
  withdrawalReceipt,
  withdrawalSupportMail,
} from "../_shared/tacticsboard_withdrawal.ts";

const seconds = (value: string) => Date.parse(value) / 1000;
const purchased = seconds("2026-11-05T06:34:16Z");

Deno.test("withdrawal: the deadline is 14 days after the day of purchase", () => {
  assertEquals(withdrawalLastDay(purchased), "2026-11-19");
  // Just before midnight in Sweden is still the same day, also past UTC.
  assertEquals(withdrawalLastDay(seconds("2026-11-05T22:59:00Z")), "2026-11-19");
  assertEquals(withdrawalLastDay(seconds("2026-11-05T23:01:00Z")), "2026-11-20");
  assertEquals(withdrawalOpen(purchased, Date.parse("2026-11-19T22:59:00Z")), true);
  assertEquals(withdrawalOpen(purchased, Date.parse("2026-11-19T23:01:00Z")), false);
});

Deno.test("withdrawal: the latest purchase of Tacticsboard only", () => {
  const metadata = { teamzone_product: "webtool.tacticsboard" };
  const old = { id: "sub_old", status: "canceled", start_date: 1, metadata };
  const latest = { id: "sub_new", status: "active", start_date: 3, metadata };
  const other = { id: "sub_other", status: "active", start_date: 5, metadata: {} };
  const failed = { id: "sub_x", status: "incomplete_expired", start_date: 4, metadata };
  assertEquals(latestPurchase([old, latest, other, failed])?.id, "sub_new");
  assertEquals(latestPurchase([other]), null);
});

Deno.test("withdrawal: the interval comes from the price", () => {
  const item = (interval: string) => ({
    id: "sub_1",
    status: "active",
    start_date: 1,
    items: { data: [{ price: { recurring: { interval } } }] },
  });
  assertEquals(purchaseInterval(item("year")), "year");
  assertEquals(purchaseInterval(item("week")), null);
});

Deno.test("withdrawal: the request", () => {
  assertEquals(parseTacticsboardBillingRequest({ action: "withdrawal_status" }), {
    action: "withdrawal_status",
  });
  assertEquals(
    parseTacticsboardBillingRequest({ action: "withdraw", name: " Anna A " }),
    { action: "withdraw", name: "Anna A" },
  );
  assertEquals(parseTacticsboardBillingRequest({ action: "withdraw", name: " " }), null);
  assertEquals(parseTacticsboardBillingRequest({ action: "withdraw" }), null);
  assertEquals(
    parseTacticsboardBillingRequest({ action: "withdraw", name: "A", amount: 1 }),
    null,
  );
  assertEquals(parseWithdrawalName("x".repeat(201)), null);
});

const item = {
  name: "Anna A",
  email: "a@b.se",
  receivedAt: "2026-11-06T09:00:00Z",
  purchasedAtSeconds: purchased,
  interval: "year" as const,
};

Deno.test("withdrawal: the receipt says when, what and what happens next", () => {
  const { text } = withdrawalReceipt(item);
  assertEquals(text.includes("6 november 2026"), true);
  assertEquals(text.includes("10:00"), true);
  assertEquals(text.includes("årsprenumeration, köpt 2026-11-05"), true);
  assertEquals(text.includes("Vi avslutar prenumerationen"), true);
});

Deno.test("withdrawal: support is told when Stripe must be done by hand", () => {
  const mail = {
    ...item,
    subscriptionRef: "sub_1",
    subscriptionStatus: "active",
    cancelled: true,
    paidPeriodStartSeconds: purchased,
  };
  assertEquals(withdrawalSupportMail(mail).subject.includes("AVSLUTA"), false);
  assertEquals(
    withdrawalSupportMail({ ...mail, cancelled: false }).subject.includes("AVSLUTA"),
    true,
  );
  assertEquals(
    withdrawalSupportMail({ ...mail, subscriptionStatus: "trialing", paidPeriodStartSeconds: null })
      .text.includes("inget har dragits"),
    true,
  );
});
