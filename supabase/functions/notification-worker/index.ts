import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";

const jsonHeaders = { "content-type": "application/json" };

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const respond = (response: Response) => withCorrelation(response, requestId);
  if (request.method !== "POST") {
    return respond(new Response("Method not allowed", { status: 405 }));
  }
  const url = Deno.env.get("SUPABASE_URL");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const secret = secretKeys.default ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) {
    sanitizedLog("worker.unavailable", "error", requestId, {
      component: "notification",
      result: "not_configured",
    });
    return respond(
      new Response(JSON.stringify({ error: "worker_not_configured" }), {
        status: 503,
        headers: jsonHeaders,
      }),
    );
  }
  const client = createClient(url, secret, { auth: { persistSession: false } });
  const { data, error } = await client.schema("api").rpc(
    "claim_notification_batch",
    { batch_size: 25 },
  );
  if (error) {
    sanitizedLog("worker.failed", "error", requestId, {
      component: "notification",
      operation: "claim",
      error_type: error.code ?? "database",
    });
    return respond(
      new Response(JSON.stringify({ error: "claim_failed" }), {
        status: 500,
        headers: jsonHeaders,
      }),
    );
  }
  let processed = 0;
  for (const item of data ?? []) {
    // Provider activation is a separate production decision. Until then the
    // worker records a sanitized terminal delivery fact without logging payloads.
    const { error: finishError } = await client.schema("api").rpc(
      "finish_notification_attempt",
      {
        target_outbox_id: item.id,
        target_state: "suppressed",
        error_code: item.recipient_profile_id
          ? "provider_not_configured"
          : "recipient_unlinked",
        provider_reference: null,
      },
    );
    if (!finishError) processed++;
  }
  sanitizedLog("worker.completed", "info", requestId, {
    component: "notification",
    result: "completed",
  });
  return respond(
    new Response(JSON.stringify({ claimed: (data ?? []).length, processed }), {
      status: 200,
      headers: jsonHeaders,
    }),
  );
});
