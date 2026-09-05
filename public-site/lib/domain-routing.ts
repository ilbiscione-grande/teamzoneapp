export type DomainDecision =
  | { mode: "path" }
  | { mode: "redirect"; status: 308; location: string }
  | { mode: "rewrite"; club_slug: string; internal_path: string; canonical_origin: string }
  | { mode: "not_found"; not_found: true };

const hostnamePattern = /^(?=.{4,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;

export function normalizedHostname(value: string): string {
  return value.trim().toLowerCase().split(":", 1)[0].replace(/\.$/, "");
}

// Behind Firebase App Hosting's edge, the framework-reported request URL
// hostname is the container's own bind address, not the hostname the visitor
// requested, and the Host header is rewritten to the internal Cloud Run
// service hostname. The single trusted edge hop instead forwards the
// original hostname in X-Forwarded-Host. Falls back to Host, then the
// framework-reported hostname, only for direct/local requests that never
// passed through that edge.
export function requestHostname(headers: { get(name: string): string | null }, frameworkHostname: string): string {
  const forwardedHost = headers.get("x-forwarded-host");
  if (forwardedHost) return normalizedHostname(forwardedHost.split(",")[0]);
  const host = headers.get("host");
  if (host) return normalizedHostname(host);
  return normalizedHostname(frameworkHostname);
}

export function validRoutingInput(hostname: string, path: string): boolean {
  return hostnamePattern.test(hostname) && path.startsWith("/") && !/[?#]/.test(path) && path.length <= 2048;
}

export function safeDomainDecision(value: unknown): DomainDecision {
  if (!value || typeof value !== "object") return { mode: "not_found", not_found: true };
  const decision = value as Record<string, unknown>;
  if (decision.mode === "path") return { mode: "path" };
  if (decision.mode === "redirect" && decision.status === 308 && typeof decision.location === "string") {
    const target = new URL(decision.location);
    if (target.protocol !== "https:") return { mode: "not_found", not_found: true };
    return { mode: "redirect", status: 308, location: target.toString() };
  }
  if (decision.mode === "rewrite" && typeof decision.club_slug === "string"
    && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(decision.club_slug)
    && typeof decision.internal_path === "string" && decision.internal_path.startsWith(`/${decision.club_slug}`)
    && typeof decision.canonical_origin === "string" && new URL(decision.canonical_origin).protocol === "https:") {
    return decision as DomainDecision;
  }
  return { mode: "not_found", not_found: true };
}
