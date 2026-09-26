import { json } from "../../../../../lib/http";

export const dynamic = "force-dynamic";
export function GET() {
  if (process.env.PUBLIC_PERSONAL_HOME_ENABLED !== "1") return json({ available: false });
  const url = process.env.SUPABASE_URL;
  const publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY;
  // Never fall back to the privileged server key, even when configuration is missing.
  if (!url || !/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url) || !publishableKey?.startsWith("sb_publishable_")) {
    return json({ available: false }, 503);
  }
  return json({ available: true, url, publishableKey });
}
