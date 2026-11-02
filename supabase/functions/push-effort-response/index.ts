import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";
import {
  parsePushEffortRequest,
  pushResponseStatus,
} from "../_shared/push_response.ts";

// An answer 1–10 from the effort notification after a training
// (2026-11-02). The action runs in the background without a user session,
// so the token from the push is the credential: it answers for one training
// and player while the question is open (internal.respond_effort_from_push).
// No JWT verification (config.toml); the token and the answer are never
// logged.

const jsonHeaders = { "content-type": "application/json" };

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const respond = (body: unknown, status: number) =>
    withCorrelation(
      new Response(JSON.stringify(body), { status, headers: jsonHeaders }),
      requestId,
    );
  if (request.method !== "POST") return respond({ error: "method_not_allowed" }, 405);
  const parsed = parsePushEffortRequest(await request.json().catch(() => null));
  if (!parsed) return respond({ error: "invalid_input" }, 400);

  const url = Deno.env.get("SUPABASE_URL");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const secret = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) return respond({ error: "unavailable" }, 503);

  const api = createClient(url, secret, { auth: { persistSession: false } }).schema("api");
  const { error } = await api.rpc("respond_effort_from_push", {
    raw_token: parsed.token,
    new_rating: parsed.rating,
  });
  if (error) {
    const status = pushResponseStatus(error.message);
    sanitizedLog("push_effort.refused", status === 500 ? "error" : "info", requestId, {
      component: "notification",
      result: status === 500 ? (error.code ?? "database") : error.message,
    });
    return respond({ error: status === 500 ? "failed" : error.message }, status);
  }
  sanitizedLog("push_effort.recorded", "info", requestId, {
    component: "notification",
    result: "recorded",
  });
  return respond({ response: "recorded" }, 200);
});
