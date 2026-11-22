// The survey page's server side: the secret key never reaches the browser.
import { createHmac } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import type { PublicSurvey } from "./survey";

function serverClient() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SECRET_KEY;
  if (!url || !key) return null;
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    global: { headers: { "X-Client-Info": "teamzone-webtools-server/0.1" } },
  });
}

/** The survey behind a link, or null when there is none (or it is a draft). */
export async function loadPublicSurvey(token: string): Promise<PublicSurvey | null> {
  const client = serverClient();
  if (!client) return null;
  const { data, error } = await client.schema("api").rpc("public_get_team_survey", { public_token: token });
  if (error) {
    console.error("public survey", error.message);
    return null;
  }
  return !data || (data as { not_found?: boolean }).not_found ? null : (data as PublicSurvey);
}

/** The first address in X-Forwarded-For, hashed: only used to slow down floods on the open link. */
export function ipHash(forwardedFor: string | null): string {
  const ip = forwardedFor?.split(",")[0]?.trim() || "unknown";
  return createHmac("sha256", process.env.SUPABASE_SECRET_KEY ?? "webtools").update(`survey:${ip}`).digest("hex");
}

export async function submitPublicSurvey(token: string, name: string | null, answers: unknown, hash: string):
  Promise<{ accepted?: boolean; closed?: boolean; not_found?: boolean; error?: string }> {
  const client = serverClient();
  if (!client) return { error: "unavailable" };
  const { data, error } = await client.schema("api").rpc("public_submit_team_survey", {
    public_token: token, respondent_name: name, answers, ip_hash: hash,
  });
  if (error) return { error: error.message };
  return data as { accepted?: boolean; closed?: boolean; not_found?: boolean };
}
