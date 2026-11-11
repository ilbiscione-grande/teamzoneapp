import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import {
  feeEmailSubject,
  feeEmailText,
  kronor,
  unsubscribeUrl,
  verifiedUnsubscribe,
} from "../_shared/fee_mail.ts";

const secret = "test-link-secret-0123456789abcdef0123";
const emailId = "6f0e8a1c-2b3d-4e5f-8a9b-0c1d2e3f4a5b";

Deno.test("the unsubscribe link names the e-mail, not the address, and cannot be forged", async () => {
  const link = await unsubscribeUrl("https://example.supabase.co/", secret, emailId);
  assert(link.startsWith(`https://example.supabase.co/functions/v1/fee-email-unsubscribe?id=${emailId}&s=`));
  assert(!link.includes("@"));
  const signature = new URL(link).searchParams.get("s");
  assertEquals(await verifiedUnsubscribe(secret, emailId, signature), emailId);
  assertEquals(await verifiedUnsubscribe(secret, emailId, "0".repeat(20)), null);
  assertEquals(await verifiedUnsubscribe(secret, "not-an-id", signature), null);
  assertEquals(await verifiedUnsubscribe("short", emailId, signature), null);
});

Deno.test("the e-mail says what is owed, by when and how to pay", () => {
  assertEquals(kronor(190000), "1 900 kr");
  assertEquals(kronor(30050), "300,50 kr");
  const text = feeEmailText({
    clubName: "IF Eksjö Fotboll",
    title: "Medlemsavgift 2027",
    dueOn: "2027-03-31",
    paymentInfo: "Swish 123 45 67",
    fees: [{ name: "Alva", amount: 30000 }, { name: "Bertil", amount: 10000 }],
    unsubscribeUrl: "https://example/unsubscribe",
  });
  assert(text.includes("  Alva: 300 kr"));
  assert(text.includes("  Totalt: 400 kr"));
  assert(text.includes("Sista betalningsdag: 2027-03-31"));
  assert(text.includes("Så betalar du:\nSwish 123 45 67"));
  assert(text.includes("https://example/unsubscribe"));
  assertEquals(
    feeEmailSubject({ clubName: "IF Eksjö Fotboll", title: "Medlemsavgift\n2027" }),
    "Påminnelse: Medlemsavgift 2027 – IF Eksjö Fotboll",
  );
});
