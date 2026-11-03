// Tacticsboard sold per person: what the person's access is and what the
// page says about it (api.get_my_tacticsboard_access). The lock itself is
// in the database; this only explains it.

export type TacticsAccess = {
  access_mode: "write" | "denied";
  source: "subscription" | "grace" | "trial" | "none";
  trial_available: boolean;
  trial_ends_at: string | null;
  subscription_state: "active" | "grace" | "ended" | "unknown" | null;
  billing_interval: "month" | "year" | null;
  current_period_ends_at: string | null;
  cancel_at_period_end: boolean;
  grace_ends_at: string | null;
};

export type Interval = "month" | "year";

/** The prices as Stripe charges them, VAT included. */
export const prices = {
  month: { label: "79 kr/mån", amount: 79 },
  year: { label: "790 kr/år", amount: 790 },
  launch: { label: "395 kr första året", until: "2026-12-31" },
};

/** Whether the launch offer on the yearly price still applies (Swedish time). */
export function launchOfferOpen(now = new Date()): boolean {
  return now.getTime() < Date.parse("2027-01-01T00:00:00+01:00");
}

/** Whole days left, rounded up: 6 days and 1 hour is "7 dagar". */
export function daysLeft(until: string | null, now = Date.now()): number {
  if (!until) return 0;
  return Math.max(0, Math.ceil((Date.parse(until) - now) / 86_400_000));
}

const swedishDate = (value: string) =>
  new Date(value).toLocaleDateString("sv-SE", { day: "numeric", month: "long", timeZone: "Europe/Stockholm" });

/** The line above Tacticsboard while it is open; empty when nothing needs saying. */
export function accessNote(access: TacticsAccess, now = Date.now()): string {
  if (access.source === "trial") {
    const days = daysLeft(access.trial_ends_at, now);
    return days <= 1 ? "Sista dagen av provperioden." : `${days} dagar kvar av provperioden.`;
  }
  if (access.source === "grace" && access.grace_ends_at) {
    return `Betalningen gick inte igenom. Uppdatera kortet senast ${swedishDate(access.grace_ends_at)} så fortsätter allt att fungera.`;
  }
  if (access.source === "subscription" && access.cancel_at_period_end && access.current_period_ends_at) {
    return `Prenumerationen avslutas ${swedishDate(access.current_period_ends_at)}.`;
  }
  return "";
}

/** The heading and text of the locked page. */
export function lockedText(access: TacticsAccess): { title: string; text: string } {
  const kept = "Dina projekt finns kvar, och det du har delat fungerar fortfarande för andra. Allt öppnas igen så fort du prenumererar.";
  if (access.subscription_state === "ended" || access.subscription_state === "grace") {
    return { title: "Prenumerationen har upphört", text: kept };
  }
  if (access.trial_ends_at) return { title: "Provperioden är slut", text: kept };
  return { title: "Prenumerera på Tacticsboard", text: "Börja prenumerera för att använda Tacticsboard." };
}

/** Whether an RPC failed because the account is locked. */
export const isLockedError = (message: string | undefined) => (message ?? "").includes("tacticsboard_locked");

/** The person's message when checkout or the portal cannot be opened. */
export function billingErrorText(code: string): string {
  if (code === "already_subscribed") return "Du har redan en prenumeration. Ladda om sidan.";
  if (code === "no_customer") return "Det finns ingen betalning att hantera än.";
  if (code === "not_signed_in") return "Logga in igen och försök på nytt.";
  return "Betalningen går inte att öppna just nu. Försök igen om en stund.";
}
