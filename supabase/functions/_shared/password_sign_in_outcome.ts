// Classify by documented Auth codes, never by a message containing user data.
// Unknown errors remain operational failures so new faults cannot be hidden.
const expectedRejections = new Set([
  "invalid_credentials",
  "email_not_confirmed",
  "phone_not_confirmed",
  "user_banned",
]);

export function passwordSignInOutcome(
  error: { code?: string; status?: number } | null,
  hasSession: boolean,
): "succeeded" | "rejected" | "limited" | "failed" {
  if (!error) return hasSession ? "succeeded" : "failed";
  if (error.status === 0 || (error.status ?? 0) >= 500) return "failed";
  if (error.status === 429) return "limited";
  if (expectedRejections.has(error.code ?? "")) return "rejected";
  return "failed";
}
