import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";
import {
  parsePushReplyRequest,
  pushResponseStatus,
} from "../_shared/push_response.ts";

// "Svara" from a message notification (Android, after unlock). As for
// push-callup-response, the single-use reply token from the push is the
// credential: it sends one message as the recipient into that thread
// (internal.reply_from_push). No JWT verification (config.toml); the token
// and the text are never logged.

const jsonHeaders = { "content-type": "application/json" };

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const respond = (body: unknown, status: number) =>
    withCorrelation(
      new Response(JSON.stringify(body), { status, headers: jsonHeaders }),
      requestId,
    );
  if (request.method !== "POST") return respond({ error: "method_not_allowed" }, 405);
  const parsed = parsePushReplyRequest(await request.json().catch(() => null));
  if (!parsed) return respond({ error: "invalid_input" }, 400);

  const url = Deno.env.get("SUPABASE_URL");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const secret = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) return respond({ error: "unavailable" }, 503);

  const api = createClient(url, secret, { auth: { persistSession: false } }).schema("api");
  const { data, error } = await api.rpc("reply_from_push", {
    raw_token: parsed.token,
    reply_body: parsed.body,
    idempotency_key: parsed.idempotencyKey,
  });
  if (error) {
    const status = pushResponseStatus(error.message);
    sanitizedLog("push_reply.refused", status === 500 ? "error" : "info", requestId, {
      component: "notification",
      result: status === 500 ? (error.code ?? "database") : error.message,
    });
    return respond({ error: status === 500 ? "failed" : error.message }, status);
  }
  sanitizedLog("push_reply.sent", "info", requestId, {
    component: "notification",
    result: (data as { repeated?: boolean })?.repeated ? "repeated" : "sent",
  });
  return respond({ sent: true }, 200);
});
