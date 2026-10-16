import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import {
  answerText,
  authenticated,
  emailAddress,
  isAutomatic,
  replyAddress,
  replyText,
  threadFromReplyAddress,
  verifySvixSignature,
} from "../_shared/contact_mail.ts";

const secret = "test-reply-secret-0123456789abcdef";
const thread = "6f0e8a1c-2b3d-4e5f-8a9b-0c1d2e3f4a5b";

Deno.test("a reply address belongs to one thread and cannot be forged", async () => {
  const address = await replyAddress(secret, thread);
  assert(/^svar\+6f0e8a1c2b3d4e5f8a9b0c1d2e3f4a5b\.[0-9a-f]{20}@reply\.teamzoneapp\.se$/.test(address));
  // RFC 5321: at most 64 characters before @ (Resend refuses longer).
  assert(address.split("@")[0].length <= 64);
  assertEquals(await threadFromReplyAddress(secret, address), thread);
  assertEquals(await threadFromReplyAddress(secret, address.toUpperCase()), thread);
  // Another thread id with this signature, a wrong secret or domain: refused.
  const other = address.replace("0c1d2e3f4a5b", "0c1d2e3f4a5c");
  assertEquals(await threadFromReplyAddress(secret, other), null);
  assertEquals(await threadFromReplyAddress("another-secret-0123456789abcdef", address), null);
  assertEquals(await threadFromReplyAddress(secret, address.replace("reply.teamzoneapp.se", "evil.example")), null);
  assertEquals(await threadFromReplyAddress(secret, "svar@reply.teamzoneapp.se"), null);
});

Deno.test("sender addresses are parsed strictly", () => {
  assertEquals(emailAddress("Ada Andersson <Ada@Example.se>"), "ada@example.se");
  assertEquals(emailAddress("bo@example.se"), "bo@example.se");
  assertEquals(emailAddress("not an address"), null);
  assertEquals(emailAddress(42), null);
});

async function svixSign(secretKey: string, id: string, timestamp: string, body: string) {
  const key = Uint8Array.from(atob(secretKey.slice(6)), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey("raw", key as BufferSource, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(`${id}.${timestamp}.${body}`));
  return `v1,${btoa(String.fromCharCode(...new Uint8Array(signature)))}`;
}

Deno.test("only correctly signed, fresh webhooks pass", async () => {
  const webhookSecret = `whsec_${btoa("0123456789abcdef0123456789abcdef")}`;
  const body = JSON.stringify({ type: "email.received", data: { email_id: "x" } });
  const now = 1_800_000_000;
  const signature = await svixSign(webhookSecret, "msg_1", String(now), body);
  const headers = { id: "msg_1", timestamp: String(now), signature: `v1,bm90IHRoaXM= ${signature}` };
  assert(await verifySvixSignature(webhookSecret, headers, body, now));
  assert(!(await verifySvixSignature(webhookSecret, headers, body + " ", now)), "changed body");
  assert(!(await verifySvixSignature(webhookSecret, { ...headers, id: "msg_2" }, body, now)), "other id");
  assert(!(await verifySvixSignature(webhookSecret, headers, body, now + 301)), "too old");
  assert(!(await verifySvixSignature(`whsec_${btoa("another-secret-another-secret!!")}`, headers, body, now)));
  assert(!(await verifySvixSignature(webhookSecret, { ...headers, signature: null }, body, now)));
  assert(!(await verifySvixSignature("not-whsec", headers, body, now)));
});

Deno.test("automatic mail is recognised", () => {
  assert(isAutomatic({ "auto-submitted": "auto-replied" }, "Re: Ny spelare"));
  assert(!isAutomatic({ "auto-submitted": "no" }, "Re: Ny spelare"));
  assert(isAutomatic({ precedence: "bulk" }, "Hej"));
  assert(isAutomatic({ "list-unsubscribe": "<mailto:x>" }, "Hej"));
  assert(isAutomatic({}, "Autosvar: Ny spelare"));
  assert(isAutomatic({}, "Automatic reply: Ny spelare"));
  assert(isAutomatic({}, "Out of office"));
  assert(!isAutomatic({}, "Re: Ny spelare"));
});

Deno.test("DMARC must pass", () => {
  assert(authenticated({ spf: "pass", dkim: "pass", dmarc: "pass" }));
  assert(authenticated({ dmarc: { result: "PASS" } }));
  assert(!authenticated({ spf: "pass", dkim: "pass", dmarc: "fail" }));
  assert(!authenticated({ spf: "pass", dkim: "pass" }));
  assert(!authenticated(null));
});

Deno.test("only the new text of a reply is kept", () => {
  assertEquals(
    replyText("Tack, vi kommer!\n\nDen 16 okt. 2026 skrev Alby IF via TeamZone <klubbsajt@teamzoneapp.se>:\n> Välkommen!", null),
    "Tack, vi kommer!",
  );
  assertEquals(replyText("Thanks!\nOn Fri, Oct 16, 2026 at 10:00 Alby IF wrote:\n> hi", null), "Thanks!");
  assertEquals(replyText("Ok\n\n-----Original Message-----\nFrom: x", null), "Ok");
  assertEquals(replyText("", "<p>Hej <b>där</b></p><div>&amp; tack</div>"), "Hej där\n& tack");
  assertEquals(replyText("x".repeat(6000), null).length, 5000);
  assertEquals(replyText(null, null), "");
});

Deno.test("mail apps' footers and a signature are not part of the reply", () => {
  assertEquals(replyText("Det låter perfekt för oss!\n\nSkickat från Outlook för Android", null), "Det låter perfekt för oss!");
  assertEquals(replyText("Ja!\n\nSkickat från min iPhone\n\nDen 16 okt. 2026 skrev X <a@b.se>:\n> hej", null), "Ja!");
  assertEquals(replyText("Ok\nSent from my Samsung Galaxy smartphone.", null), "Ok");
  assertEquals(replyText("Ok\n\nHämta Outlook för iOS", null), "Ok");
  assertEquals(replyText("Hej\n-- \nAnna Svensson\n070-123 45 67", null), "Hej");
  // Only a footer on its own line goes, never the text itself.
  assertEquals(replyText("Kort svar\nSkickat från min mobil, så kort svar: ja", null), "Kort svar\nSkickat från min mobil, så kort svar: ja");
  assertEquals(replyText("Skickat från min iPhone", null), "Skickat från min iPhone");
});

Deno.test("the answer quotes the original message", () => {
  const text = answerText({
    body: "Välkommen på torsdag!",
    sender: "P2012 · Alby IF",
    originalAt: "2026-10-16T18:37:00Z",
    originalBody: "Hej!\nKan min son börja?",
  });
  assert(text.startsWith("Välkommen på torsdag!"));
  assert(text.includes("Skickat av P2012 · Alby IF via TeamZone"));
  assert(text.includes("> Hej!\n> Kan min son börja?"));
});
