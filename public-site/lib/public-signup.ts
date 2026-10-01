// Follower accounts are created only through the public site's server: the
// browser posts here, never to Supabase sign-up directly, so only this path
// can mark an account as a follower.

export type SignUpInput = { email: string; password: string; displayName: string; captchaToken: string };

const email = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function parseSignUp(body: unknown): SignUpInput | null {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const value = body as Record<string, unknown>;
  if (typeof value.email !== "string" || typeof value.password !== "string"
    || typeof value.displayName !== "string" || typeof value.captchaToken !== "string"
    || value.acceptLegal !== true) return null;
  const input = {
    email: value.email.trim().toLowerCase(),
    password: value.password,
    displayName: value.displayName.trim().replace(/\s+/g, " "),
    captchaToken: value.captchaToken,
  };
  if (input.email.length > 320 || !email.test(input.email)) return null;
  if (input.password.length < 8 || input.password.length > 128) return null;
  if (input.displayName.length < 1 || input.displayName.length > 80) return null;
  return input;
}

/** Only addresses on the public site itself are valid confirmation targets. */
export function confirmationRedirect(origin: string): string {
  return `${origin}/?konto=bekraftat`;
}
