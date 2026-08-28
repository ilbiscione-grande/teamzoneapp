import type { ServerConfig } from "./config.ts";
import { hmacHex } from "./request-security.ts";

export async function verifyCaptcha(config: ServerConfig, token: string, rawIp: string) {
  if (!config.captchaVerifyUrl || !config.captchaSecretKey || token.length < 16 || token.length > 4096) {
    return { verified: false, assertionHash: "" };
  }
  const body = new URLSearchParams({ secret: config.captchaSecretKey, response: token, remoteip: rawIp });
  const response = await fetch(config.captchaVerifyUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
    cache: "no-store",
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) return { verified: false, assertionHash: "" };
  const result = await response.json() as { success?: boolean; hostname?: string; action?: string };
  const expectedHostname = new URL(config.publicOrigin).hostname;
  const verified = result.success === true
    && result.hostname === expectedHostname
    && result.action === "contact";
  return {
    verified,
    assertionHash: verified ? hmacHex(config.ipHmacSecret, `captcha:${token}`) : "",
  };
}
