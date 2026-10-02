// Sign-up forms: anyone with a club's or team's link sends their basic
// contact details. The browser posts to this site's server, which checks the
// origin and captcha before the service-only database command stores them.

export type IntakeInput = {
  token: string;
  fullName: string;
  phone: string;
  email: string;
  birthDate: string;
  streetAddress: string;
  postalCode: string;
  city: string;
  captchaToken: string;
};

const token = /^[a-f0-9]{32}$/;
const date = /^\d{4}-\d{2}-\d{2}$/;
const email = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const phone = /^\+?[0-9 ()-]{5,30}$/;

export function validIntakeToken(value: unknown): value is string {
  return typeof value === "string" && token.test(value);
}

export function parseIntake(body: unknown, today = new Date()): IntakeInput | null {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const value = body as Record<string, unknown>;
  const text = (key: string) => (typeof value[key] === "string" ? (value[key] as string).trim().replace(/\s+/g, " ") : "");
  const input: IntakeInput = {
    token: text("token"),
    fullName: text("fullName"),
    phone: text("phone"),
    email: text("email").toLowerCase(),
    birthDate: text("birthDate"),
    streetAddress: text("streetAddress"),
    postalCode: text("postalCode"),
    city: text("city"),
    captchaToken: typeof value.captchaToken === "string" ? value.captchaToken : "",
  };
  if (!validIntakeToken(input.token) || !input.captchaToken) return null;
  if (input.fullName.length < 2 || input.fullName.length > 120) return null;
  if (!phone.test(input.phone) || input.email.length > 254 || !email.test(input.email)) return null;
  if (!date.test(input.birthDate)) return null;
  const birth = new Date(`${input.birthDate}T00:00:00Z`);
  if (Number.isNaN(birth.getTime()) || birth.getUTCFullYear() < 1900 || birth > today) return null;
  if (input.streetAddress.length < 2 || input.streetAddress.length > 120) return null;
  if (input.postalCode.length < 3 || input.postalCode.length > 10) return null;
  if (input.city.length < 2 || input.city.length > 80) return null;
  return input;
}
