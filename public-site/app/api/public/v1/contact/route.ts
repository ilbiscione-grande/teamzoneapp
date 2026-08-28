import { serverConfig } from "../../../../../lib/config";
import { verifyCaptcha } from "../../../../../lib/captcha";
import { json, neutralError } from "../../../../../lib/http";
import { assertSameOrigin, hmacHex, resolveClientIp } from "../../../../../lib/request-security";
import { createServerSupabase } from "../../../../../lib/supabase-admin";
import { publicRpc } from "../../../../../lib/public-rpc";

export const dynamic = "force-dynamic";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type ContactBody = {
  clubId?: unknown;
  senderName?: unknown;
  senderEmail?: unknown;
  subject?: unknown;
  message?: unknown;
  captchaToken?: unknown;
};

export async function POST(request: Request) {
  try {
    const config = serverConfig(true);
    assertSameOrigin(request, config.publicOrigin);
    if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
      return json({ error: "Begäran kunde inte behandlas." }, 415);
    }
    const body = await request.json() as ContactBody;
    if (typeof body.clubId !== "string" || !uuid.test(body.clubId)
      || typeof body.senderName !== "string" || typeof body.senderEmail !== "string"
      || typeof body.subject !== "string" || typeof body.message !== "string"
      || typeof body.captchaToken !== "string") {
      return json({ error: "Begäran kunde inte behandlas." }, 400);
    }
    const rawIp = resolveClientIp(request.headers.get("x-forwarded-for"), config.trustedProxyHops);
    const captcha = await verifyCaptcha(config, body.captchaToken, rawIp);
    if (!captcha.verified) return json({ error: "Verifieringen misslyckades." }, 400);
    const data = await publicRpc(createServerSupabase(config), "public_submit_contact", {
      club_id: body.clubId,
      sender_name: body.senderName,
      sender_email: body.senderEmail,
      subject: body.subject,
      message_body: body.message,
      ip_hash: hmacHex(config.ipHmacSecret, rawIp),
      captcha_verified: true,
      captcha_assertion_hash: captcha.assertionHash,
    });
    if (data?.code === "unavailable") return json({ error: "Tjänsten är tillfälligt otillgänglig." }, 503);
    return json({ accepted: true, reference: data?.reference ?? null }, 202);
  } catch (error) {
    return neutralError(error);
  }
}
