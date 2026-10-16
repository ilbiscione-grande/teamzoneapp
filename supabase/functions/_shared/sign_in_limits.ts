// Helpers for auth-password-sign-in: allowed web origins per environment,
// the client address and the hashed keys for the failed-sign-in limits
// (internal.sign_in_failures).

/// Production web origins. Local development origins are added only where
/// TEAMZONE_EXTRA_WEB_ORIGINS lists them (a comma-separated secret set on the
/// test project, never on production).
export const productionWebOrigins = [
  "https://app.teamzoneapp.se",
  // The public site; public.teamzoneapp.se redirects there (2026-10-16).
  "https://teamzoneapp.se",
  "https://public.teamzoneapp.se",
];

export function allowedWebOrigins(
  extra: string | undefined,
  production: readonly string[] = productionWebOrigins,
): Set<string> {
  const origins = new Set(production);
  for (const value of (extra ?? "").split(",")) {
    const origin = value.trim();
    if (/^https?:\/\/[a-z0-9.-]+(:\d{1,5})?$/i.test(origin)) origins.add(origin);
  }
  return origins;
}

/// The client address as the platform's proxy appended it: the last entry of
/// X-Forwarded-For (earlier entries can be sent by the client itself).
export function clientAddress(headers: Headers): string {
  const forwarded = (headers.get("x-forwarded-for") ?? "")
    .split(",")
    .map((part) => part.trim())
    .filter((part) => part.length > 0);
  const address = forwarded.at(-1) ?? headers.get("x-real-ip")?.trim() ?? "";
  return address.length > 0 && address.length <= 64 ? address : "unknown";
}

/// HMAC-SHA256 (hex) of a limit key, so neither the e-mail nor the address
/// is stored. E-mail is compared case-insensitively.
export async function limitKeyHash(
  secret: string,
  kind: "email" | "ip",
  value: string,
): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const normalized = kind === "email" ? value.trim().toLowerCase() : value;
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(`teamzone-sign-in:${kind}:${normalized}`),
  );
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
