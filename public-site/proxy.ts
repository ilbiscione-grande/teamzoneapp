import { NextRequest, NextResponse } from "next/server";
import { serverConfig } from "./lib/config";
import { safeDomainDecision, normalizedHostname, validRoutingInput } from "./lib/domain-routing";
import { publicRpc } from "./lib/public-rpc";
import { createServerSupabase } from "./lib/supabase-admin";

// Public media tokens are already tenant-independent, opaque and resolved by a
// service-only lookup. They must retain the route's immutable image cache and
// must never be rewritten as club HTML on a custom hostname.
const bypassPrefixes = [
  "/_next/",
  "/api/",
  "/media/public/",
  "/favicon.ico",
  "/robots.txt",
];
const pageCache = "public, max-age=0, s-maxage=60, must-revalidate";

export async function proxy(request: NextRequest) {
  const path = request.nextUrl.pathname;
  if (bypassPrefixes.some((prefix) => path.startsWith(prefix))) {
    const response = NextResponse.next();
    if (path.startsWith("/api/")) response.headers.set("Cache-Control", "no-store");
    return response;
  }
  const hostname = normalizedHostname(request.nextUrl.hostname);
  if (!validRoutingInput(hostname, path)) {
    return new NextResponse("Not found", { status: 404, headers: { "x-teamzone-debug": "invalid_routing_input" } });
  }
  // TEMPORARY (remove once the 2026-09-05 fail-closed regression is diagnosed):
  // a response header survives even if console output from this runtime
  // never reaches Cloud Logging, so it can be read directly with curl -I.
  let debugTag = "no_branch_matched";
  try {
    const config = serverConfig();
    debugTag = "config_ok";
    const raw = await publicRpc(createServerSupabase(config), "resolve_public_hostname", { hostname, path });
    debugTag = "rpc_ok:" + JSON.stringify(raw).slice(0, 80);
    const decision = safeDomainDecision(raw);
    debugTag = "decision:" + decision.mode;
    if (decision.mode === "path") {
      const response = NextResponse.next();
      response.headers.set("Cache-Control", pageCache);
      return response;
    }
    if (decision.mode === "redirect") return NextResponse.redirect(decision.location, 308);
    if (decision.mode === "rewrite") {
      const target = request.nextUrl.clone();
      target.pathname = decision.internal_path;
      const requestHeaders = new Headers(request.headers);
      requestHeaders.set("x-teamzone-canonical-origin", decision.canonical_origin);
      requestHeaders.set("x-teamzone-original-path", path);
      const response = NextResponse.rewrite(target, { request: { headers: requestHeaders } });
      response.headers.set("Cache-Control", pageCache);
      return response;
    }
  } catch (error) {
    // Server-side only: never included in the client response. Diagnostic
    // aid for the otherwise-silent fail-closed 404 below (e.g. missing
    // server config, unreachable database, unexpected RPC shape).
    const name = (error as { name?: string } | undefined)?.name;
    const message = (error as { message?: string } | undefined)?.message;
    debugTag = "error:" + (name ?? "") + ":" + (message ?? "").slice(0, 120);
    console.error("proxy_fail_closed", { hostname, path, name, message });
  }
  return new NextResponse("Not found", {
    status: 404,
    headers: { "Cache-Control": "no-store", "x-teamzone-debug": debugTag },
  });
}

export const config = { matcher: ["/((?!_next/static|_next/image).*)"] };
