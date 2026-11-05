import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  checkoutSessionParams,
  isTacticsboardEvent,
  parseTacticsboardBillingRequest,
  remainingTrialEnd,
  stripeKeyIsLive,
} from "../_shared/tacticsboard_billing.ts";

const key = "a1500000-0000-4000-8000-000000000001";
const now = Date.parse("2026-11-03T12:00:00Z");
const claimed = {
  checkout_request_id: "c1500000-0000-4000-8000-000000000001",
  profile_id: "p1500000-0000-4000-8000-000000000001",
  provider_price_ref: "price_month",
  provider_coupon_ref: null,
  provider_customer_ref: null,
  trial_ends_at: null,
};

Deno.test("accepts only checkout with an interval and a key, or the portal", () => {
  assertEquals(
    parseTacticsboardBillingRequest({
      action: "checkout",
      interval: "year",
      idempotencyKey: key,
    }),
    { action: "checkout", interval: "year", idempotencyKey: key },
  );
  assertEquals(parseTacticsboardBillingRequest({ action: "portal" }), {
    action: "portal",
  });
  assertEquals(
    parseTacticsboardBillingRequest({ action: "portal", customer: "cus_1" }),
    null,
  );
  assertEquals(
    parseTacticsboardBillingRequest({
      action: "checkout",
      interval: "week",
      idempotencyKey: key,
    }),
    null,
  );
  assertEquals(
    parseTacticsboardBillingRequest({
      action: "checkout",
      interval: "month",
      idempotencyKey: key,
      price: "price_x",
    }),
    null,
  );
  assertEquals(
    parseTacticsboardBillingRequest({
      action: "checkout",
      interval: "month",
      idempotencyKey: "retry",
    }),
    null,
  );
  assertEquals(parseTacticsboardBillingRequest(null), null);
});

Deno.test("the Stripe key decides live or test", () => {
  assertEquals(stripeKeyIsLive("sk_live_abc"), true);
  assertEquals(stripeKeyIsLive("rk_live_abc"), true);
  assertEquals(stripeKeyIsLive("sk_test_abc"), false);
  assertEquals(stripeKeyIsLive(""), null);
  assertEquals(stripeKeyIsLive("pk_live_abc"), null);
});

Deno.test("only events with Tacticsboard's metadata go to the personal flow", () => {
  assertEquals(
    isTacticsboardEvent({
      data: {
        object: { metadata: { teamzone_product: "webtool.tacticsboard" } },
      },
    }),
    true,
  );
  assertEquals(
    isTacticsboardEvent({ data: { object: { metadata: {} } } }),
    false,
  );
  assertEquals(isTacticsboardEvent({ data: { object: {} } }), false);
  assertEquals(isTacticsboardEvent({}), false);
});

Deno.test("the rest of the trial carries over only when Stripe accepts it", () => {
  assertEquals(
    remainingTrialEnd("2026-11-08T12:00:00Z", now),
    Date.parse("2026-11-08T12:00:00Z") / 1000,
  );
  assertEquals(remainingTrialEnd("2026-11-05T11:00:00Z", now), null);
  assertEquals(remainingTrialEnd(null, now), null);
});

Deno.test("checkout: a new customer, tax, Swedish, metadata on both", () => {
  const params = checkoutSessionParams(
    claimed,
    "https://webtools.teamzoneapp.se",
    "a@b.se",
    now,
  );
  assertEquals(params.customer_email, "a@b.se");
  assertEquals(params.customer, undefined);
  assertEquals(params.discounts, undefined);
  assertEquals(
    params.success_url,
    "https://webtools.teamzoneapp.se/konto?betalning=klar",
  );
  assertEquals(params.automatic_tax, { enabled: true });
  assertEquals(params.locale, "sv");
  assertEquals(params.client_reference_id, claimed.checkout_request_id);
  const metadata = {
    teamzone_product: "webtool.tacticsboard",
    checkout_request_id: claimed.checkout_request_id,
  };
  assertEquals(params.metadata, metadata);
  assertEquals(params.subscription_data, { metadata });
});

Deno.test("billing: English is stated, Swedish is the plain request", () => {
  assertEquals(parseTacticsboardBillingRequest({ action: "portal", locale: "en" }), {
    action: "portal",
    locale: "en",
  });
  assertEquals(parseTacticsboardBillingRequest({ action: "portal", locale: "de" }), null);
  assertEquals(
    parseTacticsboardBillingRequest({ action: "withdraw", name: "Kim", locale: "en" }),
    { action: "withdraw", name: "Kim", locale: "en" },
  );
});

Deno.test("checkout: in English, with the terms in English", () => {
  const params = checkoutSessionParams(claimed, "https://webtools.teamzoneapp.se", null, now, "en");
  assertEquals(params.locale, "en-GB");
  const message = (params.custom_text as {
    terms_of_service_acceptance: { message: string };
  }).terms_of_service_acceptance.message;
  assertEquals(message.includes("/en/terms/tacticsboard"), true);
  assertEquals(message.includes("start at once"), true);
  assertEquals(message.length <= 1200, true);
});

Deno.test("checkout: the terms and the consent to start at once are required", () => {
  const params = checkoutSessionParams(claimed, "https://webtools.teamzoneapp.se", null, now);
  assertEquals(params.consent_collection, { terms_of_service: "required" });
  const message = (params.custom_text as {
    terms_of_service_acceptance: { message: string };
  }).terms_of_service_acceptance.message;
  assertEquals(message.includes("https://public.teamzoneapp.se/villkor/tacticsboard"), true);
  assertEquals(message.includes("börjar direkt"), true);
  assertEquals(message.length <= 1200, true);
});

Deno.test("checkout: a known customer, the launch coupon and the rest of the trial", () => {
  const params = checkoutSessionParams(
    {
      ...claimed,
      provider_coupon_ref: "launch50",
      provider_customer_ref: "cus_1",
      trial_ends_at: "2026-11-08T12:00:00Z",
    },
    "https://webtools.teamzoneapp.se",
    "a@b.se",
    now,
  );
  assertEquals(params.customer, "cus_1");
  assertEquals(params.customer_email, undefined);
  assertEquals(params.discounts, [{ coupon: "launch50" }]);
  assertEquals(
    (params.subscription_data as { trial_end: number }).trial_end,
    Date.parse("2026-11-08T12:00:00Z") / 1000,
  );
});
