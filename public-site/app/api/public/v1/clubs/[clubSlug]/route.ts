import { createServerSupabase } from "../../../../../../lib/supabase-admin";
import { json, neutralError, requestIpHash } from "../../../../../../lib/http";
import { publicRpc } from "../../../../../../lib/public-rpc";

export const dynamic = "force-dynamic";

export async function GET(request: Request, context: { params: Promise<{ clubSlug: string }> }) {
  try {
    const { clubSlug } = await context.params;
    const { config, ipHash } = requestIpHash(request);
    const data = await publicRpc(createServerSupabase(config), "public_get_club", {
      slug: clubSlug, ip_hash: ipHash,
    });
    if (data?.available === false) return json({ error: "Tjänsten är tillfälligt otillgänglig." }, 503);
    return data?.not_found ? json({ error: "Sidan kunde inte hittas." }, 404) : json(data);
  } catch (error) {
    return neutralError(error);
  }
}
