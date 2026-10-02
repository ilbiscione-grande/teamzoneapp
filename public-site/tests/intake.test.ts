import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { parseIntake, validIntakeToken } from "../lib/intake.ts";

const route = readFileSync(new URL("../app/api/public/v1/intake/route.ts", import.meta.url), "utf8");
const form = readFileSync(new URL("../components/intake-form.tsx", import.meta.url), "utf8");
const proxy = readFileSync(new URL("../proxy.ts", import.meta.url), "utf8");
const token = "0123456789abcdef0123456789abcdef";
const valid = { token, fullName: " Ada  Andersson ", phone: "070-123 45 67", email: " Ada@Mail.se ", birthDate: "2012-05-03",
  streetAddress: "Storgatan 1", postalCode: "575 31", city: "Eksjö", captchaToken: "t".repeat(20) };

test("sign-up input is validated and normalised", () => {
  const today = new Date("2026-10-02T12:00:00Z");
  const input = parseIntake(valid, today);
  assert.equal(input?.fullName, "Ada Andersson");
  assert.equal(input?.email, "ada@mail.se");
  assert.equal(parseIntake({ ...valid, token: "short" }, today), null);
  assert.equal(parseIntake({ ...valid, email: "inte-en-adress" }, today), null);
  assert.equal(parseIntake({ ...valid, phone: "ring mig" }, today), null);
  assert.equal(parseIntake({ ...valid, birthDate: "2027-01-01" }, today), null);
  assert.equal(parseIntake({ ...valid, birthDate: "1899-12-31" }, today), null);
  assert.equal(parseIntake({ ...valid, city: "" }, today), null);
  assert.equal(parseIntake({ ...valid, captchaToken: "" }, today), null);
  assert.equal(validIntakeToken(token), true);
  assert.equal(validIntakeToken("../x"), false);
});

test("submissions go through the site's server with origin and captcha checks", () => {
  assert.match(route, /assertSameOrigin\(request, siteOrigins\(config\)\)/);
  assert.match(route, /verifyCaptcha\(config, input\.captchaToken, rawIp, "intake"\)/);
  assert.match(route, /public_submit_intake/);
  assert.match(route, /hmacHex\(config\.ipHmacSecret, rawIp\)/);
  assert.match(form, /\/api\/public\/v1\/intake/);
  assert.match(proxy, /"\/anmalan\/"/);
});
