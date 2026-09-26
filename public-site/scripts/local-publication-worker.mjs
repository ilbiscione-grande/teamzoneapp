import { loadEnvFile } from "node:process";
import { fileURLToPath } from "node:url";

loadEnvFile(fileURLToPath(new URL("../.env.local", import.meta.url)));
const origin = process.env.PUBLIC_ORIGIN;
if (origin !== "http://localhost:5001"
  || process.env.SUPABASE_URL !== "https://hgcshgunvooyudvrcpig.supabase.co") {
  throw new Error("Expected local public server and approved test project");
}
const token = process.env.CACHE_INVALIDATION_SECRET?.trim();
if (!token || token.length < 32) throw new Error("Missing local worker configuration");
const mode = process.argv[2];
if (!["--check", "--once", "--watch"].includes(mode)) {
  throw new Error("Use --check, --once or --watch; running jobs needs explicit deployment approval");
}
if (mode === "--check") {
  console.log("Local worker configuration ready; no jobs processed.");
} else {
  let stopped = false;
  process.on("SIGINT", () => { stopped = true; });
  process.on("SIGTERM", () => { stopped = true; });
  do {
    try {
      const response = await fetch(`${origin}/api/internal/cache-invalidation`, {
        method: "POST", headers: { authorization: `Bearer ${token}` },
        signal: AbortSignal.timeout(20_000), redirect: "error",
      });
      if (!response.ok) throw new Error("Worker request failed");
      const result = await response.json();
      if (result.claimed || result.projected) console.log(JSON.stringify({
        projected: result.projected, claimed: result.claimed,
        completed: result.completed, failed: result.failed,
      }));
    } catch {
      console.error("Local publication worker failed; retry remains queued.");
      if (mode === "--once") process.exitCode = 1;
    }
    if (mode === "--watch" && !stopped) await new Promise(resolve => setTimeout(resolve, 10_000));
  } while (mode === "--watch" && !stopped);
}
