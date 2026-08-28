import assert from "node:assert/strict";
import test from "node:test";
import { verifyCaptcha } from "../lib/captcha.ts";
import type { ServerConfig } from "../lib/config.ts";

const config: ServerConfig = {
  supabaseUrl: "https://example.supabase.co",
  supabaseSecretKey: "secret",
  ipHmacSecret: "x".repeat(32),
  publicOrigin: "https://teamzoneapp.se",
  trustedProxyHops: 1,
  captchaVerifyUrl: "https://challenges.cloudflare.com/turnstile/v0/siteverify",
  captchaSecretKey: "turnstile-secret",
};

test("Turnstile assertion requires the canonical hostname and contact action", async (context) => {
  context.mock.method(globalThis, "fetch", async () => Response.json({
    success: true,
    hostname: "teamzoneapp.se",
    action: "contact",
  }));
  const result = await verifyCaptcha(config, "valid-token-value", "203.0.113.10");
  assert.equal(result.verified, true);
  assert.match(result.assertionHash, /^[0-9a-f]{64}$/);
});

test("Turnstile assertion fails closed for another action", async (context) => {
  context.mock.method(globalThis, "fetch", async () => Response.json({
    success: true,
    hostname: "teamzoneapp.se",
    action: "login",
  }));
  const result = await verifyCaptcha(config, "valid-token-value", "203.0.113.10");
  assert.deepEqual(result, { verified: false, assertionHash: "" });
});
