import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  correlationId,
  integrationEnabled,
  sanitizedLog,
  withCorrelation,
} from "../_shared/observability.ts";

const headers = { "content-type": "application/json" };

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const respond = (response: Response) => withCorrelation(response, requestId);
  if (request.method !== "POST") {
    return respond(new Response("Method not allowed", { status: 405 }));
  }
  if (!integrationEnabled("observability")) {
    return respond(new Response(JSON.stringify({ error: "monitor_disabled" }), {
      status: 503,
      headers,
    }));
  }

  const url = Deno.env.get("SUPABASE_URL");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const secret = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) {
    return respond(new Response(JSON.stringify({ error: "monitor_unavailable" }), {
      status: 503,
      headers,
    }));
  }

  const client = createClient(url, secret, { auth: { persistSession: false } });
  const { data, error } = await client.schema("api").rpc(
    "get_critical_flow_ratios",
  );
  if (error) {
    sanitizedLog("critical_flow.monitor.failed", "error", requestId, {
      component: "critical_flow_monitor",
      error_type: error.code ?? "database",
    });
    return respond(new Response(JSON.stringify({ error: "query_failed" }), {
      status: 500,
      headers,
    }));
  }

  let breached = 0;
  const bridgeUrl = Deno.env.get("OBSERVABILITY_BRIDGE_URL");
  const bridgeToken = Deno.env.get("OBSERVABILITY_BRIDGE_TOKEN");
  for (const ratio of data ?? []) {
    if (!ratio.breached) continue;
    breached++;
    sanitizedLog("critical_flow.threshold_breached", "error", requestId, {
      component: "critical_flow_monitor",
      flow: ratio.flow,
      attempts: ratio.attempts,
      failure_rate_percent: Number(ratio.failure_rate_percent),
      window_minutes: 5,
    });
    if (!bridgeUrl || !bridgeToken) {
      return respond(new Response(JSON.stringify({ error: "bridge_unavailable" }), {
        status: 503,
        headers,
      }));
    }
    const bridgeResponse = await fetch(bridgeUrl, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-teamzone-bridge-token": bridgeToken,
      },
      body: JSON.stringify({
        flow: ratio.flow,
        attempts: ratio.attempts,
        failure_rate_percent: Number(ratio.failure_rate_percent),
        window_minutes: 5,
      }),
    });
    if (!bridgeResponse.ok) {
      sanitizedLog("critical_flow.bridge.failed", "error", requestId, {
        component: "critical_flow_monitor",
        flow: ratio.flow,
        error_type: `http_${bridgeResponse.status}`,
      });
      return respond(new Response(JSON.stringify({ error: "bridge_failed" }), {
        status: 502,
        headers,
      }));
    }
  }

  return respond(new Response(JSON.stringify({ checked: 4, breached }), {
    status: 200,
    headers,
  }));
});
