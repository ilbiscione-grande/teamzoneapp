import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import Stripe from "npm:stripe@22.0.0";
import { billingRuntimeEnabled, json } from "../_shared/billing_http.ts";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const respond = (response: Response) => withCorrelation(response, requestId);
  if (request.method !== "POST") {
    return respond(json(405, { error: "method_not_allowed" }));
  }
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SIGNING_SECRET");
  const signature = request.headers.get("stripe-signature");
  if (!stripeKey || !webhookSecret || !signature) {
    return respond(json(503, { error: "billing_unavailable" }));
  }

  const rawBody = await request.text();
  let event: Stripe.Event;
  try {
    const stripe = new Stripe(stripeKey);
    event = await stripe.webhooks.constructEventAsync(
      rawBody,
      signature,
      webhookSecret,
      undefined,
      Stripe.createSubtleCryptoProvider(),
    );
  } catch {
    sanitizedLog("webhook.rejected", "warning", requestId, {
      component: "stripe",
      result: "invalid_signature",
    });
    return respond(json(400, { error: "invalid_signature" }));
  }
  if (!billingRuntimeEnabled()) {
    return respond(json(503, { error: "billing_unavailable" }));
  }

  const url = Deno.env.get("SUPABASE_URL");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const secret = secretKeys.default ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) {
    return respond(json(503, { error: "billing_unavailable" }));
  }
  const client = createClient(url, secret, { auth: { persistSession: false } });
  const { error } = await client.schema("api").rpc("ingest_stripe_event", {
    provider_event_id: event.id,
    provider_created_at: event.created,
    event_type: event.type,
    livemode: event.livemode,
    payload: event,
  });
  if (error) {
    sanitizedLog("webhook.failed", "error", requestId, {
      component: "stripe",
      operation: "ingest",
      error_type: error.code ?? "database",
    });
    return respond(json(500, { error: "retry_required" }));
  }
  sanitizedLog("webhook.completed", "info", requestId, {
    component: "stripe",
    result: "accepted",
  });
  return respond(json(200, { received: true }));
});
