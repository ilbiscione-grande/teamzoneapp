import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";
import {
  fcmAccessToken,
  isStale,
  parseServiceAccount,
  type PushContent,
  sendFcm,
} from "../_shared/fcm.ts";

// Started every minute by pg_cron (internal.invoke_notification_worker) with
// the NOTIFICATION_WORKER_TOKEN. Push goes out only when
// NOTIFICATION_PUSH_ENABLED=true and FCM_SERVICE_ACCOUNT_JSON are set (the
// fail-closed switch); otherwise every claimed notification is recorded as
// suppressed, as before. Delivery facts are recorded
// without logging payloads: device tokens, titles and bodies never reach a log.

const jsonHeaders = { "content-type": "application/json" };

const matchesWorkerToken = async (request: Request, expected: string) => {
  const presented = request.headers.get("x-teamzone-worker-token") ?? "";
  if (!presented || !expected) return false;
  const encoder = new TextEncoder();
  const [presentedHash, expectedHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(presented)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const left = new Uint8Array(presentedHash);
  const right = new Uint8Array(expectedHash);
  let mismatch = left.length ^ right.length;
  for (let index = 0; index < Math.min(left.length, right.length); index++) {
    mismatch |= left[index] ^ right[index];
  }
  return mismatch === 0;
};

type Target = { endpoint_id: string; platform: string; token: string };
type Message = PushContent & { targets: Target[] };

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const respond = (body: unknown, status: number) =>
    withCorrelation(
      new Response(JSON.stringify(body), { status, headers: jsonHeaders }),
      requestId,
    );
  if (request.method !== "POST") return respond({ error: "method_not_allowed" }, 405);
  if (!(await matchesWorkerToken(request, Deno.env.get("NOTIFICATION_WORKER_TOKEN") ?? ""))) {
    return respond({ error: "unauthorized" }, 401);
  }
  const url = Deno.env.get("SUPABASE_URL");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const secret = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) {
    sanitizedLog("worker.unavailable", "error", requestId, {
      component: "notification",
      result: "not_configured",
    });
    return respond({ error: "worker_not_configured" }, 503);
  }
  const pushEnabled = Deno.env.get("NOTIFICATION_PUSH_ENABLED") === "true";
  const account = pushEnabled
    ? parseServiceAccount(Deno.env.get("FCM_SERVICE_ACCOUNT_JSON"))
    : null;
  // Switched on but the service account is missing or not valid JSON (for
  // example quotes lost when the secret was set through a shell).
  const notConfigured = pushEnabled ? "fcm_service_account_invalid" : "provider_not_configured";

  const api = createClient(url, secret, { auth: { persistSession: false } })
    .schema("api");
  const { data, error } = await api.rpc("claim_notification_batch", { batch_size: 25 });
  if (error) {
    sanitizedLog("worker.failed", "error", requestId, {
      component: "notification",
      operation: "claim",
      error_type: error.code ?? "database",
    });
    return respond({ error: "claim_failed" }, 500);
  }

  const finish = (id: string, state: string, code: string | null, reference: string | null = null) =>
    api.rpc("finish_notification_attempt", {
      target_outbox_id: id,
      target_state: state,
      error_code: code,
      provider_reference: reference,
    });

  let accessToken: string | null = null;
  const counts = { delivered: 0, suppressed: 0, failed: 0 };
  for (const item of data ?? []) {
    let state = "suppressed";
    let code: string | null = null;
    let reference: string | null = null;
    if (!item.recipient_profile_id) {
      code = "recipient_unlinked";
    } else if (isStale(item.created_at)) {
      code = "stale";
    } else if (!account) {
      code = notConfigured;
    } else {
      const { data: message } = await api.rpc("push_message_for_outbox", {
        target_outbox_id: item.id,
      });
      const push = message as Message | null;
      if (!push) {
        code = "unsupported_event";
      } else if (push.targets.length === 0) {
        code = "no_push_endpoint";
      } else {
        try {
          accessToken ??= await fcmAccessToken(account);
          let retryable = false;
          for (const target of push.targets) {
            const result = await sendFcm(account, accessToken, target.token, push);
            if (result.kind === "sent") {
              reference ??= result.name;
            } else if (result.kind === "unregistered") {
              await api.rpc("disable_push_endpoint", { target_endpoint_id: target.endpoint_id });
            } else if (result.kind === "retryable") {
              retryable = true;
              code = result.code;
            } else {
              code ??= result.code;
            }
          }
          if (reference) {
            state = "delivered";
            code = null;
          } else if (retryable) {
            state = "failed";
          } else {
            code ??= "fcm_unregistered";
          }
        } catch (sendError) {
          state = "failed";
          code = sendError instanceof Error && sendError.message.startsWith("fcm_auth")
            ? sendError.message
            : "fcm_unavailable";
        }
      }
    }
    const { error: finishError } = await finish(item.id, state, code, reference);
    if (!finishError) counts[state as keyof typeof counts]++;
  }
  sanitizedLog("worker.completed", "info", requestId, {
    component: "notification",
    result: account ? "push_enabled" : pushEnabled ? "push_misconfigured" : "push_disabled",
  });
  return respond({ claimed: (data ?? []).length, ...counts }, 200);
});
