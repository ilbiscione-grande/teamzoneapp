import { NextRequest, NextResponse } from "next/server";
import { tacticsboardOnlyRedirect } from "./lib/site-scope";

export function proxy(request: NextRequest) {
  if (process.env.WEBTOOLS_SCOPE !== "tacticsboard") return NextResponse.next();
  const target = tacticsboardOnlyRedirect(request.nextUrl.pathname);
  if (!target) return NextResponse.next();
  const url = request.nextUrl.clone();
  url.pathname = target;
  url.search = "";
  return NextResponse.redirect(url, 307);
}

export const config = { matcher: ["/((?!_next/|api/|.*\\..*).*)"] };
