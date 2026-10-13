import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import {
  allowedWebOrigins,
  clientAddress,
  limitKeyHash,
} from "../_shared/sign_in_limits.ts";

Deno.test("only production origins unless extra ones are configured", () => {
  const production = allowedWebOrigins(undefined);
  assert(production.has("https://app.teamzoneapp.se"));
  assert(!production.has("http://localhost:5000"));
  const test = allowedWebOrigins(
    "http://localhost, http://localhost:5000 ,not a url,javascript:alert(1)",
  );
  assert(test.has("http://localhost"));
  assert(test.has("http://localhost:5000"));
  assertEquals(test.size, 4);
  // A function may narrow the production list (invitation-preview).
  assertEquals(
    [...allowedWebOrigins(undefined, ["https://app.teamzoneapp.se"])],
    ["https://app.teamzoneapp.se"],
  );
});

Deno.test("the client address is the proxy-appended last entry", () => {
  const headers = new Headers({ "x-forwarded-for": "6.6.6.6, 203.0.113.9" });
  assertEquals(clientAddress(headers), "203.0.113.9");
  assertEquals(
    clientAddress(new Headers({ "x-real-ip": "198.51.100.1" })),
    "198.51.100.1",
  );
  assertEquals(clientAddress(new Headers()), "unknown");
});

Deno.test("limit keys are keyed hashes, e-mail case-insensitive", async () => {
  const a = await limitKeyHash("secret", "email", "Anna@Example.se ");
  const b = await limitKeyHash("secret", "email", "anna@example.se");
  assertEquals(a, b);
  assertEquals(a.length, 64);
  assertNotEquals(a, await limitKeyHash("other", "email", "anna@example.se"));
  assertNotEquals(a, await limitKeyHash("secret", "ip", "anna@example.se"));
});
