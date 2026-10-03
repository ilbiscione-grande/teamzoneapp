import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";

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

const subjectFor = (caseType: string) => {
  switch (caseType) {
    case "club_verification":
      return "Ny ansökan om officiell klubb i TeamZone";
    case "protected_name":
      return "Nytt ärende om skyddat klubbnamn i TeamZone";
    case "login_email_change":
      return "Ny begäran om byte av inloggningsadress i TeamZone";
    case "person_erasure":
      return "Ny begäran om kontoradering i TeamZone";
    default:
      return "Nytt supportärende i TeamZone";
  }
};

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const respond = (response: Response) => withCorrelation(response, requestId);
  if (request.method !== "POST") {
    return respond(new Response("Method not allowed", { status: 405 }));
  }

  const workerToken = Deno.env.get("SUPPORT_WORKER_TOKEN") ?? "";
  if (!await matchesWorkerToken(request, workerToken)) {
    return respond(new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: jsonHeaders,
    }));
  }

  const url = Deno.env.get("SUPABASE_URL");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const secret = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("SUPPORT_EMAIL_FROM") ??
    "TeamZone Support <support@teamzoneapp.se>";
  const portalUrl = Deno.env.get("SUPPORT_PORTAL_URL") ??
    "https://app.teamzoneapp.se/support";
  if (!url || !secret) {
    return respond(new Response(JSON.stringify({ error: "worker_not_configured" }), {
      status: 503,
      headers: jsonHeaders,
    }));
  }

  const client = createClient(url, secret, { auth: { persistSession: false } });
  const { data, error } = await client.schema("api").rpc(
    "claim_support_email_batch",
    { batch_size: 20 },
  );
  if (error) {
    sanitizedLog("worker.failed", "error", requestId, {
      component: "support_email",
      operation: "claim",
      error_type: error.code ?? "database",
    });
    return respond(new Response(JSON.stringify({ error: "claim_failed" }), {
      status: 500,
      headers: jsonHeaders,
    }));
  }

  let delivered = 0;
  let failed = 0;
  for (const item of data ?? []) {
    const recipients = (item.recipient_emails ?? []).filter((value: unknown) =>
      typeof value === "string" && value.length > 3
    );
    let nextState = "failed";
    let errorCode: string | null = null;
    let providerReference: string | null = null;
    if (!resendKey) {
      errorCode = "provider_not_configured";
    } else if (recipients.length === 0) {
      errorCode = "recipient_not_configured";
    } else {
      try {
        const response = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            authorization: `Bearer ${resendKey}`,
            "content-type": "application/json",
            "idempotency-key": `teamzone-support-${item.outbox_id}`,
          },
          body: JSON.stringify({
            from,
            to: recipients,
            subject: subjectFor(item.case_type),
            text: [
              subjectFor(item.case_type),
              "",
              `Ärendereferens: ${item.case_id}`,
              `Inkom: ${item.received_at}`,
              "",
              `Öppna den säkra supportkön: ${portalUrl}`,
              "",
              "Underlag och personuppgifter visas endast efter inloggning i TeamZone.",
            ].join("\n"),
          }),
        });
        if (response.ok) {
          const payload = await response.json();
          nextState = "delivered";
          providerReference = typeof payload?.id === "string" ? payload.id : null;
        } else {
          errorCode = `provider_http_${response.status}`;
        }
      } catch {
        errorCode = "provider_network_error";
      }
    }

    const { error: finishError } = await client.schema("api").rpc(
      "finish_support_email_attempt",
      {
        target_outbox_id: item.outbox_id,
        next_state: nextState,
        error_code: errorCode,
        target_provider_reference: providerReference,
      },
    );
    if (finishError) {
      failed++;
    } else if (nextState === "delivered") {
      delivered++;
    } else {
      failed++;
    }
  }

  sanitizedLog("worker.completed", "info", requestId, {
    component: "support_email",
    result: "completed",
    claimed: (data ?? []).length,
    delivered,
    failed,
  });
  return respond(new Response(JSON.stringify({
    claimed: (data ?? []).length,
    delivered,
    failed,
  }), { status: 200, headers: jsonHeaders }));
});
