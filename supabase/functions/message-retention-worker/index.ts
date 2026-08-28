import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";

const headers = { "content-type": "application/json" };

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
      component: "message_retention",
      result: "not_configured",
    });
    return respond(
      new Response(JSON.stringify({ error: "worker_not_configured" }), {
        status: 503,
        headers,
      }),
    );
  }
  const client = createClient(url, secret, { auth: { persistSession: false } });
  const { data: files, error: claimError } = await client.schema("api").rpc(
    "claim_expired_message_files",
    { batch_size: 100 },
  );
  if (claimError) {
    sanitizedLog("worker.failed", "error", requestId, {
      component: "message_retention",
      operation: "claim",
      error_type: claimError.code ?? "database",
    });
    return respond(
      new Response(JSON.stringify({ error: "claim_failed" }), {
        status: 500,
        headers,
      }),
    );
  }
  let deleted = 0;
  for (const file of files ?? []) {
    const { error: removeError } = await client.storage.from(file.bucket_id)
      .remove([file.object_key]);
    const { error: finishError } = await client.schema("api").rpc(
      "finish_message_file_deletion",
      { file_id: file.id, succeeded: !removeError },
    );
    if (!removeError && !finishError) deleted++;
  }
  const { data: retention, error: retentionError } = await client.schema("api")
    .rpc("apply_message_retention", { batch_size: 500 });
  if (retentionError) {
    sanitizedLog("worker.failed", "error", requestId, {
      component: "message_retention",
      operation: "retention",
      error_type: retentionError.code ?? "database",
    });
    return respond(
      new Response(
        JSON.stringify({
          error: "retention_failed",
          claimed: (files ?? []).length,
          deleted,
        }),
        { status: 500, headers },
      ),
    );
  }
  sanitizedLog("worker.completed", "info", requestId, {
    component: "message_retention",
    result: "completed",
  });
  return respond(
    new Response(
      JSON.stringify({ claimed: (files ?? []).length, deleted, retention }),
      { status: 200, headers },
    ),
  );
});
