import { NextRequest, NextResponse } from "next/server";
import { serverConfig } from "./lib/config";
import { safeDomainDecision, normalizedHostname, validRoutingInput } from "./lib/domain-routing";
import { publicRpc } from "./lib/public-rpc";
import { createServerSupabase } from "./lib/supabase-admin";

const bypassPrefixes = ["/_next/", "/api/", "/favicon.ico", "/robots.txt"];
const pageCache = "public, max-age=0, s-maxage=60, must-revalidate";

export async function proxy(request: NextRequest) {
  const path = request.nextUrl.pathname;
  if (bypassPrefixes.some((prefix) => path.startsWith(prefix))) {
    const response = NextResponse.next();
    if (path.startsWith("/api/")) response.headers.set("Cache-Control", "no-store");
    return response;
  }
  const hostname = normalizedHostname(request.nextUrl.hostname);
  if (!validRoutingInput(hostname, path)) return new NextResponse("Not found", { status: 404 });
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
  } catch { /* fail closed below */ }
  return new NextResponse("Not found", { status: 404, headers: { "Cache-Control": "no-store" } });
}

export const config = { matcher: ["/((?!_next/static|_next/image).*)"] };
