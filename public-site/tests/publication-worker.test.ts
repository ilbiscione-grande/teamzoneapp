import assert from "node:assert/strict";
import test from "node:test";
import { runPublicationWorker } from "../lib/publication-worker.ts";

test("worker projects before invalidating and only completes after acknowledgement", async () => {
  const calls: string[] = [];
  const result = await runPublicationWorker(async (name, params) => {
    calls.push(name);
    if (name === "process_publication_projection_batch") return [{ state: "awaiting_invalidation" }];
    if (name === "claim_publication_delivery") return [{ id: "job", invalidation_token: "lease", affected_paths: ["/club/team"] }];
    assert.equal(params.succeeded, true);
    assert.equal(params.claim_token, "lease");
    return { state: "completed" };
  }, (path) => { calls.push(path); });
  assert.deepEqual(calls, ["process_publication_projection_batch", "claim_publication_delivery", "/club/team", "finish_publication_delivery"]);
  assert.equal(result.completed, 1);
});

for (const mode of ["invalid-path", "missing-path", "cache-failure", "stale-claim", "lost-receipt"] as const) {
  test(`worker handles ${mode} without claiming completion`, async () => {
    let acknowledged: unknown;
    const run = runPublicationWorker(async (name, params) => {
      if (name === "process_publication_projection_batch") return [];
      if (name === "claim_publication_delivery") return [{ id: "job", invalidation_token: "lease", affected_paths: mode === "invalid-path" ? ["https://external.example"] : mode === "missing-path" ? [] : ["/club"] }];
      acknowledged = params.succeeded;
      if (mode === "lost-receipt") throw new Error("timeout");
      return { state: mode === "stale-claim" ? "stale_claim" : "failed" };
    }, () => { if (mode === "cache-failure") throw new Error("cache unavailable"); });
    if (mode === "lost-receipt") await assert.rejects(run, /timeout/);
    else assert.equal((await run).completed, 0);
    assert.equal(acknowledged, mode === "stale-claim" || mode === "lost-receipt");
  });
}
