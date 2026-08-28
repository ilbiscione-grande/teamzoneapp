import assert from "node:assert/strict";
import test from "node:test";
import { assertSameOrigin, hmacHex, resolveClientIp } from "../lib/request-security.ts";

test("trusted proxy hops ignore a spoofed leading address", () => {
  assert.equal(resolveClientIp("spoofed, 203.0.113.10, 10.0.0.1", 1), "203.0.113.10");
});

test("missing client IP fails closed", () => {
  assert.throws(() => resolveClientIp(null, 1), /client_ip_unavailable/);
});

test("IP HMAC is deterministic and does not contain input", () => {
  const value = hmacHex("x".repeat(32), "203.0.113.10");
  assert.match(value, /^[0-9a-f]{64}$/);
  assert.equal(value, hmacHex("x".repeat(32), "203.0.113.10"));
  assert.ok(!value.includes("203.0.113.10"));
});

test("contact mutation requires exact same origin", () => {
  const allowed = new Request("https://teamzoneapp.se/api/public/v1/contact", {
    headers: { origin: "https://teamzoneapp.se" },
  });
  assert.doesNotThrow(() => assertSameOrigin(allowed, "https://teamzoneapp.se"));
  const denied = new Request("https://teamzoneapp.se/api/public/v1/contact", {
    headers: { origin: "https://evil.example" },
  });
  assert.throws(() => assertSameOrigin(denied, "https://teamzoneapp.se"), /origin_denied/);
});
