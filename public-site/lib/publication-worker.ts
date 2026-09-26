type Rpc = (name: string, params: Record<string, unknown>) => Promise<unknown>;
type Delivery = { id: string; affected_paths: string[]; invalidation_token: string };
const safePath = /^\/[a-z0-9][a-z0-9/-]{0,500}$/;

export async function runPublicationWorker(rpc: Rpc, invalidate: (path: string) => void | Promise<void>) {
  const projected = await rpc("process_publication_projection_batch", { batch_size: 20 });
  if (!Array.isArray(projected)) throw new Error("invalid_worker_response");
  const jobs = await rpc("claim_publication_delivery", { batch_size: 20 });
  if (!Array.isArray(jobs)) throw new Error("invalid_worker_response");
  let completed = 0;
  let failed = projected.filter((job) => job?.state === "failed").length;
  for (const job of jobs as Delivery[]) {
    let succeeded = false;
    try {
      if (!Array.isArray(job.affected_paths) || job.affected_paths.length === 0
        || job.affected_paths.length > 20
        || job.affected_paths.some((path) => typeof path !== "string" || !safePath.test(path))) {
        throw new Error("invalid_path");
      }
      for (const path of job.affected_paths) await invalidate(path);
      succeeded = true;
    } catch { failed++; }
    // An uncertain acknowledgement is retried by the claim lease, never guessed successful.
    const receipt = await rpc("finish_publication_delivery", {
      job_id: job.id, claim_token: job.invalidation_token, succeeded,
    }) as { state?: string } | null;
    if (receipt?.state === "completed") completed++;
  }
  return { projected: projected.length, claimed: jobs.length, completed, failed };
}
