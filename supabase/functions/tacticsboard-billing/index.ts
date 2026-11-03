// Tacticsboard sold per person (plan item 7): starts Stripe Checkout for
// webtool.tacticsboard, or opens the Customer Portal, for the signed-in
// person. Prices, coupon and customer come from the database, never from
// the request.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import Stripe from "npm:stripe@22.0.0";
import { billingRuntimeEnabled, json } from "../_shared/billing_http.ts";
import { allowedWebOrigins } from "../_shared/sign_in_limits.ts";
import {
  checkoutSessionParams,
  type ClaimedCheckout,
  parseTacticsboardBillingRequest,
  stripeKeyIsLive,
  tacticsboardProductionOrigins,
} from "../_shared/tacticsboard_billing.ts";
import {
  correlationId,
  recordCriticalFlowOutcome,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";

const origins = allowedWebOrigins(
  Deno.env.get("TEAMZONE_EXTRA_WEB_ORIGINS"),
  tacticsboardProductionOrigins,
);

function cors(origin: string): Record<string, string> {
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers":
      "authorization, apikey, content-type, x-client-info",
    "vary": "Origin",
  };
}

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const respond = (response: Response) => withCorrelation(response, requestId);
  const origin = request.headers.get("origin");
  if (!origin || !origins.has(origin)) {
    return respond(json(403, { error: "not_allowed" }));
  }
  const headers = cors(origin);
  if (request.method === "OPTIONS") {
    return respond(new Response(null, { status: 204, headers }));
  }
  if (request.method !== "POST") {
    return respond(json(405, { error: "method_not_allowed" }, headers));
  }
  const unavailable = () =>
    respond(json(503, { error: "billing_unavailable" }, headers));
  if (!billingRuntimeEnabled()) return unavailable();

  const url = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    Deno.env.get("SUPABASE_ANON_KEY");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const databaseSecret = secretKeys.default ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  const livemode = stripeKeyIsLive(stripeKey);
  const authorization = request.headers.get("authorization");
  if (
    !url || !publishableKey || !databaseSecret || livemode === null ||
    !authorization
  ) return unavailable();

  let body;
  try {
    body = parseTacticsboardBillingRequest(await request.json());
  } catch {
    body = null;
  }
  if (!body) return respond(json(400, { error: "invalid_request" }, headers));

  const admin = createClient(url, databaseSecret, {
    auth: { persistSession: false },
  });
  const client = createClient(url, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: user } = await client.auth.getUser(
    authorization.replace(/^Bearer\s+/i, ""),
  );
  if (!user?.user || user.user.is_anonymous) {
    return respond(json(401, { error: "not_signed_in" }, headers));
  }
  const stripe = new Stripe(stripeKey);
  const flow = "checkout";
  const step = body.action === "checkout"
    ? "tacticsboard_checkout"
    : "tacticsboard_portal";

  try {
    if (body.action === "portal") {
      const { data: customer } = await admin.schema("api").rpc(
        "tacticsboard_billing_customer",
        {
          target_profile_id: user.user.id,
          target_livemode: livemode,
        },
      );
      if (typeof customer !== "string") {
        return respond(json(404, { error: "no_customer" }, headers));
      }
      const session = await stripe.billingPortal.sessions.create({
        customer,
        return_url: `${origin}/konto`,
        locale: "sv",
      });
      await recordCriticalFlowOutcome(admin, flow, "succeeded", requestId);
      return respond(json(200, { url: session.url }, headers));
    }

    const { data: prepared, error } = await client.schema("api").rpc(
      "prepare_tacticsboard_checkout",
      {
        target_interval: body.interval,
        idempotency_key: body.idempotencyKey,
      },
    );
    if (error?.message === "already_subscribed") {
      return respond(json(409, { error: "already_subscribed" }, headers));
    }
    if (error || !prepared?.checkout_request_id) {
      throw new Error("prepare_failed");
    }
    const { data: claimed, error: claimError } = await admin.schema("api").rpc(
      "claim_tacticsboard_checkout",
      {
        target_checkout_request_id: prepared.checkout_request_id,
        target_livemode: livemode,
      },
    );
    if (claimError || !claimed?.provider_price_ref) {
      throw new Error("claim_failed");
    }
    const session = await stripe.checkout.sessions.create(
      checkoutSessionParams(
        claimed as ClaimedCheckout,
        origin,
        user.user.email ?? null,
      ) as Parameters<typeof stripe.checkout.sessions.create>[0],
      { idempotencyKey: body.idempotencyKey },
    );
    if (!session.url) throw new Error("no_session_url");
    await recordCriticalFlowOutcome(admin, flow, "succeeded", requestId);
    return respond(json(200, { url: session.url }, headers));
  } catch (error) {
    await recordCriticalFlowOutcome(admin, flow, "failed", requestId);
    // Our own errors carry a short code; Stripe's are logged by type only.
    sanitizedLog(`${step}.failed`, "error", requestId, {
      component: "billing",
      error_type: !(error instanceof Error)
        ? "unknown"
        : error.name === "Error"
        ? error.message
        : error.name,
    });
    return unavailable();
  }
});
