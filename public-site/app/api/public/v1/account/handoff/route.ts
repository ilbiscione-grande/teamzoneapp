import { createClient } from "@supabase/supabase-js";
import { serverConfig, siteOrigins } from "../../../../../../lib/config";
import { json, neutralError } from "../../../../../../lib/http";
import { assertSameOrigin } from "../../../../../../lib/request-security";
import { createServerSupabase } from "../../../../../../lib/supabase-admin";

export const dynamic = "force-dynamic";

// POOL-01: sign-in from the app. The app asks the database for a one-time
// code as the signed-in user and opens the site with it in the URL
// fragment; the page posts it here. The code is used once (two minutes,
// 256 bits), and the session is for that same user: a sign-in link is made
// server side (never e-mailed) and redeemed at once. Only the refresh token
// goes back, in the response body.

const code = /^[0-9a-f]{64}$/;
const refused = () => json({ error: "Inloggningen från appen gick inte att använda. Logga in här i stället." }, 401);

export async function POST(request: Request) {
  try {
    const config = serverConfig(true);
    assertSameOrigin(request, siteOrigins(config));
    if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
      return json({ error: "Begäran kunde inte behandlas." }, 415);
    }
    const body = await request.json().catch(() => ({})) as { code?: unknown };
    if (typeof body.code !== "string" || !code.test(body.code)) return refused();
    const publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY?.trim();
    if (!publishableKey) throw new Error("missing_server_config:SUPABASE_PUBLISHABLE_KEY");

    const admin = createServerSupabase(config);
    const { data: owner, error: consumeError } = await admin.schema("api").rpc("consume_web_handoff", { handoff_code: body.code });
    if (consumeError) throw consumeError;
    if (typeof owner !== "string") return refused();
    const { data: found, error: userError } = await admin.auth.admin.getUserById(owner);
    const email = found?.user?.email;
    if (userError || !email) return refused();
    const { data: link, error: linkError } = await admin.auth.admin.generateLink({ type: "magiclink", email });
    const tokenHash = link?.properties?.hashed_token;
    if (linkError || !tokenHash) throw linkError ?? new Error("handoff_link_failed");

    const auth = createClient(config.supabaseUrl, publishableKey, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
    const { data: verified, error: verifyError } = await auth.auth.verifyOtp({ token_hash: tokenHash, type: "magiclink" });
    if (verifyError || !verified.session || verified.user?.id !== owner) throw verifyError ?? new Error("handoff_verify_failed");
    return json({ refresh_token: verified.session.refresh_token });
  } catch (error) {
    return neutralError(error);
  }
}
