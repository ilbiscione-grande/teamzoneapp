// Supportens statistik för Tacticsboard (2026-11-14): Tacticsboard is sold
// from webtools.teamzoneapp.se, whose database is the production project, not
// this one. A support administrator signed in here gets that project's counts
// through this function. It checks the caller with api.is_support_admin here,
// then calls api.get_tacticsboard_usage_for_server there with that project's
// secret key. Counts only; nothing from the request reaches the query except
// the period.
//
// Secrets (set by the owner, never in the repository):
//   TACTICSBOARD_STATS_URL         https://<production ref>.supabase.co
//   TACTICSBOARD_STATS_SECRET_KEY  the production project's secret key
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";

const periods = new Set([7, 30, 90, 365]);

// Any origin, as for person-erasure-worker: the answer needs a support
// administrator's session, which a page cannot borrow (no cookies). The
// preflight allows the headers the browser asks for, so a client that adds
// one is not stopped before the request.
function headersFor(requested: string | null): Record<string, string> {
  const allowed = (requested ?? "")
    .split(",")
    .map((name) => name.trim().toLowerCase())
    .filter((name) => /^[a-z0-9-]{1,64}$/.test(name));
  return {
    "content-type": "application/json",
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers": [
      ...new Set([
        "authorization",
        "apikey",
        "content-type",
        "x-client-info",
        "x-correlation-id",
        ...allowed,
      ]),
    ].join(", "),
    "access-control-max-age": "600",
  };
}

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const headers = headersFor(
    request.headers.get("access-control-request-headers"),
  );
  const respond = (status: number, body: unknown) =>
    withCorrelation(
      new Response(JSON.stringify(body), { status, headers }),
      requestId,
    );
  if (request.method === "OPTIONS") {
    return withCorrelation(new Response(null, { status: 204, headers }), requestId);
  }
  if (request.method !== "POST") {
    return respond(405, { error: "method_not_allowed" });
  }

  const authorization = request.headers.get("authorization") ?? "";
  const url = Deno.env.get("SUPABASE_URL");
  const publishableKeys = JSON.parse(
    Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}",
  );
  const publishableKey = publishableKeys.default ??
    Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !publishableKey || !authorization.startsWith("Bearer ")) {
    return respond(503, { error: "gateway_unavailable" });
  }

  let periodDays = 30;
  try {
    const body = await request.json();
    if (body && typeof body === "object" && "period_days" in body) {
      periodDays = Number((body as Record<string, unknown>).period_days);
    }
  } catch {
    // An empty body asks for the default period.
  }
  if (!periods.has(periodDays)) {
    return respond(400, { error: "invalid_request" });
  }

  const userClient = createClient(url, publishableKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: authorization } },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  const { data: isSupportAdmin, error: adminError } = await userClient
    .schema("api").rpc("is_support_admin");
  if (authError || !authData.user || adminError || isSupportAdmin !== true) {
    sanitizedLog("support_tacticsboard_usage.rejected", "warning", requestId, {
      component: "support_tacticsboard_usage",
      error_type: "not_authorized",
    });
    return respond(404, { error: "not_found" });
  }

  const statsUrl = Deno.env.get("TACTICSBOARD_STATS_URL") ?? "";
  const statsKey = Deno.env.get("TACTICSBOARD_STATS_SECRET_KEY") ?? "";
  if (!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(statsUrl) || !statsKey) {
    return respond(503, { error: "not_configured" });
  }

  const production = createClient(statsUrl, statsKey, {
    auth: { persistSession: false },
  });
  const { data, error } = await production.schema("api").rpc(
    "get_tacticsboard_usage_for_server",
    { period_days: periodDays },
  );
  if (error || !data || typeof data !== "object") {
    sanitizedLog("support_tacticsboard_usage.failed", "error", requestId, {
      component: "support_tacticsboard_usage",
      error_type: error?.code ?? "empty_response",
    });
    return respond(502, { error: "source_unavailable" });
  }
  return respond(200, { source: new URL(statsUrl).hostname.split(".")[0], usage: data });
});
