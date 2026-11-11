// Påminnelser via e-post (club-members-and-fees.md, step 5): the fee
// reminder's text and its unsubscribe link. The link names the e-mail (its
// id), never the address, and is signed so it cannot be guessed. Shared by
// fee-email-worker and fee-email-unsubscribe; nothing here logs addresses.

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

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** The signature of one e-mail's unsubscribe link (80 bits, hex). */
export async function unsubscribeSignature(secret: string, emailId: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(`fee-unsubscribe:${emailId.toLowerCase()}`));
  return hex(mac).slice(0, 20);
}

/** The unsubscribe link for one e-mail. */
export async function unsubscribeUrl(baseUrl: string, secret: string, emailId: string): Promise<string> {
  const id = emailId.toLowerCase();
  return `${baseUrl.replace(/\/+$/, "")}/functions/v1/fee-email-unsubscribe?id=${id}&s=${
    await unsubscribeSignature(secret, id)
  }`;
}

/** The e-mail id a link belongs to, or null when it is forged. */
export async function verifiedUnsubscribe(secret: string, id: string | null, signature: string | null) {
  const emailId = (id ?? "").toLowerCase();
  if (!uuidPattern.test(emailId) || !signature || secret.length < 32) return null;
  return constantTimeEqual(await unsubscribeSignature(secret, emailId), signature.toLowerCase()) ? emailId : null;
}

/** 30000 öre → "300 kr", 30050 → "300,50 kr". */
export function kronor(minor: number): string {
  const whole = Math.floor(minor / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  const rest = minor % 100;
  return rest === 0 ? `${whole} kr` : `${whole},${rest.toString().padStart(2, "0")} kr`;
}

export type FeeEmail = {
  clubName: string;
  title: string;
  dueOn: string;
  paymentInfo: string | null;
  fees: Array<{ name: string; amount: number }>;
  unsubscribeUrl: string;
};

export function feeEmailSubject(input: Pick<FeeEmail, "clubName" | "title">): string {
  return `Påminnelse: ${input.title} – ${input.clubName}`.replace(/[\r\n]/g, " ").slice(0, 200);
}

/** Plain text: what is owed, for whom, by when and how to pay. */
export function feeEmailText(input: FeeEmail): string {
  const total = input.fees.reduce((sum, fee) => sum + fee.amount, 0);
  const lines = [
    "Hej!",
    "",
    `Det här är en påminnelse från ${input.clubName} om en obetald avgift: ${input.title}.`,
    "",
    ...input.fees.map((fee) => `  ${fee.name}: ${kronor(fee.amount)}`),
    ...(input.fees.length > 1 ? [`  Totalt: ${kronor(total)}`] : []),
    "",
    `Sista betalningsdag: ${input.dueOn}`,
  ];
  if (input.paymentInfo && input.paymentInfo.trim()) {
    lines.push("", "Så betalar du:", input.paymentInfo.trim());
  }
  lines.push(
    "",
    "Har du redan betalat? Då kan du bortse från det här mejlet – klubben markerar avgiften när betalningen har kommit in.",
    "",
    "—",
    `Skickat av ${input.clubName} via TeamZone. Svara inte på det här mejlet, kontakta klubben om du har frågor.`,
    `Vill du inte få påminnelser om avgifter via e-post? Avregistrera dig här: ${input.unsubscribeUrl}`,
  );
  return lines.join("\n");
}
