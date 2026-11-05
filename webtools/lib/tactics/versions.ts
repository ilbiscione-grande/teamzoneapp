// A project's earlier versions (core.tactics_project_versions): kept before
// a save overwrites the project, at most one per half hour of editing, when
// someone else saves, and before a restore. Only the owner sees them.

import { swedishLanguage, type Language } from "../i18n/translate.ts";

export type VersionReason = "edit" | "other_editor" | "before_restore";
export type VersionSummary = {
  id: string; revision: number; name: string; saved_at: string; reason: VersionReason;
  saved_by_me: boolean; saved_by_name: string | null; boards: string[];
};

const days = ["sön", "mån", "tis", "ons", "tors", "fre", "lör"];
const months = ["jan", "feb", "mars", "apr", "maj", "juni", "juli", "aug", "sep", "okt", "nov", "dec"];
const pad = (value: number) => String(value).padStart(2, "0");

/** "I dag 19:40", "I går 08:05", "Tors 19:40" this week, "3 okt 19:40" before, with the year when another. */
export function versionTime(iso: string, now = new Date(), { t, intl }: Language = swedishLanguage): string {
  const at = new Date(iso);
  const clock = `${pad(at.getHours())}:${pad(at.getMinutes())}`;
  const day = (date: Date) => new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  const ago = Math.round((day(now) - day(at)) / 86_400_000);
  if (ago === 0) return t("I dag {clock}", { clock });
  if (ago === 1) return t("I går {clock}", { clock });
  if (intl !== swedishLanguage.intl) {
    const options: Intl.DateTimeFormatOptions = ago > 1 && ago < 7 ? { weekday: "long" }
      : { day: "numeric", month: "short", ...(at.getFullYear() === now.getFullYear() ? {} : { year: "numeric" }) };
    return `${at.toLocaleDateString(intl, options)} ${clock}`;
  }
  if (ago > 1 && ago < 7) return `${days[at.getDay()][0].toUpperCase()}${days[at.getDay()].slice(1)} ${clock}`;
  const year = at.getFullYear() === now.getFullYear() ? "" : ` ${at.getFullYear()}`;
  return `${at.getDate()} ${months[at.getMonth()]}${year} ${clock}`;
}

/** Who saved it and why it was kept, in a few words. */
export function versionNote(version: VersionSummary, { t }: Language = swedishLanguage): string {
  const who = version.saved_by_me ? t("du") : version.saved_by_name?.trim() || t("en annan ledare");
  const boards = version.boards.length === 1 ? t("1 tavla") : t("{count} tavlor", { count: version.boards.length });
  const why = version.reason === "before_restore" ? t(" · före en återställning") : "";
  return `${who} · ${boards}${why}`;
}

/** The person's message for a versions RPC's error. */
export function versionErrorText(message: string): string {
  if (message.includes("stale_revision")) return "Projektet har sparats under tiden. Ladda om sidan och försök igen.";
  if (message.includes("not_found")) return "Versionen finns inte längre.";
  return "Det gick inte. Försök igen om en stund.";
}
