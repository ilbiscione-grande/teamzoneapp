// Reporting what is in the library, and support reviewing the reports (plan
// item 16). A report is a reason chosen from a list and, if wished, words of
// one's own, kept as one text (at most 500 characters, as the server checks).
// Three open reports hide an item until support decides: hide it, or show it
// again (20261214090000); support sees it whole first (20270208090000).
import type { Board } from "./model.ts";
import type { SharedItemSummary } from "./library.ts";

export const reportReasons = [
  ["offensive", "Kränkande eller olämpligt"],
  ["copyright", "Kopierat från någon annan"],
  ["personal", "Personuppgifter, till exempel riktiga spelares namn"],
  ["spam", "Reklam eller skräp"],
  ["other", "Något annat"],
] as const;

export type ReportReason = (typeof reportReasons)[number][0];

const reasonLabel = (reason: ReportReason) => reportReasons.find(([value]) => value === reason)![1];

/** The text the server keeps: the reason, then the reporter's words. */
export function reportText(reason: ReportReason, words: string): string {
  const own = words.trim().replace(/\s+/g, " ");
  return (own ? `${reasonLabel(reason)}: ${own}` : reasonLabel(reason)).slice(0, 500);
}

/** Something else needs words of one's own; the rest do not. */
export function reportReady(reason: ReportReason | "", words: string): boolean {
  return reason !== "" && (reason !== "other" || words.trim().length > 0);
}

export type ReportEntry = { reason: string; created_at: string; resolution: "hidden" | "dismissed" | null; resolved_at: string | null };

/** An item in support's list: the library's summary with its reports. */
export type ReportedItem = SharedItemSummary & { hidden_by_support: boolean; reports: ReportEntry[] };

/** The item whole, for support to look at before deciding. */
export type ReportedItemWhole = ReportedItem & { document: { boards?: Board[] } };

export const openReports = (item: Pick<ReportedItem, "reports">) => item.reports.filter(report => !report.resolved_at);

/** Where an item stands for support. */
export function reviewStatus(item: Pick<ReportedItem, "hidden" | "hidden_by_support" | "reports">): string {
  const open = openReports(item).length;
  if (item.hidden_by_support) return "Dold av supporten";
  if (open === 0) return "Behållen";
  if (item.hidden) return `Dold efter ${open} anmälningar, väntar på beslut`;
  return open === 1 ? "1 anmälan, syns i biblioteket" : `${open} anmälningar, syns i biblioteket`;
}

/** Support's note, kept in the audit: 5 to 1000 characters, as the server checks. */
export const noteReady = (note: string) => note.trim().length >= 5 && note.trim().length <= 1000;

/** Every text a board shows, for support to read: its name, description, coaching points and what is written on the pitch. */
export function boardTexts(board: Board): string[] {
  const texts = [board.name, board.description, board.exercise?.coachingPoints];
  for (const frame of board.frames ?? []) {
    for (const object of frame.objects ?? []) {
      const fields = object as unknown as Record<string, unknown>;
      for (const key of ["text", "label", "name"]) if (typeof fields[key] === "string") texts.push(fields[key] as string);
    }
  }
  return [...new Set(texts.map(text => text?.trim() ?? "").filter(Boolean))];
}

export function reviewErrorText(message: string | undefined): string {
  if (message?.includes("not_found")) return "Det finns inte längre, eller så saknar kontot rätt att granska.";
  if (message?.includes("invalid_input")) return "Skriv en kort motivering, minst 5 tecken.";
  return "Det gick inte. Försök igen.";
}
