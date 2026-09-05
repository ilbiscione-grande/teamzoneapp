import { NextResponse } from "next/server";
import { serverConfig } from "./config";
import { hmacHex, resolveClientIp } from "./request-security";

export const noStoreHeaders = {
  "Cache-Control": "no-store, max-age=0",
  "Content-Type": "application/json; charset=utf-8",
};

export function json(data: unknown, status = 200): NextResponse {
  return NextResponse.json(data, { status, headers: noStoreHeaders });
}

export function requestIpHash(request: Request): { config: ReturnType<typeof serverConfig>; ipHash: string; rawIp: string } {
  const config = serverConfig();
  const rawIp = resolveClientIp(request.headers.get("x-forwarded-for"), config.trustedProxyHops);
  return { config, rawIp, ipHash: hmacHex(config.ipHmacSecret, rawIp) };
}

export function neutralError(error: unknown): NextResponse {
  const message = typeof error === "object" && error && "message" in error ? String(error.message) : "";
  // Server-side only: never included in the client response. Diagnostic aid
  // for otherwise-silent fail-closed responses (e.g. missing server config,
  // unreachable database) that would be invisible in Cloud Logging otherwise.
  console.error("neutral_error", { name: (error as { name?: string } | undefined)?.name, message });
  if (message.includes("rate_limited")) return json({ error: "För många försök. Försök senare." }, 429);
  if (message.includes("invalid_request")) return json({ error: "Begäran kunde inte behandlas." }, 400);
  return json({ error: "Tjänsten är tillfälligt otillgänglig." }, 503);
}
