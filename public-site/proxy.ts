import { NextRequest, NextResponse } from "next/server";
import { serverConfig } from "./lib/config";
import { safeDomainDecision, requestHostname, validRoutingInput } from "./lib/domain-routing";
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
  const hostname = requestHostname(request.headers, request.nextUrl.hostname);
  if (!validRoutingInput(hostname, path)) {
    return new NextResponse("Not found", { status: 404, headers: { "Cache-Control": "no-store" } });
  }
  try {
    const config = serverConfig();
    const raw = await publicRpc(createServerSupabase(config), "resolve_public_hostname", { hostname, path });
    const decision = safeDomainDecision(raw);
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
    console.error("proxy_fail_closed", {
      hostname,
      path,
      name: (error as { name?: string } | undefined)?.name,
      message: (error as { message?: string } | undefined)?.message,
    });
  }
  return new NextResponse("Not found", { status: 404, headers: { "Cache-Control": "no-store" } });
}

export const config = { matcher: ["/((?!_next/static|_next/image).*)"] };
