// Where people reach support, how soon they hear back, and the terms for
// Tacticsboard (on the public site).

export const supportEmail = "support@teamzoneapp.se";
export const supportReply = "Vi svarar inom två vardagar.";
export const tacticsboardTermsUrl = (locale: "sv" | "en") =>
  `https://public.teamzoneapp.se/${locale === "en" ? "en/terms" : "villkor"}/tacticsboard`;
