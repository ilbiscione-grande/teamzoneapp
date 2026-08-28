import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  recordCriticalFlowOutcome,
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
    return respond({ error: "request_rejected" }, 403);
  }
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers });
  }
  if (request.method !== "POST") {
    return respond({ error: "method_not_allowed" }, 405);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const publishableKeys = JSON.parse(
    Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}",
  );
  const publishableKey = publishableKeys.default ??
    Deno.env.get("SUPABASE_ANON_KEY");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const serviceSecret = secretKeys.default ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publishableKey || !serviceSecret) {
    sanitizedLog("auth.sign_in.unavailable", "error", requestId, {
      component: "auth_password_sign_in",
      error_type: "configuration",
    });
    return respond({ error: "sign_in_unavailable" }, 503);
  }

  let input: unknown;
  try {
    input = await request.json();
  } catch {
    return respond({ error: "invalid_request" }, 400);
  }
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    return respond({ error: "invalid_request" }, 400);
  }
  const body = input as Record<string, unknown>;
  const email = typeof body.email === "string" ? body.email.trim() : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (!email || email.length > 320 || !password || password.length > 1024) {
    return respond({ error: "invalid_request" }, 400);
  }

  const authClient = createClient(url, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const serviceClient = createClient(url, serviceSecret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await authClient.auth.signInWithPassword({
    email,
    password,
  });
  await recordCriticalFlowOutcome(
    serviceClient,
    "auth",
    error ? "failed" : "succeeded",
    requestId,
  );
  if (error || !data.session) {
    sanitizedLog("auth.sign_in.failed", "warning", requestId, {
      component: "auth_password_sign_in",
      error_type: error?.code ?? "authentication",
    });
    return respond({ error: "invalid_credentials" }, 401);
  }

  sanitizedLog("auth.sign_in.succeeded", "info", requestId, {
    component: "auth_password_sign_in",
    result: "succeeded",
  });
  return respond({
    refresh_token: data.session.refresh_token,
  }, 200);
});
