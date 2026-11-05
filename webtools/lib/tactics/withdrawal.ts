// What the withdrawal function says on the account page.

import { swedishLanguage, type Language } from "../i18n/translate.ts";

export type WithdrawalStatus =
  | { state: "none" }
  | { state: "received"; received_at: string; receipt_sent: boolean }
  | { state: "expired"; last_day: string }
  | { state: "open"; interval: "month" | "year" | null; purchased_at: string; last_day: string; email: string };

const longDate = (value: string, intl: string) =>
  new Date(value).toLocaleDateString(intl, { day: "numeric", month: "long", year: "numeric", timeZone: "Europe/Stockholm" });

const longTime = (value: string, intl: string) =>
  new Date(value).toLocaleString(intl, { dateStyle: "long", timeStyle: "short", timeZone: "Europe/Stockholm" });

/** The purchase the person is about to withdraw from. */
export function withdrawalFacts(status: Extract<WithdrawalStatus, { state: "open" }>, { t, intl }: Language = swedishLanguage): string {
  const kind = t(status.interval === "year" ? "Årsprenumeration" : status.interval === "month" ? "Månadsprenumeration" : "Prenumeration");
  return t("{kind} på Tacticsboard, köpt {purchased}. Du kan ångra köpet till och med {last}.", { kind, purchased: longDate(status.purchased_at, intl), last: longDate(status.last_day, intl) });
}

export function withdrawalReceivedText(status: Extract<WithdrawalStatus, { state: "received" }>, { t, intl }: Language = swedishLanguage): string {
  const time = t("Vi tog emot din ånger {time}.", { time: longTime(status.received_at, intl) });
  return `${time} ${t(status.receipt_sent
    ? "Mottagningsbeviset är skickat med e-post."
    : "Mejlet med mottagningsbeviset gick inte att skicka, så spara den här texten. Vi hör av oss.")}`;
}
