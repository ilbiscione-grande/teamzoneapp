// Helpers for push-callup-response and push-message-reply: the request
// shapes and how database refusals map to answers the app understands.

export type PushResponseRequest = { token: string; idempotencyKey: string };

const TOKEN = /^[0-9a-f]{64}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// Only a well-formed token and idempotency key pass; anything else is 400.
export function parsePushResponseRequest(body: unknown): PushResponseRequest | null {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const { token, idempotency_key: key } = body as Record<string, unknown>;
  if (typeof token !== "string" || !TOKEN.test(token)) return null;
  if (typeof key !== "string" || !UUID.test(key)) return null;
  return { token, idempotencyKey: key };
}

export type PushReplyRequest = PushResponseRequest & { body: string };

/// A reply also needs 1–4000 characters of text (trimmed by the database).
export function parsePushReplyRequest(body: unknown): PushReplyRequest | null {
  const parsed = parsePushResponseRequest(body);
  const text = (body as Record<string, unknown> | null)?.body;
  if (!parsed || typeof text !== "string") return null;
  const trimmed = text.trim();
  if (trimmed.length < 1 || trimmed.length > 4000) return null;
  return { ...parsed, body: text };
}

/// 410: the notification can no longer answer (expired, cancelled, already
/// answered differently); the app then opens the event. 409: the callup
/// changed meanwhile and a retry may work. Anything else is 500.
export function pushResponseStatus(message: string | undefined): 400 | 409 | 410 | 500 {
  switch (message) {
    case "invalid_input":
      return 400;
    case "stale_revision":
      return 409;
    case "invalid_or_expired_token":
    case "invalid_state":
    case "not_found":
    case "invalid_acting_as":
    case "announcement_closed":
      return 410;
    default:
      return 500;
  }
}
