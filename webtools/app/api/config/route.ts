// The browser's account configuration, read at run time so one build serves
// any environment. Only the publishable key is ever handed out.
export const dynamic = "force-dynamic";

export function GET() {
  const url = process.env.SUPABASE_URL;
  const publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY;
  if (!url || !/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url) || !publishableKey?.startsWith("sb_publishable_")) {
    return Response.json({ available: false }, { status: 503 });
  }
  return Response.json({
    available: true,
    url,
    publishableKey,
    siteUrl: process.env.TEAMZONE_SITE_URL ?? "https://teamzoneapp.se",
    appUrl: process.env.TEAMZONE_APP_URL ?? "https://app.teamzoneapp.se",
  });
}
