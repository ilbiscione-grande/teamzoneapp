const SAFE_DIMENSIONS = new Set([
  "operation",
  "component",
  "result",
  "duration_bucket",
  "error_type",
  "flow",
  "attempts",
  "failure_rate_percent",
  "window_minutes",
]);

type RpcResult = { error: { code?: string } | null };
type ServiceClient = {
  schema(name: string): {
    rpc(name: string, parameters: Record<string, unknown>): PromiseLike<RpcResult>;
  };
};

function identifier(value: string): string {
  return value.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 80);
}

export function correlationId(request: Request): string {
  const supplied = request.headers.get("x-correlation-id") ?? "";
  return /^[a-zA-Z0-9._-]{8,80}$/.test(supplied)
    ? supplied
    : crypto.randomUUID();
}

export function sanitizedLog(
  event: string,
  severity: "debug" | "info" | "warning" | "error" | "fatal",
  requestCorrelationId: string,
  dimensions: Record<string, unknown> = {},
): void {
  const safe: Record<string, string | number | boolean | null> = {};
  for (const [key, value] of Object.entries(dimensions)) {
    if (!SAFE_DIMENSIONS.has(key)) continue;
    if (
      value === null || typeof value === "boolean" || typeof value === "number"
    ) {
      safe[key] = value;
    } else if (
      typeof value === "string" && value.length <= 80 && !value.includes("@")
    ) {
      safe[key] = identifier(value);
    }
  }
  console.log(JSON.stringify({
    event: identifier(event),
    severity,
    environment: identifier(Deno.env.get("TEAMZONE_ENV") ?? "unknown"),
    release: identifier(Deno.env.get("DENO_DEPLOYMENT_ID") ?? "local"),
    correlation_id: identifier(requestCorrelationId),
    dimensions: safe,
  }));
}

export function withCorrelation(response: Response, id: string): Response {
  const headers = new Headers(response.headers);
  headers.set("x-correlation-id", identifier(id));
  return new Response(response.body, { status: response.status, headers });
}

export function integrationEnabled(name: string): boolean {
  return Deno.env.get(`${identifier(name).toUpperCase()}_RUNTIME_ENABLED`) ===
    "true";
}

export async function recordCriticalFlowOutcome(
  client: ServiceClient,
  flow: "auth" | "checkout" | "messaging" | "critical_commands",
  result: "succeeded" | "failed",
  requestCorrelationId: string,
): Promise<void> {
  const { error } = await client.schema("api").rpc(
    "record_critical_flow_outcome",
    { target_flow: flow, target_result: result },
  );
  if (error) {
    sanitizedLog("observability.counter.failed", "warning", requestCorrelationId, {
      component: "critical_flow_counter",
      flow,
      error_type: error.code ?? "database",
    });
  }
}
