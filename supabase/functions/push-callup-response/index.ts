import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";
import {
  parsePushResponseRequest,
  pushResponseStatus,
} from "../_shared/push_response.ts";

// "Kommer" from a callup notification (decided 2026-10-13). The action runs
// in the background without a user session, so the single-use response token
// from the push is the credential: it answers "accepted" for one callup and
// person (internal.respond_callup_from_push). No JWT verification
// (config.toml); the token and the payload are never logged.

const jsonHeaders = { "content-type": "application/json" };

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const respond = (body: unknown, status: number) =>
    withCorrelation(
      new Response(JSON.stringify(body), { status, headers: jsonHeaders }),
      requestId,
    );
  if (request.method !== "POST") return respond({ error: "method_not_allowed" }, 405);
  const parsed = parsePushResponseRequest(await request.json().catch(() => null));
  if (!parsed) return respond({ error: "invalid_input" }, 400);

  const url = Deno.env.get("SUPABASE_URL");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const secret = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) return respond({ error: "unavailable" }, 503);

  const api = createClient(url, secret, { auth: { persistSession: false } }).schema("api");
  const { data, error } = await api.rpc("respond_callup_from_push", {
    raw_token: parsed.token,
    idempotency_key: parsed.idempotencyKey,
  });
  if (error) {
    const status = pushResponseStatus(error.message);
    sanitizedLog("push_response.refused", status === 500 ? "error" : "info", requestId, {
      component: "notification",
      result: status === 500 ? (error.code ?? "database") : error.message,
    });
    return respond({ error: status === 500 ? "failed" : error.message }, status);
  }
  sanitizedLog("push_response.recorded", "info", requestId, {
    component: "notification",
    result: (data as { repeated?: boolean })?.repeated ? "repeated" : "accepted",
  });
  return respond({ response: "accepted" }, 200);
});
