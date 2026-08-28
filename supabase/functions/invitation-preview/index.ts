import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";

const allowedWebOrigins = new Set([
  "https://app.teamzoneapp.se",
  "http://localhost",
  "http://localhost:5000",
]);

function corsHeaders(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    "access-control-allow-headers":
      "authorization, apikey, content-type, x-client-info",
    "access-control-allow-methods": "POST, OPTIONS",
    "cache-control": "no-store",
    "vary": "Origin",
  };
  if (origin && allowedWebOrigins.has(origin)) {
    headers["access-control-allow-origin"] = origin;
  }
  return headers;
}

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const origin = request.headers.get("origin");
  const headers = corsHeaders(origin);
  const respond = (body: unknown, status: number) => withCorrelation(
    new Response(JSON.stringify(body), {
      status,
      headers: { ...headers, "content-type": "application/json" },
    }),
    requestId,
  );

  if (origin && !allowedWebOrigins.has(origin)) {
    return respond({ status: "invalid" }, 403);
  }
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return respond({ status: "invalid" }, 405);

  let input: unknown;
  try {
    input = await request.json();
  } catch {
    return respond({ status: "invalid" }, 400);
  }
  const token = input && typeof input === "object" && !Array.isArray(input) &&
      typeof (input as Record<string, unknown>).token === "string"
    ? ((input as Record<string, string>).token).trim()
    : "";
  if (token.length < 32 || token.length > 512) {
    return respond({ status: "invalid" }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const serviceSecret = secretKeys.default ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceSecret) {
    sanitizedLog("invitation.preview.unavailable", "error", requestId, {
      component: "invitation_preview",
      error_type: "configuration",
    });
    return respond({ status: "invalid" }, 503);
  }

  const serviceClient = createClient(url, serviceSecret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await serviceClient.schema("api").rpc(
    "preview_roster_invitation",
    { raw_token: token },
  );
  if (error || !data || typeof data !== "object") {
    sanitizedLog("invitation.preview.failed", "warning", requestId, {
      component: "invitation_preview",
      error_type: error?.code ?? "invalid",
    });
    return respond({ status: "invalid" }, 200);
  }
  return respond(data, 200);
});
