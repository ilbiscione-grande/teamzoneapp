import { createHmac } from "node:crypto";

export function resolveClientIp(forwardedFor: string | null, trustedProxyHops: number): string {
  if (!forwardedFor) throw new Error("client_ip_unavailable");
  const chain = forwardedFor.split(",").map((part) => part.trim()).filter(Boolean);
  const index = chain.length - 1 - trustedProxyHops;
  if (index < 0 || !chain[index] || chain[index].length > 64) throw new Error("client_ip_unavailable");
  return chain[index];
}

export function hmacHex(secret: string, value: string): string {
  return createHmac("sha256", secret).update(value, "utf8").digest("hex");
}

export function assertSameOrigin(request: Request, publicOrigin: string): void {
  const origin = request.headers.get("origin");
  if (origin !== publicOrigin) throw new Error("origin_denied");
}
