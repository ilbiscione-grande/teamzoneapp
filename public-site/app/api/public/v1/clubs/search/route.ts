import { createServerSupabase } from "../../../../../../lib/supabase-admin";
import { json, neutralError, requestIpHash } from "../../../../../../lib/http";
import { publicRpc } from "../../../../../../lib/public-rpc";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const query = url.searchParams.get("q") ?? "";
    const pageLimit = Number.parseInt(url.searchParams.get("limit") ?? "10", 10);
    const { config, ipHash } = requestIpHash(request);
    const data = await publicRpc(createServerSupabase(config), "public_search_clubs", {
      query, ip_hash: ipHash, page_limit: pageLimit,
    });
    return data?.available === false ? json({ error: "Tjänsten är tillfälligt otillgänglig." }, 503) : json(data);
  } catch (error) {
    return neutralError(error);
  }
}
