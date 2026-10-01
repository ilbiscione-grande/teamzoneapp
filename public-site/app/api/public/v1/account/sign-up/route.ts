import { createClient } from "@supabase/supabase-js";
import { serverConfig, siteOrigins } from "../../../../../../lib/config";
import { verifyCaptcha } from "../../../../../../lib/captcha";
import { json, neutralError } from "../../../../../../lib/http";
import { confirmationRedirect, parseSignUp } from "../../../../../../lib/public-signup";
import { assertSameOrigin, resolveClientIp } from "../../../../../../lib/request-security";
import { createServerSupabase } from "../../../../../../lib/supabase-admin";
import { publicRpc } from "../../../../../../lib/public-rpc";

export const dynamic = "force-dynamic";

// The same answer whether or not the address already has an account.
const accepted = () => json({ accepted: true }, 202);

export async function POST(request: Request) {
  try {
    const config = serverConfig(true);
    const origins = siteOrigins(config);
    assertSameOrigin(request, origins);
    if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
      return json({ error: "Begäran kunde inte behandlas." }, 415);
    }
    const input = parseSignUp(await request.json());
    if (!input) return json({ error: "Kontrollera uppgifterna och försök igen." }, 400);
    const rawIp = resolveClientIp(request.headers.get("x-forwarded-for"), config.trustedProxyHops);
    const captcha = await verifyCaptcha(config, input.captchaToken, rawIp, "signup");
    if (!captcha.verified) return json({ error: "Verifieringen misslyckades. Försök igen." }, 400);
    const publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY?.trim();
    if (!publishableKey) throw new Error("missing_server_config:SUPABASE_PUBLISHABLE_KEY");
    const auth = createClient(config.supabaseUrl, publishableKey, {
      auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    });
    const origin = request.headers.get("origin")!;
    const { data, error } = await auth.auth.signUp({
      email: input.email,
      password: input.password,
      options: { data: { display_name: input.displayName, locale: "sv" }, emailRedirectTo: confirmationRedirect(origin) },
    });
    if (error) {
      if (error.code === "weak_password") return json({ error: "Välj ett starkare lösenord, minst 8 tecken." }, 400);
      if (error.status === 429) return json({ error: "För många försök. Försök senare." }, 429);
      if (error.code === "user_already_exists" || error.code === "email_exists") return accepted();
      throw new Error(error.message);
    }
    // An address that already has an account comes back without identities;
    // that account is left exactly as it is.
    const user = data.user;
    if (user && (user.identities?.length ?? 0) > 0) {
      await publicRpc(createServerSupabase(config), "mark_public_follower_account", {
        target_profile_id: user.id, legal_accepted: true,
      });
    }
    return accepted();
  } catch (error) {
    return neutralError(error);
  }
}
