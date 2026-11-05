// What the withdrawal function says on the account page.

export type WithdrawalStatus =
  | { state: "none" }
  | { state: "received"; received_at: string; receipt_sent: boolean }
  | { state: "expired"; last_day: string }
  | { state: "open"; interval: "month" | "year" | null; purchased_at: string; last_day: string; email: string };

const swedishDate = (value: string) =>
  new Date(value).toLocaleDateString("sv-SE", { day: "numeric", month: "long", year: "numeric", timeZone: "Europe/Stockholm" });

const swedishTime = (value: string) =>
  new Date(value).toLocaleString("sv-SE", { dateStyle: "long", timeStyle: "short", timeZone: "Europe/Stockholm" });

/** The purchase the person is about to withdraw from. */
export function withdrawalFacts(status: Extract<WithdrawalStatus, { state: "open" }>): string {
  const kind = status.interval === "year" ? "Årsprenumeration" : status.interval === "month" ? "Månadsprenumeration" : "Prenumeration";
  return `${kind} på Tacticsboard, köpt ${swedishDate(status.purchased_at)}. Du kan ångra köpet till och med ${swedishDate(status.last_day)}.`;
}

export function withdrawalReceivedText(status: Extract<WithdrawalStatus, { state: "received" }>): string {
  const time = `Vi tog emot din ånger ${swedishTime(status.received_at)}.`;
  return status.receipt_sent
    ? `${time} Mottagningsbeviset är skickat med e-post.`
    : `${time} Mejlet med mottagningsbeviset gick inte att skicka, så spara den här texten. Vi hör av oss.`;
}
