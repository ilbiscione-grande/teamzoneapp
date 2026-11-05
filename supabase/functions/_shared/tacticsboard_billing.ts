// Tacticsboard sold per person (plan item 7): the request, the origins and
// the Stripe Checkout parameters, kept free of I/O so they can be tested.

export const tacticsboardProduct = "webtool.tacticsboard";

/// Webtools in production. The test project adds its hosted address and
/// local origins through TEAMZONE_EXTRA_WEB_ORIGINS.
export const tacticsboardProductionOrigins = [
  "https://webtools.teamzoneapp.se",
];

export type TacticsboardBillingRequest =
  | { action: "checkout"; interval: "month" | "year"; idempotencyKey: string }
  | { action: "portal" }
  | { action: "withdrawal_status" }
  | { action: "withdraw"; name: string };

const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type BillingLocale = "sv" | "en";

/// Only English is stated; Swedish stays the request it has always been.
export function parseTacticsboardBillingRequest(
  value: unknown,
): (TacticsboardBillingRequest & { locale?: "en" }) | null {
  if (!value || typeof value !== "object") return null;
  const { locale, ...rest } = value as Record<string, unknown>;
  if (locale !== undefined && locale !== "en") return null;
  const request = parseRequest(rest);
  return request && locale ? { ...request, locale } : request;
}

function parseRequest(
  body: Record<string, unknown>,
): TacticsboardBillingRequest | null {
  const keys = Object.keys(body).sort().join(",");
  if (body.action === "portal" || body.action === "withdrawal_status") {
    return keys === "action" ? { action: body.action } : null;
  }
  if (body.action === "withdraw") {
    const name = typeof body.name === "string" ? body.name.trim() : "";
    return keys === "action,name" && name.length >= 1 && name.length <= 200
      ? { action: "withdraw", name }
      : null;
  }
  if (body.action !== "checkout" || keys !== "action,idempotencyKey,interval") {
    return null;
  }
  if (
    (body.interval !== "month" && body.interval !== "year") ||
    typeof body.idempotencyKey !== "string" || !uuid.test(body.idempotencyKey)
  ) return null;
  return {
    action: "checkout",
    interval: body.interval,
    idempotencyKey: body.idempotencyKey,
  };
}

/// Live or test follows the Stripe key, so a test key never meets live prices.
export function stripeKeyIsLive(key: string): boolean | null {
  if (/^(sk|rk)_live_/.test(key)) return true;
  if (/^(sk|rk)_test_/.test(key)) return false;
  return null;
}

/// An event belongs to Tacticsboard when our checkout put the product in
/// its metadata (the session and the subscription both carry it).
export function isTacticsboardEvent(
  event: { data?: { object?: unknown } },
): boolean {
  const object = event.data?.object as
    | { metadata?: Record<string, unknown> }
    | undefined;
  return object?.metadata?.teamzone_product === tacticsboardProduct;
}

export type ClaimedCheckout = {
  checkout_request_id: string;
  profile_id: string;
  provider_price_ref: string;
  provider_coupon_ref: string | null;
  provider_customer_ref: string | null;
  trial_ends_at: string | null;
};

/// Stripe needs a trial end at least 48 hours ahead; a shorter rest of the
/// trial is dropped and the first payment is taken at once.
export function remainingTrialEnd(
  trialEndsAt: string | null,
  now = Date.now(),
): number | null {
  if (!trialEndsAt) return null;
  const end = Math.floor(Date.parse(trialEndsAt) / 1000);
  return Number.isFinite(end) && end * 1000 - now > 48 * 3600 * 1000
    ? end
    : null;
}

export const tacticsboardTermsUrl =
  "https://public.teamzoneapp.se/villkor/tacticsboard";
/// The English translation of the terms; published in step 8 of the plan.
export const tacticsboardTermsUrlEnglish =
  "https://public.teamzoneapp.se/en/terms/tacticsboard";

/// As Stripe names the languages of Checkout and the Customer Portal.
export const stripeLocale = (locale: BillingLocale) =>
  locale === "en" ? "en-GB" : "sv";

/// The required box in Checkout: the terms, and the consent to start at once
/// that the right of withdrawal asks for. Stripe also needs a terms URL
/// under its public business details.
export const tacticsboardConsentText =
  `Jag godkänner [villkoren för Tacticsboard](${tacticsboardTermsUrl}) och vill att prenumerationen börjar direkt. Jag kan ångra köpet inom 14 dagar med knappen Ångra köpet på kontosidan och betalar då en proportionell del av priset för den betalda tiden.`;
export const tacticsboardConsentTextEnglish =
  `I accept the [terms for Tacticsboard](${tacticsboardTermsUrlEnglish}) and want the subscription to start at once. I can withdraw from the purchase within 14 days with the Withdraw from the purchase button on the account page, and then pay a proportionate part of the price for the time paid for.`;

export function checkoutSessionParams(
  claimed: ClaimedCheckout,
  origin: string,
  email: string | null,
  now = Date.now(),
  locale: BillingLocale = "sv",
): Record<string, unknown> {
  const metadata = {
    teamzone_product: tacticsboardProduct,
    checkout_request_id: claimed.checkout_request_id,
  };
  const trialEnd = remainingTrialEnd(claimed.trial_ends_at, now);
  return {
    mode: "subscription",
    line_items: [{ price: claimed.provider_price_ref, quantity: 1 }],
    success_url: `${origin}/konto?betalning=klar`,
    cancel_url: `${origin}/konto?betalning=avbruten`,
    client_reference_id: claimed.checkout_request_id,
    locale: stripeLocale(locale),
    automatic_tax: { enabled: true },
    tax_id_collection: { enabled: true },
    billing_address_collection: "required",
    consent_collection: { terms_of_service: "required" },
    custom_text: {
      terms_of_service_acceptance: {
        message: locale === "en"
          ? tacticsboardConsentTextEnglish
          : tacticsboardConsentText,
      },
    },
    metadata,
    subscription_data: {
      metadata,
      ...(trialEnd ? { trial_end: trialEnd } : {}),
    },
    ...(claimed.provider_coupon_ref
      ? { discounts: [{ coupon: claimed.provider_coupon_ref }] }
      : {}),
    ...(claimed.provider_customer_ref
      ? {
        customer: claimed.provider_customer_ref,
        customer_update: { address: "auto", name: "auto" },
      }
      : email
      ? { customer_email: email }
      : {}),
  };
}
