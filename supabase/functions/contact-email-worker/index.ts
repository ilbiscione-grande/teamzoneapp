import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";
import { answerText, replyAddress } from "../_shared/contact_mail.ts";

// PUB-14: sends answers to messages from the club site. Started every minute
// by pg_cron (internal.invoke_contact_email_worker) with the support worker's
// token, only when an answer is waiting. Each answer goes from a TeamZone
// address with the club's (or team's) name, never a leader's own address,
// and its Reply-To is the thread's signed reply address, so the sender's
// answer comes back to contact-inbound. Addresses and text are never logged.

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

// A display name may not carry quotes or angle brackets into the header.
const displayName = (value: string) => value.replace(/["<>\r\n]/g, "").slice(0, 80);

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const respond = (body: unknown, status: number) =>
    withCorrelation(new Response(JSON.stringify(body), { status, headers: jsonHeaders }), requestId);
  if (request.method !== "POST") return respond({ error: "method_not_allowed" }, 405);
  if (!await matchesWorkerToken(request, Deno.env.get("SUPPORT_WORKER_TOKEN") ?? "")) {
    return respond({ error: "unauthorized" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const secret = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendKey = Deno.env.get("RESEND_API_KEY");
  const replySecret = Deno.env.get("CONTACT_REPLY_SECRET") ?? "";
  const fromAddress = Deno.env.get("CONTACT_EMAIL_FROM_ADDRESS") ?? "klubbsajt@teamzoneapp.se";
  if (!url || !secret) return respond({ error: "worker_not_configured" }, 503);

  const api = createClient(url, secret, { auth: { persistSession: false } }).schema("api");
  const { data, error } = await api.rpc("claim_contact_emails", { batch_size: 20 });
  if (error) {
    sanitizedLog("worker.failed", "error", requestId, {
      component: "contact_email",
      operation: "claim",
      error_type: error.code ?? "database",
    });
    return respond({ error: "claim_failed" }, 500);
  }

  let sent = 0;
  let failed = 0;
  for (const item of (data ?? []) as Array<Record<string, string | null>>) {
    let providerId: string | null = null;
    let errorCode: string | null = null;
    // Fail closed: without a reply secret the sender could not answer back.
    if (!resendKey || replySecret.length < 32) {
      errorCode = "provider_not_configured";
    } else {
      const sender = item.team_name ? `${item.team_name} · ${item.club_name}` : `${item.club_name}`;
      try {
        const response = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            authorization: `Bearer ${resendKey}`,
            "content-type": "application/json",
            "idempotency-key": `teamzone-contact-${item.message_id}`,
          },
          body: JSON.stringify({
            from: `"${displayName(`${sender} via TeamZone`)}" <${fromAddress}>`,
            to: [item.to],
            reply_to: await replyAddress(replySecret, String(item.submission_public_id)),
            subject: `Sv: ${item.subject}`.slice(0, 200),
            text: answerText({
              body: String(item.body),
              sender,
              originalAt: String(item.original_at),
              originalBody: String(item.original_body ?? ""),
            }),
          }),
        });
        if (response.ok) {
          const payload = await response.json().catch(() => ({}));
          providerId = typeof payload?.id === "string" ? payload.id : "sent";
        } else {
          // Resend's reason ("validation_error: … not verified"), with any
          // address removed, so a failure can be diagnosed from the row.
          const problem = await response.json().catch(() => ({})) as { name?: unknown; message?: unknown };
          const reason = [problem.name, problem.message]
            .filter((part): part is string => typeof part === "string")
            .join(": ")
            .replace(/[^\s<>"]+@[^\s<>"]+/g, "<adress>");
          errorCode = `provider_http_${response.status}${reason ? ` ${reason}` : ""}`.slice(0, 80);
        }
      } catch {
        errorCode = "provider_network_error";
      }
    }
    const { error: finishError } = await api.rpc("finish_contact_email", {
      target_message_id: item.message_id,
      sent: providerId !== null,
      provider_id: providerId,
      error_code: errorCode,
    });
    if (providerId !== null && !finishError) sent++;
    else failed++;
  }
  sanitizedLog("worker.completed", "info", requestId, {
    component: "contact_email",
    result: failed === 0 ? "ok" : "partial",
    sent,
    failed,
  });
  return respond({ sent, failed }, 200);
});
