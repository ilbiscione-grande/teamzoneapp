import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { verifyCaptcha } from "../lib/captcha.ts";
import type { ServerConfig } from "../lib/config.ts";
import { confirmationRedirect, parseSignUp } from "../lib/public-signup.ts";
import { assertSameOrigin } from "../lib/request-security.ts";

const route = readFileSync(new URL("../app/api/public/v1/account/sign-up/route.ts", import.meta.url), "utf8");
const home = readFileSync(new URL("../components/personal-home.tsx", import.meta.url), "utf8");
const valid = { email: " Ada@Mail.se ", password: "hemligt123", displayName: " Ada  Andersson ", captchaToken: "t".repeat(20), acceptLegal: true };

test("sign-up input is validated and normalised", () => {
  assert.deepEqual(parseSignUp(valid), { email: "ada@mail.se", password: "hemligt123", displayName: "Ada Andersson", captchaToken: "t".repeat(20) });
  assert.equal(parseSignUp({ ...valid, acceptLegal: false }), null);
  assert.equal(parseSignUp({ ...valid, password: "kort" }), null);
  assert.equal(parseSignUp({ ...valid, email: "inte-en-adress" }), null);
  assert.equal(parseSignUp({ ...valid, displayName: "  " }), null);
  assert.equal(parseSignUp([]), null);
  assert.equal(confirmationRedirect("https://public.teamzoneapp.se"), "https://public.teamzoneapp.se/?konto=bekraftat");
});

test("follower accounts are created only by the public site's server", () => {
  assert.match(route, /assertSameOrigin\(request, origins\)/);
  assert.match(route, /verifyCaptcha\(config, input\.captchaToken, rawIp, "signup"\)/);
  assert.match(route, /mark_public_follower_account/);
  // Existing accounts come back without identities and are never touched.
  assert.match(route, /identities\?\.length/);
  assert.doesNotMatch(home, /auth\.signUp|mark_public_follower_account/);
  assert.match(home, /\/api\/public\/v1\/account\/sign-up/);
});

test("the site accepts requests from each of its addresses", () => {
  const request = (origin: string) => new Request("https://public.teamzoneapp.se/x", { method: "POST", headers: { origin } });
  const origins = ["https://teamzoneapp.se", "https://public.teamzoneapp.se"];
  assert.doesNotThrow(() => assertSameOrigin(request("https://public.teamzoneapp.se"), origins));
  assert.throws(() => assertSameOrigin(request("https://evil.example"), origins), /origin_denied/);
  assert.throws(() => assertSameOrigin(new Request("https://x.se", { method: "POST" }), origins), /origin_denied/);
});

test("captcha accepts the extra site address and the sign-up action", async (context) => {
  const config: ServerConfig = {
    supabaseUrl: "https://example.supabase.co", supabaseSecretKey: "secret", ipHmacSecret: "x".repeat(32),
    publicOrigin: "https://teamzoneapp.se", siteOrigins: ["https://public.teamzoneapp.se"], trustedProxyHops: 1,
    captchaVerifyUrl: "https://challenges.cloudflare.com/turnstile/v0/siteverify", captchaSecretKey: "turnstile-secret",
  };
  context.mock.method(globalThis, "fetch", async () => Response.json({ success: true, hostname: "public.teamzoneapp.se", action: "signup" }));
  assert.equal((await verifyCaptcha(config, "valid-token-value", "203.0.113.10", "signup")).verified, true);
  assert.equal((await verifyCaptcha(config, "valid-token-value", "203.0.113.10")).verified, false);
});
