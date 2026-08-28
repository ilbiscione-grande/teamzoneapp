const {timingSafeEqual} = require("node:crypto");
const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const {error} = require("firebase-functions/logger");
const {sanitizedBreach} = require("./bridge");

const bridgeToken = defineSecret("TEAMZONE_OBSERVABILITY_BRIDGE_TOKEN");
const supabaseAnonKey = defineSecret("TEAMZONE_SUPABASE_ANON_KEY");

function tokenMatches(provided, expected) {
  const left = Buffer.from((provided || "").trim());
  const right = Buffer.from((expected || "").trim());
  return left.length === right.length && left.length >= 32 && timingSafeEqual(left, right);
}

exports.criticalFlowAlertBridge = onRequest(
  {region: "europe-west1", secrets: [bridgeToken], timeoutSeconds: 15, memory: "256MiB"},
  (request, response) => {
    response.set("x-teamzone-bridge-version", "2");
    if (request.method !== "POST") return response.status(405).send("Method not allowed");
    if (!tokenMatches(request.get("x-teamzone-bridge-token"), bridgeToken.value())) {
      return response.status(401).send("Unauthorized");
    }
    const breach = sanitizedBreach(request.body);
    if (!breach) return response.status(400).send("Invalid aggregate");
    error("TeamZone critical-flow threshold breached", breach);
    return response.status(202).json({accepted: true});
  },
);

exports.runCriticalFlowMonitor = onSchedule(
  {
    schedule: "every 5 minutes",
    region: "europe-west1",
    timeZone: "Etc/UTC",
    retryCount: 1,
    secrets: [supabaseAnonKey],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async () => {
    const key = supabaseAnonKey.value().trim();
    const response = await fetch(
      "https://hgcshgunvooyudvrcpig.supabase.co/functions/v1/critical-flow-monitor",
      {
        method: "POST",
        headers: {apikey: key, authorization: `Bearer ${key}`},
      },
    );
    if (!response.ok) {
      error("TeamZone critical-flow monitor invocation failed", {
        event: "teamzone.alert.monitor_invocation_failed",
        status: response.status,
      });
      throw new Error(`sanitized_http_${response.status}`);
    }
  },
);
