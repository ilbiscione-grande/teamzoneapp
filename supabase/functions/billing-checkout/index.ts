import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import Stripe from "npm:stripe@22.0.0";
import {
  billingCorsHeaders,
  billingRuntimeEnabled,
  exactWebOrigin,
  json,
} from "../_shared/billing_http.ts";
import { parseCheckoutRequest } from "../_shared/billing_contract.ts";
import {
  correlationId,
  recordCriticalFlowOutcome,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const respond = (response: Response) => withCorrelation(response, requestId);
  const origin = exactWebOrigin();
  const requestOrigin = request.headers.get("origin");
  if (!origin || requestOrigin !== origin) {
    return respond(json(403, { error: "not_allowed" }));
  }
  const cors = billingCorsHeaders(origin);
  if (request.method === "OPTIONS") {
    return respond(new Response(null, { status: 204, headers: cors }));
  }
  if (request.method !== "POST") {
    return respond(json(405, { error: "method_not_allowed" }, cors));
  }
  if (!billingRuntimeEnabled()) {
    return respond(json(503, { error: "billing_unavailable" }, cors));
  }

  const url = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    Deno.env.get("SUPABASE_ANON_KEY");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const databaseSecret = secretKeys.default ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const secretKey = Deno.env.get("STRIPE_SECRET_KEY");
  const authorization = request.headers.get("authorization");
  if (
    !url || !publishableKey || !databaseSecret || !secretKey || !authorization
  ) return respond(json(503, { error: "billing_unavailable" }, cors));
  const admin = createClient(url, databaseSecret, {
    auth: { persistSession: false },
  });

  let rawBody: unknown;
  try {
    rawBody = await request.json();
  } catch {
    return respond(json(400, { error: "invalid_request" }, cors));
  }
  const body = parseCheckoutRequest(rawBody);
  if (!body) return respond(json(400, { error: "invalid_request" }, cors));

  const client = createClient(url, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: prepared, error } = await client.schema("api").rpc(
    "prepare_billing_checkout",
    {
      target_club_id: body.clubId,
      target_plan_key: body.planKey,
      target_interval: body.interval,
      idempotency_key: body.idempotencyKey,
    },
  );
  if (error || !prepared?.checkout_request_id) {
    await recordCriticalFlowOutcome(admin, "checkout", "failed", requestId);
    return respond(json(503, { error: "billing_unavailable" }, cors));
  }

  const { data: claimed, error: claimError } = await admin.schema("api").rpc(
    "claim_billing_checkout",
    {
      target_checkout_request_id: prepared.checkout_request_id,
    },
  );
  if (claimError || !claimed?.provider_price_ref) {
    await recordCriticalFlowOutcome(admin, "checkout", "failed", requestId);
    return respond(json(503, { error: "billing_unavailable" }, cors));
  }

  try {
    const stripe = new Stripe(secretKey);
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: claimed.provider_price_ref, quantity: 1 }],
      success_url: `${origin}/billing?result=success`,
      cancel_url: `${origin}/billing?result=cancelled`,
      client_reference_id: prepared.checkout_request_id,
      subscription_data: {
        metadata: { checkout_request_id: prepared.checkout_request_id },
      },
    }, { idempotencyKey: body.idempotencyKey });
    if (!session.url) {
      await recordCriticalFlowOutcome(admin, "checkout", "failed", requestId);
      return respond(json(503, { error: "billing_unavailable" }, cors));
    }
    await recordCriticalFlowOutcome(admin, "checkout", "succeeded", requestId);
    sanitizedLog("checkout.created", "info", requestId, {
      component: "billing",
      result: "created",
    });
    return respond(json(200, { checkoutUrl: session.url }, cors));
  } catch (error) {
    await recordCriticalFlowOutcome(admin, "checkout", "failed", requestId);
    sanitizedLog("checkout.failed", "error", requestId, {
      component: "billing",
      operation: "provider_create",
      error_type: error instanceof Error ? error.name : "unknown",
    });
    return respond(json(503, { error: "billing_unavailable" }, cors));
  }
});
