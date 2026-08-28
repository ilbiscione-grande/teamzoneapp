export type CheckoutRequest = {
  clubId: string;
  planKey: "plan.free" | "plan.small" | "plan.medium" | "plan.large";
  interval: "month" | "year";
  idempotencyKey: string;
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const plan = /^plan\.(free|small|medium|large)$/;

export function parseCheckoutRequest(value: unknown): CheckoutRequest | null {
  if (!value || typeof value !== "object") return null;
  const body = value as Record<string, unknown>;
  if (Object.keys(body).sort().join(",") !== "clubId,idempotencyKey,interval,planKey") return null;
  if (typeof body.clubId !== "string" || !uuid.test(body.clubId)
      || typeof body.planKey !== "string" || !plan.test(body.planKey)
      || (body.interval !== "month" && body.interval !== "year")
      || typeof body.idempotencyKey !== "string" || !uuid.test(body.idempotencyKey)) return null;
  return body as CheckoutRequest;
}
