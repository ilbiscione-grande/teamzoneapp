export const jsonHeaders = { "content-type": "application/json", "cache-control": "no-store" };

export function json(status: number, body: Record<string, unknown>, extraHeaders = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...jsonHeaders, ...extraHeaders } });
}

export function billingCorsHeaders(origin: string): Record<string, string> {
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers": "authorization, apikey, content-type, x-client-info",
    "vary": "Origin",
  };
}

export function billingRuntimeEnabled(): boolean {
  return Deno.env.get("BILLING_RUNTIME_ENABLED") === "true";
}

export function exactWebOrigin(): string | null {
  const value = Deno.env.get("BILLING_WEB_ORIGIN") ?? "";
  return /^https:\/\/[a-z0-9.-]+$/.test(value) ? value : null;
}
