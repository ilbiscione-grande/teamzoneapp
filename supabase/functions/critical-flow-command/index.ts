import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  recordCriticalFlowOutcome,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";

type Flow = "messaging" | "critical_commands";

const OPERATIONS: Readonly<Record<string, Flow>> = Object.freeze({
  create_thread: "messaging",
  add_thread_participants: "messaging",
  create_announcement: "messaging",
  send_message: "messaging",
  mark_thread_read: "messaging",
  mark_all_threads_read: "messaging",
  set_thread_mute: "messaging",
  set_thread_pin: "messaging",
  set_thread_visibility: "messaging",
  leave_thread: "messaging",
  close_thread: "messaging",
  request_thread_erasure: "messaging",
  approve_thread_erasure: "messaging",
  set_notification_state: "messaging",
  mark_all_notifications_read: "messaging",
  set_messaging_push: "messaging",
  stage_message_file: "messaging",
  recall_message: "messaging",
  report_message: "messaging",
  request_cross_club_contact: "messaging",
  decide_contact_request: "messaging",
  freeze_match_roster: "critical_commands",
  transition_match_clock_v2: "critical_commands",
  transition_match_period_v2: "critical_commands",
  record_match_event_v2: "critical_commands",
  complete_match_v2: "critical_commands",
  unlock_match_v2: "critical_commands",
  create_economy_account: "critical_commands",
  create_economy_entry: "critical_commands",
  approve_economy_entry: "critical_commands",
  post_economy_entry: "critical_commands",
  reverse_economy_entry: "critical_commands",
  create_board_mandate_change: "critical_commands",
  approve_board_mandate_change: "critical_commands",
  apply_board_mandate_change: "critical_commands",
  save_editorial_article: "critical_commands",
  transition_editorial_article: "critical_commands",
  configure_event_publication: "critical_commands",
  save_public_partner: "critical_commands",
  request_publication_domain: "critical_commands",
  set_canonical_publication_domain: "critical_commands",
});

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};
const jsonHeaders = { ...corsHeaders, "content-type": "application/json" };

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const requestId = correlationId(request);
  const respond = (body: unknown, status: number) => withCorrelation(
    new Response(JSON.stringify(body), { status, headers: jsonHeaders }),
    requestId,
  );
  if (request.method !== "POST") return respond({ error: "method_not_allowed" }, 405);

  const authorization = request.headers.get("authorization") ?? "";
  const url = Deno.env.get("SUPABASE_URL");
  const publishableKeys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}");
  const publishableKey = publishableKeys.default ?? Deno.env.get("SUPABASE_ANON_KEY");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const serviceSecret = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publishableKey || !serviceSecret || !authorization.startsWith("Bearer ")) {
    sanitizedLog("critical_flow.command.rejected", "warning", requestId, {
      component: "critical_flow_command",
      error_type: "configuration_or_authorization",
    });
    return respond({ error: "gateway_unavailable" }, 503);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    sanitizedLog("critical_flow.command.rejected", "warning", requestId, {
      component: "critical_flow_command",
      error_type: "invalid_json",
    });
    return respond({ error: "invalid_request" }, 400);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return respond({ error: "invalid_request" }, 400);
  }
  const input = body as Record<string, unknown>;
  const operation = typeof input.operation === "string" ? input.operation : "";
  const flow = OPERATIONS[operation];
  const params = input.params;
  if (!flow || !params || typeof params !== "object" || Array.isArray(params)) {
    sanitizedLog("critical_flow.command.rejected", "warning", requestId, {
      component: "critical_flow_command",
      operation,
      error_type: "operation_or_params",
    });
    return respond({ error: "operation_not_allowed" }, 400);
  }

  sanitizedLog("critical_flow.command.accepted", "info", requestId, {
    component: "critical_flow_command",
    flow,
    operation,
  });

  const userClient = createClient(url, publishableKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: authorization } },
  });
  const serviceClient = createClient(url, serviceSecret, {
    auth: { persistSession: false },
  });
  const { data, error } = await userClient.schema("api").rpc(
    operation,
    params as Record<string, unknown>,
  );
  await recordCriticalFlowOutcome(
    serviceClient,
    flow,
    error ? "failed" : "succeeded",
    requestId,
  );
  if (error) {
    sanitizedLog("critical_flow.command.failed", "warning", requestId, {
      component: "critical_flow_command",
      flow,
      operation,
      error_type: error.code ?? "database",
    });
    const publicError = operation === "freeze_match_roster" &&
        error.code === "23514"
      ? "accepted_callups_required"
      : "command_failed";
    return respond({ error: publicError }, 409);
  }
  return respond({ data }, 200);
});
