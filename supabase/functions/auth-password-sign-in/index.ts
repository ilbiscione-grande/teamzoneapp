import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { passwordSignInOutcome } from "../_shared/password_sign_in_outcome.ts";
import {
  correlationId,
  recordCriticalFlowOutcome,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";
import {
  allowedWebOrigins as webOrigins,
  clientAddress,
  limitKeyHash,
} from "../_shared/sign_in_limits.ts";

// Local development origins come from TEAMZONE_EXTRA_WEB_ORIGINS, set only
// on the test project.
const allowedWebOrigins = webOrigins(
  Deno.env.get("TEAMZONE_EXTRA_WEB_ORIGINS"),
);

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
  const respond = (
    body: unknown,
    status: number,
    extra: Record<string, string> = {},
  ) =>
    withCorrelation(
      new Response(JSON.stringify(body), {
        status,
        headers: { ...headers, ...extra, "content-type": "application/json" },
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

  const address = clientAddress(request.headers);
  const serviceClient = createClient(url, serviceSecret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  // Failed-sign-in limits (internal.sign_in_failures): Auth itself only sees
  // this function's address. If the limit store is unavailable, sign-in
  // still works under Auth's own limits rather than locking everyone out.
  const emailHash = await limitKeyHash(serviceSecret, "email", email);
  const addressHash = await limitKeyHash(serviceSecret, "ip", address);
  const limits = serviceClient.schema("api");
  const { data: allowed, error: limitError } = await limits.rpc(
    "sign_in_attempt_allowed",
    { email_hash: emailHash, ip_hash: addressHash },
  );
  if (limitError) {
    sanitizedLog("auth.sign_in.limit_unavailable", "error", requestId, {
      component: "auth_password_sign_in",
      error_type: "limit_store",
    });
  } else if (allowed === false) {
    sanitizedLog("auth.sign_in.limited", "warning", requestId, {
      component: "auth_password_sign_in",
      result: "limited",
    });
    return respond({ error: "too_many_attempts" }, 429, {
      "retry-after": "900",
    });
  }

  const authClient = createClient(url, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    // Lets Auth's own per-IP limits see the client where the platform
    // honours Sb-Forwarded-For.
    global: { headers: { "Sb-Forwarded-For": address } },
  });
  let authResult;
  try {
    authResult = await authClient.auth.signInWithPassword({ email, password });
  } catch (_) {
    // SDK exceptions (including transport failures) must also reach the
    // operational counter, without logging credentials or error messages.
    await recordCriticalFlowOutcome(serviceClient, "auth", "failed", requestId);
    sanitizedLog("auth.sign_in.unavailable", "error", requestId, {
      component: "auth_password_sign_in",
      error_type: "request_failed",
    });
    return respond({ error: "sign_in_unavailable" }, 503);
  }
  const { data, error } = authResult;
  const outcome = passwordSignInOutcome(error, !!data.session);
  if (outcome === "failed") {
    await recordCriticalFlowOutcome(serviceClient, "auth", "failed", requestId);
    sanitizedLog("auth.sign_in.unavailable", "error", requestId, {
      component: "auth_password_sign_in",
      error_type: error?.code ?? "authentication",
    });
    return respond({ error: "sign_in_unavailable" }, 503);
  }
  if (outcome === "limited") {
    sanitizedLog("auth.sign_in.limited", "warning", requestId, {
      component: "auth_password_sign_in",
      result: "limited",
    });
    return respond({ error: "too_many_attempts" }, 429, {
      "retry-after": "900",
    });
  }
  const succeeded = outcome === "succeeded";
  const { error: recordError } = await limits.rpc("record_sign_in_result", {
    email_hash: emailHash,
    ip_hash: addressHash,
    succeeded,
  });
  if (recordError) {
    sanitizedLog("auth.sign_in.limit_unavailable", "error", requestId, {
      component: "auth_password_sign_in",
      error_type: "limit_store",
    });
  }
  // Expected rejections stay in the abuse-prevention counters and warning
  // logs, but are excluded from both sides of the availability ratio.
  if (succeeded) {
    await recordCriticalFlowOutcome(
      serviceClient,
      "auth",
      "succeeded",
      requestId,
    );
  }
  if (!succeeded || !data.session) {
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
