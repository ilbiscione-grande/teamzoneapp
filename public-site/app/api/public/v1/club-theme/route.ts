import { clubThemeCss } from "../../../../../lib/club-theme";

// The colours are in the address and validated as plain hex, so the response
// is the same for everyone and can be cached for good.
export function GET(request: Request) {
  const url = new URL(request.url);
  const body = clubThemeCss(url.searchParams.get("p"), url.searchParams.get("a"));
  if (!body) return new Response("", { status: 400, headers: { "Content-Type": "text/css; charset=utf-8", "Cache-Control": "no-store" } });
  return new Response(body, {
    headers: {
      "Content-Type": "text/css; charset=utf-8",
      "Cache-Control": "public, max-age=31536000, immutable",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
