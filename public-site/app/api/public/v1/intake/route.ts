import { serverConfig, siteOrigins } from "../../../../../lib/config";
import { verifyCaptcha } from "../../../../../lib/captcha";
import { json, neutralError } from "../../../../../lib/http";
import { parseIntake } from "../../../../../lib/intake";
import { assertSameOrigin, hmacHex, resolveClientIp } from "../../../../../lib/request-security";
import { createServerSupabase } from "../../../../../lib/supabase-admin";
import { publicRpc } from "../../../../../lib/public-rpc";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    const config = serverConfig(true);
    assertSameOrigin(request, siteOrigins(config));
    if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
      return json({ error: "Begäran kunde inte behandlas." }, 415);
    }
    const input = parseIntake(await request.json());
    if (!input) return json({ error: "Kontrollera uppgifterna och försök igen." }, 400);
    const rawIp = resolveClientIp(request.headers.get("x-forwarded-for"), config.trustedProxyHops);
    const captcha = await verifyCaptcha(config, input.captchaToken, rawIp, "intake");
    if (!captcha.verified) return json({ error: "Verifieringen misslyckades. Försök igen." }, 400);
    try {
      const data = await publicRpc(createServerSupabase(config), "public_submit_intake", {
        public_token: input.token,
        full_name: input.fullName,
        phone: input.phone,
        email: input.email,
        birth_date: input.birthDate,
        street_address: input.streetAddress,
        postal_code: input.postalCode,
        city: input.city,
        ip_hash: hmacHex(config.ipHmacSecret, rawIp),
      });
      if (data?.not_found) return json({ error: "Sidan är inte längre öppen. Be din ledare om en ny länk." }, 404);
      return json({ accepted: true }, 202);
    } catch (error) {
      const message = error instanceof Error ? error.message : "";
      if (message.includes("invalid_email")) return json({ error: "Kontrollera e-postadressen." }, 400);
      if (message.includes("invalid_phone")) return json({ error: "Kontrollera telefonnumret." }, 400);
      throw error;
    }
  } catch (error) {
    return neutralError(error);
  }
}
