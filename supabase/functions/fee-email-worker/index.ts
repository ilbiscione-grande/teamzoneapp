import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";
import { feeEmailSubject, feeEmailText, unsubscribeUrl } from "../_shared/fee_mail.ts";

// Påminnelser via e-post (club-members-and-fees.md, step 5): sends the fee
// reminders queued for those without a TeamZone account. Started every
// minute by pg_cron (internal.invoke_fee_email_worker) with the support
// worker's token, only when an e-mail is waiting. Each e-mail goes from a
// TeamZone address with the club's name and carries an unsubscribe link and
// List-Unsubscribe. Addresses and amounts are never logged.

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
  // The unsubscribe links are signed with the contact reply secret, kept
  // apart by their own prefix (fee_mail.ts).
  const linkSecret = Deno.env.get("CONTACT_REPLY_SECRET") ?? "";
  const fromAddress = Deno.env.get("FEE_EMAIL_FROM_ADDRESS") ?? "avgifter@teamzoneapp.se";
  if (!url || !secret) return respond({ error: "worker_not_configured" }, 503);

  const api = createClient(url, secret, { auth: { persistSession: false } }).schema("api");
  const { data, error } = await api.rpc("claim_club_fee_emails", { batch_size: 20 });
  if (error) {
    sanitizedLog("worker.failed", "error", requestId, {
      component: "fee_email",
      operation: "claim",
      error_type: error.code ?? "database",
    });
    return respond({ error: "claim_failed" }, 500);
  }

  let sent = 0;
  let failed = 0;
  for (const item of (data ?? []) as Array<Record<string, unknown>>) {
    const emailId = String(item.email_id);
    const fees = (item.fees ?? []) as Array<{ name: string; amount: number }>;
    let providerId: string | null = null;
    let errorCode: string | null = null;
    // Fail closed: without a link secret the e-mail could not be unsubscribed.
    if (!resendKey || linkSecret.length < 32) {
      errorCode = "provider_not_configured";
    } else if (fees.length === 0) {
      errorCode = "nothing_to_remind";
    } else {
      const clubName = String(item.club_name ?? "");
      const link = await unsubscribeUrl(url, linkSecret, emailId);
      try {
        const response = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            authorization: `Bearer ${resendKey}`,
            "content-type": "application/json",
            "idempotency-key": `teamzone-fee-${emailId}`,
          },
          body: JSON.stringify({
            from: `"${displayName(`${clubName} via TeamZone`)}" <${fromAddress}>`,
            to: [String(item.to)],
            subject: feeEmailSubject({ clubName, title: String(item.title ?? "") }),
            text: feeEmailText({
              clubName,
              title: String(item.title ?? ""),
              dueOn: String(item.due_on ?? ""),
              paymentInfo: typeof item.payment_info === "string" ? item.payment_info : null,
              fees,
              unsubscribeUrl: link,
            }),
            headers: {
              "List-Unsubscribe": `<${link}>`,
              "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
            },
          }),
        });
        if (response.ok) {
          const payload = await response.json().catch(() => ({}));
          providerId = typeof payload?.id === "string" ? payload.id : "sent";
        } else {
          // Resend's reason, with any address removed.
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
    const { error: finishError } = await api.rpc("finish_club_fee_email", {
      target_email_id: emailId,
      sent: providerId !== null,
      provider_id: providerId,
      error_code: errorCode,
    });
    if (providerId !== null && !finishError) sent++;
    else failed++;
  }
  sanitizedLog("worker.completed", "info", requestId, {
    component: "fee_email",
    result: failed === 0 ? "ok" : "partial",
    sent,
    failed,
  });
  return respond({ sent, failed }, 200);
});
