// Ending one's own account from Webtools (plan item 9): checks that the
// erasure will go through (a dry run in the database), cancels the
// person's Stripe subscriptions at once, erases the data and deletes the
// Auth user. A club-linked account is sent to the reviewed erasure instead.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import Stripe from "npm:stripe@22.0.0";
import { json } from "../_shared/billing_http.ts";
import { allowedWebOrigins } from "../_shared/sign_in_limits.ts";
import {
  stripeKeyIsLive,
  tacticsboardProductionOrigins,
} from "../_shared/tacticsboard_billing.ts";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";

const origins = allowedWebOrigins(
  Deno.env.get("TEAMZONE_EXTRA_WEB_ORIGINS"),
  tacticsboardProductionOrigins,
);

/// The word the person types to confirm.
export const confirmation = "AVSLUTA";

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
  const fail = (status: number, error: string, operation: string) => {
    sanitizedLog("account_deletion.failed", "error", requestId, {
      component: "account_deletion",
      operation,
      error_type: error,
    });
    return respond(json(status, { error }, headers));
  };

  const url = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    Deno.env.get("SUPABASE_ANON_KEY");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const databaseSecret = secretKeys.default ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  const authorization = request.headers.get("authorization");
  if (!url || !publishableKey || !databaseSecret || !authorization) {
    return respond(json(503, { error: "unavailable" }, headers));
  }

  let body: { confirm?: unknown } | null = null;
  try {
    body = await request.json();
  } catch {
    body = null;
  }
  if (body?.confirm !== confirmation) {
    return respond(json(400, { error: "invalid_request" }, headers));
  }

  const client = createClient(url, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const admin = createClient(url, databaseSecret, {
    auth: { persistSession: false },
  });
  const { data: user } = await client.auth.getUser(
    authorization.replace(/^Bearer\s+/i, ""),
  );
  if (!user?.user || user.user.is_anonymous) {
    return respond(json(401, { error: "not_signed_in" }, headers));
  }
  const profileId = user.user.id;
  const erase = (dryRun: boolean) =>
    admin.schema("api").rpc("erase_own_account", {
      target_profile_id: profileId,
      dry_run: dryRun,
    });

  // 1. Will it go through? Nothing is changed yet.
  const check = await erase(true);
  if (check.error) return fail(503, "unavailable", "dry_run");
  if (check.data !== "ok") {
    return respond(json(409, { error: check.data }, headers));
  }

  // 2. Stripe: every subscription of the person's customer ends now.
  const livemode = stripeKeyIsLive(stripeKey);
  if (livemode !== null) {
    const { data: customer, error } = await admin.schema("api").rpc(
      "tacticsboard_billing_customer",
      { target_profile_id: profileId, target_livemode: livemode },
    );
    if (error) return fail(503, "unavailable", "customer");
    if (typeof customer === "string") {
      try {
        const stripe = new Stripe(stripeKey);
        for await (
          const subscription of stripe.subscriptions.list({
            customer,
            status: "all",
          })
        ) {
          if (
            !["canceled", "incomplete_expired"].includes(subscription.status)
          ) {
            await stripe.subscriptions.cancel(subscription.id);
          }
        }
      } catch (error) {
        return fail(
          503,
          "billing_cancel_failed",
          error instanceof Error ? error.name : "stripe",
        );
      }
    }
  }

  // 3. The data, then the sign-in. A retry after a failed Auth delete finds
  // the data already gone and deletes the user.
  const erased = await erase(false);
  if (erased.error || erased.data !== "ok") {
    return fail(503, "unavailable", "erase");
  }
  const { error: deleteError } = await admin.auth.admin.deleteUser(profileId);
  if (deleteError) return fail(502, "auth_delete_failed", "delete_auth_user");
  sanitizedLog("account_deletion.completed", "info", requestId, {
    component: "account_deletion",
    result: "completed",
  });
  return respond(json(200, { deleted: true }, headers));
});
