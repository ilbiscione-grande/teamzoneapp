import { createServerSupabase } from "../../../../../../../lib/supabase-admin";
import { json, neutralError, requestIpHash } from "../../../../../../../lib/http";
import { publicRpc } from "../../../../../../../lib/public-rpc";

export const dynamic = "force-dynamic";

// Decision package 12 (PLM-08): the team page asks again every 20 seconds
// while a match is under way, through the same read path and rate limit as
// the page itself. Only published teams' reported matches come back.
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function GET(request: Request, context: { params: Promise<{ teamKey: string }> }) {
  try {
    const { teamKey: teamId } = await context.params;
    if (!uuid.test(teamId)) return json({ error: "Sidan kunde inte hittas." }, 404);
    const { config, ipHash } = requestIpHash(request);
    const data = await publicRpc(createServerSupabase(config), "public_team_live_matches", { team_id: teamId, ip_hash: ipHash });
    if (data?.available === false) return json({ error: "Tjänsten är tillfälligt otillgänglig." }, 503);
    return json(data);
  } catch (error) {
    return neutralError(error);
  }
}
