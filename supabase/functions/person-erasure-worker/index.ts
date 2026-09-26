import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";

type ErasureInput = {
  requestId: string;
  decision: "approved" | "rejected";
  reason: string;
};

type WorkerItem = {
  request_id: string;
  subject_profile_id: string;
  state: "requested" | "approved" | "rejected" | "completed";
  revision: number;
};

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type, x-correlation-id",
  "access-control-allow-methods": "POST, OPTIONS",
};
const jsonHeaders = { ...corsHeaders, "content-type": "application/json" };
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function parseInput(value: unknown): ErasureInput | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const input = value as Record<string, unknown>;
  const requestId = typeof input.requestId === "string" ? input.requestId : "";
  const decision = input.decision;
  const reason = typeof input.reason === "string" ? input.reason.trim() : "";
  if (
    !uuidPattern.test(requestId) ||
    (decision !== "approved" && decision !== "rejected") ||
    reason.length < 2 ||
    reason.length > 500
  ) return null;
  return { requestId, decision, reason };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const requestId = correlationId(request);
  const respond = (body: unknown, status: number) =>
    withCorrelation(
      new Response(JSON.stringify(body), { status, headers: jsonHeaders }),
      requestId,
    );
  if (request.method !== "POST") {
    return respond({ error: "method_not_allowed" }, 405);
  }

  const authorization = request.headers.get("authorization") ?? "";
  const url = Deno.env.get("SUPABASE_URL");
  const publishableKeys = JSON.parse(
    Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}",
  );
  const publishableKey = publishableKeys.default ??
    Deno.env.get("SUPABASE_ANON_KEY");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const serviceSecret = secretKeys.default ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (
    !url || !publishableKey || !serviceSecret ||
    !authorization.startsWith("Bearer ")
  ) {
    return respond({ error: "gateway_unavailable" }, 503);
  }

  let input: ErasureInput | null = null;
  try {
    input = parseInput(await request.json());
  } catch {
    // The neutral validation response below intentionally covers invalid JSON.
  }
  if (!input) return respond({ error: "invalid_request" }, 400);

  const userClient = createClient(url, publishableKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: authorization } },
  });
  const serviceClient = createClient(url, serviceSecret, {
    auth: { persistSession: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  const { data: isSupportAdmin, error: adminError } = await userClient
    .schema("api").rpc("is_support_admin");
  if (authError || !authData.user || adminError || isSupportAdmin !== true) {
    sanitizedLog("person_erasure.rejected", "warning", requestId, {
      component: "person_erasure_worker",
      error_type: "not_authorized",
    });
    return respond({ error: "not_found" }, 404);
  }

  const { data: rawItem, error: itemError } = await serviceClient.schema("api")
    .rpc("get_global_person_erasure_worker_item", {
      target_request_id: input.requestId,
    });
  const item = rawItem as WorkerItem | null;
  if (itemError || !item || item.subject_profile_id === authData.user.id) {
    return respond({ error: "not_found" }, 404);
  }
  if (item.state === "completed" || item.state === "rejected") {
    return respond({ state: item.state }, 200);
  }

  if (item.state === "requested") {
    const { error: reviewError } = await serviceClient.schema("api").rpc(
      "review_global_person_erasure",
      {
        target_request_id: input.requestId,
        reviewer_profile_id: authData.user.id,
        decision: input.decision,
        reason: input.reason,
      },
    );
    if (reviewError) {
      sanitizedLog("person_erasure.failed", "error", requestId, {
        component: "person_erasure_worker",
        operation: "review",
        error_type: reviewError.code ?? "database",
      });
      return respond({ error: "operation_failed" }, 409);
    }
    if (input.decision === "rejected") {
      return respond({ state: "rejected" }, 200);
    }
  } else if (input.decision !== "approved") {
    return respond({ error: "invalid_transition" }, 409);
  }

  const { data: subject } = await serviceClient.auth.admin.getUserById(
    item.subject_profile_id,
  );
  if (subject.user) {
    const { error: deleteError } = await serviceClient.auth.admin.deleteUser(
      item.subject_profile_id,
      false,
    );
    if (deleteError) {
      sanitizedLog("person_erasure.failed", "error", requestId, {
        component: "person_erasure_worker",
        operation: "delete_auth_user",
        error_type: deleteError.code ?? "auth_admin",
      });
      return respond({ error: "operation_failed", state: "approved" }, 502);
    }
  }

  const { error: finalizeError } = await serviceClient.schema("api").rpc(
    "finalize_global_person_erasure",
    { target_request_id: input.requestId },
  );
  if (finalizeError) {
    sanitizedLog("person_erasure.failed", "error", requestId, {
      component: "person_erasure_worker",
      operation: "finalize",
      error_type: finalizeError.code ?? "database",
    });
    return respond({ error: "operation_failed", state: "approved" }, 502);
  }

  sanitizedLog("person_erasure.completed", "info", requestId, {
    component: "person_erasure_worker",
    result: "completed",
  });
  return respond({ state: "completed" }, 200);
});
