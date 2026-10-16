import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";
import {
  authenticated,
  emailAddress,
  isAutomatic,
  replyText,
  threadFromReplyAddress,
  verifySvixSignature,
} from "../_shared/contact_mail.ts";

// PUB-14: a sender's e-mail reply to an answer (Resend inbound,
// reply.teamzoneapp.se). Every request must carry Resend's Svix signature.
// The mail must be addressed to a reply address whose HMAC matches its
// thread, pass DMARC, not be automatic and come from the thread's sender
// (checked in internal.receive_contact_email). Only the new plain text is
// kept; attachments and HTML are dropped. Mail that fails a check is
// acknowledged (200) so Resend does not retry it, and nothing is logged
// except the outcome.

const jsonHeaders = { "content-type": "application/json" };

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const respond = (body: unknown, status: number) =>
    withCorrelation(new Response(JSON.stringify(body), { status, headers: jsonHeaders }), requestId);
  const outcome = (result: string, status = 200) => {
    sanitizedLog("contact_inbound.handled", status >= 500 ? "error" : "info", requestId, {
      component: "contact_email",
      result,
    });
    return respond({ result }, status);
  };
  if (request.method !== "POST") return respond({ error: "method_not_allowed" }, 405);

  const webhookSecret = Deno.env.get("RESEND_INBOUND_WEBHOOK_SECRET") ?? "";
  const replySecret = Deno.env.get("CONTACT_REPLY_SECRET") ?? "";
  const resendKey = Deno.env.get("RESEND_API_KEY");
  const body = await request.text();
  if (body.length > 256_000) return outcome("too_large", 413);
  const signed = await verifySvixSignature(webhookSecret, {
    id: request.headers.get("svix-id"),
    timestamp: request.headers.get("svix-timestamp"),
    signature: request.headers.get("svix-signature"),
  }, body);
  if (!signed) return outcome("bad_signature", 401);
  if (replySecret.length < 32 || !resendKey) return outcome("not_configured", 503);

  let event: { type?: string; data?: Record<string, unknown> };
  try {
    event = JSON.parse(body);
  } catch {
    return outcome("bad_payload", 400);
  }
  if (event.type !== "email.received" || !event.data) return outcome("ignored_event");
  const emailId = event.data.email_id;
  if (typeof emailId !== "string" || !/^[0-9a-zA-Z-]{8,64}$/.test(emailId)) return outcome("bad_payload", 400);

  // The thread: the first recipient that is a valid reply address.
  const recipients = [
    ...((event.data.to as unknown[]) ?? []),
    ...((event.data.cc as unknown[]) ?? []),
  ].map(emailAddress).filter((value): value is string => value !== null);
  let thread: string | null = null;
  for (const address of recipients) {
    thread = await threadFromReplyAddress(replySecret, address);
    if (thread) break;
  }
  if (!thread) return outcome("unknown_address");

  // The webhook carries no body: fetch the mail with its authentication.
  const fetched = await fetch(`https://api.resend.com/emails/receiving/${emailId}`, {
    headers: { authorization: `Bearer ${resendKey}` },
  });
  if (!fetched.ok) return outcome(`provider_http_${fetched.status}`, fetched.status >= 500 ? 502 : 200);
  const mail = await fetched.json().catch(() => null) as Record<string, unknown> | null;
  if (!mail) return outcome("bad_provider_payload", 502);

  const headers = (mail.headers && typeof mail.headers === "object" ? mail.headers : {}) as Record<string, unknown>;
  if (isAutomatic(headers, typeof mail.subject === "string" ? mail.subject : "")) return outcome("automatic");
  if (!authenticated(mail.authentication)) return outcome("unauthenticated");
  const from = emailAddress(mail.from);
  if (!from) return outcome("bad_sender");
  const text = replyText(mail.text, mail.html);
  if (!text) return outcome("empty");

  const url = Deno.env.get("SUPABASE_URL");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const secret = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) return outcome("not_configured", 503);
  const api = createClient(url, secret, { auth: { persistSession: false } }).schema("api");
  const { data, error } = await api.rpc("receive_contact_email", {
    target_submission_public_id: thread,
    from_email: from,
    reply_body: text,
    provider_email_id: emailId,
  });
  // A database failure is retried by Resend; everything else is final.
  if (error) return outcome("database_error", 500);
  return outcome(typeof data === "string" ? data : "unknown");
});
