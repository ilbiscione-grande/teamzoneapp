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
  | { action: "portal" };

const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseTacticsboardBillingRequest(
  value: unknown,
): TacticsboardBillingRequest | null {
  if (!value || typeof value !== "object") return null;
  const body = value as Record<string, unknown>;
  const keys = Object.keys(body).sort().join(",");
  if (body.action === "portal") {
    return keys === "action" ? { action: "portal" } : null;
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

export function checkoutSessionParams(
  claimed: ClaimedCheckout,
  origin: string,
  email: string | null,
  now = Date.now(),
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
    locale: "sv",
    automatic_tax: { enabled: true },
    tax_id_collection: { enabled: true },
    billing_address_collection: "required",
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
