import { createServerSupabase } from "../../../../../lib/supabase-admin";
import { json, neutralError, requestIpHash } from "../../../../../lib/http";
import { publicRpc } from "../../../../../lib/public-rpc";

export const dynamic = "force-dynamic";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const clubId = url.searchParams.get("club_id") ?? "";
    const teamId = url.searchParams.get("team_id");
    const beforeId = url.searchParams.get("before_id");
    if (!uuid.test(clubId) || (teamId && !uuid.test(teamId)) || (beforeId && !uuid.test(beforeId))) {
      return json({ error: "Begäran kunde inte behandlas." }, 400);
    }
    const { config, ipHash } = requestIpHash(request);
    const data = await publicRpc(createServerSupabase(config), "public_list_publications", {
      club_id: clubId,
      team_id: teamId,
      before_published_at: url.searchParams.get("before_published_at"),
      before_id: beforeId,
      ip_hash: ipHash,
      page_limit: Number.parseInt(url.searchParams.get("limit") ?? "20", 10),
    });
    return data?.available === false ? json({ error: "Tjänsten är tillfälligt otillgänglig." }, 503) : json(data);
  } catch (error) {
    return neutralError(error);
  }
}
