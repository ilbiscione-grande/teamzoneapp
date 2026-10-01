export type ServerConfig = {
  supabaseUrl: string;
  supabaseSecretKey: string;
  ipHmacSecret: string;
  publicOrigin: string;
  /** Further addresses the public site is served on (PUBLIC_SITE_ORIGINS). */
  siteOrigins?: string[];
  trustedProxyHops: number;
  captchaVerifyUrl?: string;
  captchaSecretKey?: string;
};

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`missing_server_config:${name}`);
  return value;
}

/** Every address the public site answers on: the canonical origin first. */
export function siteOrigins(config: ServerConfig): string[] {
  return [...new Set([config.publicOrigin, ...(config.siteOrigins ?? [])])];
}

export function serverConfig(requireCaptcha = false): ServerConfig {
  const ipHmacSecret = required("PUBLIC_API_IP_HMAC_SECRET");
  if (ipHmacSecret.length < 32) throw new Error("invalid_server_config:PUBLIC_API_IP_HMAC_SECRET");
  const publicOrigin = required("PUBLIC_ORIGIN");
  const originUrl = new URL(publicOrigin);
  if (originUrl.protocol !== "https:" && originUrl.hostname !== "localhost") {
    throw new Error("invalid_server_config:PUBLIC_ORIGIN");
  }
  const trustedProxyHops = Number.parseInt(process.env.TRUSTED_PROXY_HOPS ?? "1", 10);
  if (!Number.isInteger(trustedProxyHops) || trustedProxyHops < 0 || trustedProxyHops > 5) {
    throw new Error("invalid_server_config:TRUSTED_PROXY_HOPS");
  }
  const siteOrigins = (process.env.PUBLIC_SITE_ORIGINS ?? "").split(",").map((value) => value.trim()).filter(Boolean).map((value) => {
    const url = new URL(value);
    if (url.protocol !== "https:" && url.hostname !== "localhost") throw new Error("invalid_server_config:PUBLIC_SITE_ORIGINS");
    return url.origin;
  });
  const config: ServerConfig = {
    supabaseUrl: required("SUPABASE_URL"),
    supabaseSecretKey: required("SUPABASE_SECRET_KEY"),
    ipHmacSecret,
    publicOrigin: originUrl.origin,
    siteOrigins,
    trustedProxyHops,
  };
  if (requireCaptcha) {
    const captchaVerifyUrl = required("CAPTCHA_VERIFY_URL");
    if (new URL(captchaVerifyUrl).protocol !== "https:") {
      throw new Error("invalid_server_config:CAPTCHA_VERIFY_URL");
    }
    config.captchaVerifyUrl = captchaVerifyUrl;
    config.captchaSecretKey = required("CAPTCHA_SECRET_KEY");
  }
  return config;
}
