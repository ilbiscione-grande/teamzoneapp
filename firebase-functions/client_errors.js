// Sanitized Flutter web error reports (PAR-OPS-05: web errors go to Google
// Cloud Logging). Only allowlisted identifiers pass; anything else in the
// body is dropped, and a record with an unexpected shape is rejected. A
// fatal report may carry its stack reduced to code locations (decided
// 2026-10-13); every frame is checked again here and one bad frame rejects
// the whole record rather than being cleaned up.
const IDENTIFIER = /^[A-Za-z0-9._-]{1,80}$/;
const ALLOWED_ORIGINS = new Set(["https://app.teamzoneapp.se"]);
const MAX_BODY_BYTES = 8192;
const MAX_FRAMES = 30;
// "#3 member (location:line[:column])", the format StackSanitizer emits.
const FRAME = /^#(\d{1,2}) (.+) \((.+?):(\d{1,7})(?::(\d{1,7}))?\)$/;
const MEMBER = /^(?:new )?[A-Za-z0-9_$.<>-]{1,120}$/;
const LOCATION = /^(?:package:[a-z0-9_]+(?:\/[A-Za-z0-9_.-]+)+\.dart|dart:[a-z_]+(?:\/[A-Za-z0-9_.-]+)*(?:\.dart)?|[A-Za-z0-9_.-]+\.(?:dart|js|mjs))$/;

function validFrame(frame, index) {
  if (typeof frame !== "string" || frame.length > 300) return false;
  const match = FRAME.exec(frame);
  if (!match || Number(match[1]) !== index) return false;
  const member = match[2].split("<anonymous closure>").join("<closure>");
  return MEMBER.test(member) && LOCATION.test(match[3]);
}

function allowedOrigin(origin, extraOrigins) {
  if (!origin) return false;
  if (ALLOWED_ORIGINS.has(origin)) return true;
  return (extraOrigins || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean)
    .includes(origin);
}

function sanitizedClientError(raw) {
  if (typeof raw !== "string" || Buffer.byteLength(raw) > MAX_BODY_BYTES) return null;
  let value;
  try {
    value = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  for (const key of ["operation", "error_type", "environment", "release"]) {
    if (typeof value[key] !== "string" || !IDENTIFIER.test(value[key])) return null;
  }
  if (typeof value.fatal !== "boolean") return null;
  let stack;
  if (value.stack !== undefined) {
    if (!value.fatal || !Array.isArray(value.stack) || value.stack.length === 0 ||
      value.stack.length > MAX_FRAMES || !value.stack.every(validFrame)) return null;
    stack = value.stack;
  }
  return {
    event: "teamzone.client.error",
    platform: "web",
    operation: value.operation,
    error_type: value.error_type,
    fatal: value.fatal,
    environment: value.environment,
    release: value.release,
    ...(stack ? {stack} : {}),
  };
}

// Best effort per instance (maxInstances bounds the total): at most
// LIMIT_PER_MINUTE records per client address and minute.
const LIMIT_PER_MINUTE = 30;
const recent = new Map();

function withinLimit(address, now = Date.now()) {
  const minute = Math.floor(now / 60000);
  const key = `${address}:${minute}`;
  const count = (recent.get(key) || 0) + 1;
  recent.set(key, count);
  if (recent.size > 5000) {
    for (const stale of recent.keys()) {
      if (!stale.endsWith(`:${minute}`)) recent.delete(stale);
    }
  }
  return count <= LIMIT_PER_MINUTE;
}

module.exports = {allowedOrigin, sanitizedClientError, withinLimit, LIMIT_PER_MINUTE};
