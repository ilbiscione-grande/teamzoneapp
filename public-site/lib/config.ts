export type ServerConfig = {
  supabaseUrl: string;
  supabaseSecretKey: string;
  ipHmacSecret: string;
  publicOrigin: string;
  trustedProxyHops: number;
  captchaVerifyUrl?: string;
  captchaSecretKey?: string;
};

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`missing_server_config:${name}`);
  return value;
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
  const config: ServerConfig = {
    supabaseUrl: required("SUPABASE_URL"),
    supabaseSecretKey: required("SUPABASE_SECRET_KEY"),
    ipHmacSecret,
    publicOrigin: originUrl.origin,
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
