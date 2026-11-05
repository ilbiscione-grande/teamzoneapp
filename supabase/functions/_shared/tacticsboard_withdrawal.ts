// Withdrawing from a Tacticsboard purchase: the deadline, which purchase it
// concerns and the two mails, kept free of I/O so they can be tested.
import { tacticsboardProduct } from "./tacticsboard_billing.ts";

const stockholmDate = (ms: number) =>
  new Date(ms).toLocaleDateString("sv-SE", { timeZone: "Europe/Stockholm" });

/// The last day to withdraw: 14 days after the day of purchase.
export function withdrawalLastDay(purchasedAtSeconds: number): string {
  const purchaseDay = stockholmDate(purchasedAtSeconds * 1000);
  const noon = Date.parse(`${purchaseDay}T12:00:00Z`);
  return new Date(noon + 14 * 86_400_000).toISOString().slice(0, 10);
}

export function withdrawalOpen(
  purchasedAtSeconds: number,
  now = Date.now(),
): boolean {
  return stockholmDate(now) <= withdrawalLastDay(purchasedAtSeconds);
}

export type StripeSubscriptionLike = {
  id: string;
  status: string;
  start_date: number;
  metadata?: Record<string, string> | null;
  items?: { data?: { price?: { recurring?: { interval?: string } | null } }[] };
};

/// The person's latest purchase of Tacticsboard.
export function latestPurchase<T extends StripeSubscriptionLike>(
  subscriptions: T[],
): T | null {
  return subscriptions
    .filter((item) => item.metadata?.teamzone_product === tacticsboardProduct)
    .filter((item) => item.status !== "incomplete_expired")
    .sort((a, b) => b.start_date - a.start_date)[0] ?? null;
}

export function purchaseInterval(
  subscription: StripeSubscriptionLike,
): "month" | "year" | null {
  const interval = subscription.items?.data?.[0]?.price?.recurring?.interval;
  return interval === "month" || interval === "year" ? interval : null;
}

export function parseWithdrawalName(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const name = value.trim();
  return name.length >= 1 && name.length <= 200 ? name : null;
}

const stockholmTime = (value: string) =>
  new Date(value).toLocaleString("sv-SE", {
    timeZone: "Europe/Stockholm",
    dateStyle: "long",
    timeStyle: "short",
  });

const intervalText = (interval: "month" | "year" | null) =>
  interval === "year"
    ? "årsprenumeration"
    : interval === "month"
    ? "månadsprenumeration"
    : "prenumeration";

type Withdrawal = {
  name: string;
  email: string;
  receivedAt: string;
  purchasedAtSeconds: number;
  interval: "month" | "year" | null;
};

/// The receipt the law asks for. It says when we received the message; it
/// also says what happens next, since the person has no other record of it.
export function withdrawalReceipt(item: Withdrawal) {
  const purchased = stockholmDate(item.purchasedAtSeconds * 1000);
  return {
    subject: "Mottagningsbevis: du har ångrat köpet av Tacticsboard",
    text: [
      `Hej ${item.name}!`,
      "",
      `Vi tog emot ditt besked om att ångra köpet ${stockholmTime(item.receivedAt)}.`,
      "",
      `Avtal: Tacticsboard, ${intervalText(item.interval)}, köpt ${purchased}.`,
      `Konto: ${item.email}`,
      "",
      "Vi avslutar prenumerationen, och inget mer dras.",
      "Har du betalat får du tillbaka pengarna till samma betalsätt inom 14 dagar, med avdrag för en proportionell del av priset för den betalda tiden fram till i dag.",
      "",
      "Frågor? Svara inte på det här mejlet utan mejla support@teamzoneapp.se.",
      "",
      "Tre 60 Grader, Plangränd 15, 574 34 Vetlanda",
    ].join("\n"),
  };
}

/// What support needs for the refund. No card data, and only what the person
/// has given us themselves.
export function withdrawalSupportMail(
  item: Withdrawal & {
    subscriptionRef: string;
    subscriptionStatus: string;
    cancelled: boolean;
    paidPeriodStartSeconds: number | null;
  },
) {
  const paidFrom = item.paidPeriodStartSeconds === null
    ? "okänt"
    : stockholmDate(item.paidPeriodStartSeconds * 1000);
  return {
    subject: item.cancelled
      ? "Ånger Tacticsboard: återbetala i Stripe"
      : "Ånger Tacticsboard: AVSLUTA OCH återbetala i Stripe",
    text: [
      `Namn: ${item.name}`,
      `E-post: ${item.email}`,
      `Mottagen: ${stockholmTime(item.receivedAt)}`,
      `Avtal: ${intervalText(item.interval)}, köpt ${stockholmDate(item.purchasedAtSeconds * 1000)}`,
      `Prenumeration i Stripe: ${item.subscriptionRef} (var ${item.subscriptionStatus})`,
      `Betald period från: ${paidFrom}`,
      "",
      item.cancelled
        ? "Prenumerationen är avslutad."
        : "Prenumerationen kunde inte avslutas automatiskt. Avsluta den i Stripe.",
      item.subscriptionStatus === "trialing"
        ? "Den var i provperioden, så inget har dragits."
        : "Återbetala senast inom 14 dagar: det betalda beloppet minus den proportionella delen från den betalda periodens start till mottagandet.",
    ].join("\n"),
  };
}
