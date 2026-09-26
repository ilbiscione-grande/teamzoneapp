import { revalidatePath } from "next/cache";
import { json } from "../../../../lib/http";
import { publicRpc } from "../../../../lib/public-rpc";
import { serverConfig } from "../../../../lib/config";
import { createServerSupabase } from "../../../../lib/supabase-admin";
import { validWorkerBearer } from "../../../../lib/worker-auth";
import { runPublicationWorker } from "../../../../lib/publication-worker";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const workerSecret = process.env.CACHE_INVALIDATION_SECRET?.trim() ?? "";
  if (!validWorkerBearer(request.headers.get("authorization"), workerSecret)) {
    return json({ error: "not_found" }, 404);
  }
  try {
    const client = createServerSupabase(serverConfig());
    const result = await runPublicationWorker(
      (name, params) => publicRpc(client, name, params),
      (path) => revalidatePath(path),
    );
    return json(result, result.failed ? 503 : 200);
  } catch { return json({ error: "worker_unavailable" }, 503); }
}
