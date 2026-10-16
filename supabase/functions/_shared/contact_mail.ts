// PUB-14: e-mail threads for messages from the club site. Shared by
// contact-email-worker (answers out) and contact-inbound (replies in). The
// reply address binds a reply to one thread with an HMAC, so it cannot be
// guessed or moved to another thread; Resend's webhook is verified with its
// Svix signature. Nothing here logs addresses or message text.

const encoder = new TextEncoder();

function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function constantTimeEqual(left: string, right: string): boolean {
  let mismatch = left.length ^ right.length;
  for (let index = 0; index < Math.min(left.length, right.length); index++) {
    mismatch |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return mismatch === 0;
}

async function hmacSha256(key: Uint8Array, message: string): Promise<ArrayBuffer> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return await crypto.subtle.sign("HMAC", cryptoKey, encoder.encode(message));
}

export const replyDomain = "reply.teamzoneapp.se";
// The part before @ may be at most 64 characters (RFC 5321): "svar+", the
// thread id without dashes (32) and an 80-bit signature (20) make 58.
const replyPattern = /^svar\+([0-9a-f]{32})\.([0-9a-f]{20})@reply\.teamzoneapp\.se$/;

async function threadSignature(secret: string, threadId: string): Promise<string> {
  return hex(await hmacSha256(encoder.encode(secret), `contact-reply:${threadId}`)).slice(0, 20);
}

/** The Reply-To address for one thread (the submission's public id). */
export async function replyAddress(secret: string, threadId: string): Promise<string> {
  const id = threadId.toLowerCase();
  return `svar+${id.replace(/-/g, "")}.${await threadSignature(secret, id)}@${replyDomain}`;
}

/** The thread a reply address belongs to, or null when it is not ours or forged. */
export async function threadFromReplyAddress(secret: string, address: string): Promise<string | null> {
  const match = replyPattern.exec(address.trim().toLowerCase());
  if (!match) return null;
  const compact = match[1];
  const id = `${compact.slice(0, 8)}-${compact.slice(8, 12)}-${compact.slice(12, 16)}-${compact.slice(16, 20)}-${compact.slice(20)}`;
  const expected = await threadSignature(secret, id);
  return constantTimeEqual(expected, match[2]) ? id : null;
}

/** The bare address from "Name <a@b.se>" or "a@b.se". */
export function emailAddress(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const angle = /<([^<>\s]+@[^<>\s]+)>/.exec(value);
  const raw = (angle ? angle[1] : value).trim().toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(raw) && raw.length <= 254 ? raw : null;
}

/**
 * Verifies a Svix-signed webhook (Resend): HMAC-SHA256 over
 * "id.timestamp.body" with the base64 secret after "whsec_", any of the
 * space-separated "v1,<base64>" signatures, timestamp within five minutes.
 */
export async function verifySvixSignature(
  secret: string,
  headers: { id: string | null; timestamp: string | null; signature: string | null },
  body: string,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<boolean> {
  const { id, timestamp, signature } = headers;
  if (!secret.startsWith("whsec_") || !id || !timestamp || !signature) return false;
  const sent = Number(timestamp);
  if (!Number.isInteger(sent) || Math.abs(nowSeconds - sent) > 300) return false;
  let key: Uint8Array;
  try {
    key = Uint8Array.from(atob(secret.slice("whsec_".length)), (c) => c.charCodeAt(0));
  } catch {
    return false;
  }
  const expected = btoa(String.fromCharCode(...new Uint8Array(await hmacSha256(key, `${id}.${timestamp}.${body}`))));
  return signature.split(" ").some((part) => {
    const [version, value] = part.split(",", 2);
    return version === "v1" && typeof value === "string" && constantTimeEqual(value, expected);
  });
}

/** Out-of-office answers, bounces and list mail never enter a thread. */
export function isAutomatic(headers: Record<string, unknown>, subject: string): boolean {
  const header = (name: string) => {
    const value = headers[name] ?? headers[name.toLowerCase()];
    return typeof value === "string" ? value.toLowerCase() : "";
  };
  const autoSubmitted = header("auto-submitted");
  if (autoSubmitted && autoSubmitted !== "no") return true;
  if (header("x-autoreply") || header("x-autorespond") || header("x-auto-response-suppress")) return true;
  if (["bulk", "junk", "list", "auto_reply"].includes(header("precedence"))) return true;
  if (header("list-id") || header("list-unsubscribe")) return true;
  return /^(automatic reply|auto(matic)?[- ]?(reply|svar)|autosvar|out of office|frånvaro|abwesenheit|undeliverable|delivery status notification)/i
    .test(subject.trim());
}

/** SPF, DKIM and DMARC as Resend reports them: DMARC must pass. */
export function authenticated(authentication: unknown): boolean {
  if (!authentication || typeof authentication !== "object") return false;
  const result = (key: string) => {
    const value = (authentication as Record<string, unknown>)[key];
    const text = typeof value === "string" ? value : (value as { result?: unknown } | null)?.result;
    return typeof text === "string" ? text.toLowerCase() : "";
  };
  return result("dmarc") === "pass";
}

// A mail app's own footer ("Skickat från min iPhone", "Hämta Outlook för
// Android", "Sent from Mail for Windows"), only as the reply's last line.
const appSignature =
  /^\s*(skickat från|sänt från|skickad från|sent from|hämta|get)\s+(min[a-z]*\s+|my\s+)?(iphone|ipad|android|outlook|mail|e-post|gmail|yahoo|samsung|galaxy|huawei|xiaomi|oneplus|pixel|mobil|smartphone)\b(\s+[\wåäö-]+){0,4}[\s.!]*$/i;

/**
 * The new text of a reply: plain text only, without the quoted earlier
 * mail ("Den ... skrev:", "On ... wrote:", "> ..." and forwarded headers),
 * a "-- " signature or a mail app's "Skickat från ..." footer.
 */
export function replyText(text: unknown, html: unknown): string {
  let body = typeof text === "string" && text.trim()
    ? text
    : typeof html === "string"
    ? html.replace(/<(br|\/p|\/div)\s*\/?>/gi, "\n").replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ")
      .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
    : "";
  body = body.replace(/\r\n/g, "\n");
  const lines = body.split("\n");
  const cut = lines.findIndex((line) =>
    /^\s*>/.test(line) ||
    // "On … wrote:", and Swedish "Den … skrev Namn <adress>:".
    (/^\s*(den|on|am|le)\s/i.test(line) && /\b(skrev|wrote|schrieb|a écrit)\b/i.test(line) && /:\s*$/.test(line)) ||
    /^\s*-{2,}\s*(original message|ursprungligt meddelande|vidarebefordrat meddelande|forwarded message)/i.test(line) ||
    /^\s*(från|from)\s*:\s.+/i.test(line) && /@/.test(line) ||
    // The standard signature separator (RFC 3676): everything after it.
    line === "-- "
  );
  const kept = cut >= 0 ? lines.slice(0, cut) : lines;
  // The footer goes, but never the whole reply.
  while (kept.length > 1 && (kept[kept.length - 1].trim() === "" || appSignature.test(kept[kept.length - 1]))) {
    kept.pop();
  }
  return kept.join("\n").replace(/\n{3,}/g, "\n\n").trim().slice(0, 5000);
}

/** The answer e-mail's text: the answer, a footer and the quoted original. */
export function answerText(input: {
  body: string;
  sender: string;
  originalAt: string;
  originalBody: string;
}): string {
  const date = new Date(input.originalAt);
  const when = Number.isNaN(date.getTime())
    ? ""
    : date.toLocaleDateString("sv-SE", { timeZone: "Europe/Stockholm" });
  return [
    input.body,
    "",
    "—",
    `Skickat av ${input.sender} via TeamZone. Svara på det här mejlet för att fortsätta konversationen.`,
    "Du får det här mejlet eftersom du skrev till dem via deras sida på teamzoneapp.se.",
    "",
    `Ditt meddelande${when ? ` ${when}` : ""}:`,
    ...input.originalBody.slice(0, 2000).split("\n").map((line) => `> ${line}`),
  ].join("\n");
}
