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
  month: { label: "39 kr/mån", amount: 39 },
  year: { label: "390 kr/år", amount: 390 },
  launch: { label: "292,50 kr första året", amount: "292,50", until: "2026-12-31" },
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

/** What the account page says about Tacticsboard, and which actions it offers. */
export function subscriptionSummary(access: TacticsAccess, now = Date.now()): {
  lines: string[];
  subscribe: boolean;
  manage: "card" | "manage" | null;
  tryIt: boolean;
} {
  const interval = access.billing_interval === "year" ? "Årsabonnemang" : "Månadsabonnemang";
  const price = access.billing_interval === "year" ? prices.year.label : prices.month.label;
  if (access.source === "subscription") {
    const end = access.current_period_ends_at ? swedishDate(access.current_period_ends_at) : null;
    return {
      lines: [`${interval}, ${price}.`,
        access.cancel_at_period_end
          ? `Uppsagt. Gäller till och med ${end}.`
          : end ? `Nästa betalning ${end}.` : ""].filter(Boolean),
      subscribe: false, manage: "manage", tryIt: false,
    };
  }
  if (access.source === "grace") {
    return { lines: [accessNote(access, now)], subscribe: false, manage: "card", tryIt: false };
  }
  if (access.source === "trial") {
    const end = access.trial_ends_at ? ` (till och med ${swedishDate(access.trial_ends_at)})` : "";
    return { lines: [`Provperiod${end}. ${accessNote(access, now)}`], subscribe: true, manage: null, tryIt: false };
  }
  if (access.trial_available) {
    return { lines: ["Prova Tacticsboard gratis i 7 dagar. Inget kort behövs."], subscribe: false, manage: null, tryIt: true };
  }
  const ended = access.subscription_state === "ended" || access.subscription_state === "grace";
  return {
    lines: [ended ? "Prenumerationen har upphört. Dina projekt finns kvar." : "Provperioden är slut. Dina projekt finns kvar."],
    subscribe: true, manage: ended ? "manage" : null, tryIt: false,
  };
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
