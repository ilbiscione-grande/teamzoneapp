const FLOWS = new Set(["auth", "checkout", "messaging", "critical_commands"]);

function sanitizedBreach(value) {
  if (!value || typeof value !== "object" || !FLOWS.has(value.flow)) return null;
  const attempts = Number(value.attempts);
  const failureRatePercent = Number(value.failure_rate_percent);
  if (!Number.isInteger(attempts) || attempts < 0 || attempts > 1000000) return null;
  if (!Number.isFinite(failureRatePercent) || failureRatePercent < 5 || failureRatePercent > 100) return null;
  if (value.window_minutes !== 5) return null;
  return {
    event: "teamzone.alert.critical_flow",
    flow: value.flow,
    attempts,
    failure_rate_percent: Math.round(failureRatePercent * 100) / 100,
    window_minutes: 5,
  };
}

module.exports = {sanitizedBreach};
