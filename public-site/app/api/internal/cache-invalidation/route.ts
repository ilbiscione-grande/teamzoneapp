import { revalidatePath } from "next/cache";
import { json } from "../../../../lib/http";
import { publicRpc } from "../../../../lib/public-rpc";
import { serverConfig } from "../../../../lib/config";
import { createServerSupabase } from "../../../../lib/supabase-admin";
import { validWorkerBearer } from "../../../../lib/worker-auth";

export const dynamic = "force-dynamic";
const safePath = /^\/[a-z0-9][a-z0-9/-]{0,500}$/;

export async function POST(request: Request) {
  const workerSecret = process.env.CACHE_INVALIDATION_SECRET?.trim() ?? "";
  if (!validWorkerBearer(request.headers.get("authorization"), workerSecret)) {
    return json({ error: "not_found" }, 404);
  }
  const client = createServerSupabase(serverConfig());
  const jobs = await publicRpc(client, "claim_publication_invalidation_jobs", { batch_size: 20 }) as Array<{ id: string; affected_paths?: unknown }>;
  let completed = 0;
  for (const job of jobs) {
    try {
      const paths = Array.isArray(job.affected_paths) ? job.affected_paths : [];
      if (paths.length > 20 || paths.some((path) => typeof path !== "string" || !safePath.test(path))) throw new Error("invalid_path");
      for (const path of paths) revalidatePath(path);
      await publicRpc(client, "finish_publication_invalidation", { job_id: job.id, succeeded: true, error_code: null });
      completed += 1;
    } catch {
      await publicRpc(client, "finish_publication_invalidation", { job_id: job.id, succeeded: false, error_code: "invalidation_failed" });
    }
  }
  return json({ claimed: jobs.length, completed }, 200);
}
