// What a player shows: one short thing in the disc and, under it, what else
// the board asks for. The board picks number, name and position (any of them):
//   none or only the number  → the number in the disc
//   only the name            → the initials in the disc (NAA for Niman Abdirahman Ali)
//   only the position        → the position in the disc (CDM)
//   position and number      → number in the disc, position under
//   position and name        → position in the disc, "K. Svensson" under
//   number and name          → number in the disc, "K. Svensson" under
//   all three                → position in the disc, "K. Svensson (7)" under
// What a player lacks falls back: no position gives the number, no number the initials.
import type { Locale } from "../i18n/locale.ts";
import type { Board } from "./model.ts";

type Labelled = { number: number | null; name?: string | null; position?: string | null };

/** Football and handball positions as TeamZone stores them: the short form and the name in each language. */
const POSITIONS: Record<string, { short: string; sv: string; en: string }> = {
  goalkeeper: { short: "GK", sv: "Målvakt", en: "Goalkeeper" },
  defender: { short: "DEF", sv: "Försvarare", en: "Defender" },
  midfielder: { short: "MID", sv: "Mittfältare", en: "Midfielder" },
  forward: { short: "FWD", sv: "Anfallare", en: "Forward" },
  centre_back: { short: "CB", sv: "Mittback", en: "Centre-back" },
  left_back: { short: "LB", sv: "Vänsterback", en: "Left-back" },
  right_back: { short: "RB", sv: "Högerback", en: "Right-back" },
  wing_back: { short: "WB", sv: "Wingback", en: "Wing-back" },
  defensive_midfielder: { short: "CDM", sv: "Defensiv mittfältare", en: "Defensive midfielder" },
  central_midfielder: { short: "CM", sv: "Central mittfältare", en: "Central midfielder" },
  attacking_midfielder: { short: "CAM", sv: "Offensiv mittfältare", en: "Attacking midfielder" },
  left_winger: { short: "LW", sv: "Vänsterytter", en: "Left winger" },
  right_winger: { short: "RW", sv: "Högerytter", en: "Right winger" },
  striker: { short: "ST", sv: "Centralanfallare", en: "Striker" },
  hb_backcourt: { short: "BC", sv: "Nia", en: "Back" },
  hb_wing: { short: "W", sv: "Kant", en: "Wing" },
  hb_pivot: { short: "P", sv: "Linjespelare", en: "Pivot" },
  hb_left_back: { short: "LB", sv: "Vänsternia", en: "Left back" },
  hb_centre_back: { short: "CB", sv: "Mittnia", en: "Centre back" },
  hb_right_back: { short: "RB", sv: "Högernia", en: "Right back" },
  hb_left_wing: { short: "LW", sv: "Vänstersexa", en: "Left wing" },
  hb_right_wing: { short: "RW", sv: "Högersexa", en: "Right wing" },
};

const words = (text: string) => text.trim().split(/\s+/).filter(Boolean);
const firstLetter = (word: string) => Array.from(word)[0]?.toLocaleUpperCase("sv") ?? "";

/** "Karl Svensson" → "K. Svensson"; one word stays as it is. */
export function shortName(name: string | null | undefined): string | null {
  const parts = words(name ?? "");
  if (parts.length === 0) return null;
  if (parts.length === 1) return parts[0];
  return `${firstLetter(parts[0])}. ${parts[parts.length - 1]}`;
}

/** Every name's first letter, at most three: NAA for Niman Abdirahman Ali (the first two and the last when more). */
export function initials(name: string | null | undefined): string | null {
  const parts = words(name ?? "");
  if (parts.length === 0) return null;
  const picked = parts.length > 3 ? [parts[0], parts[1], parts[parts.length - 1]] : parts;
  return picked.map(firstLetter).join("");
}

/** The short form for the disc: CDM for a central defensive midfielder; an own position by its words' first letters. */
export function positionShort(position: string | null | undefined): string | null {
  const text = position?.trim();
  if (!text) return null;
  const known = POSITIONS[text];
  if (known) return known.short;
  if (Array.from(text).length <= 4) return text.toLocaleUpperCase("sv");
  const parts = words(text);
  return parts.length > 1 ? parts.slice(0, 3).map(firstLetter).join("") : Array.from(text).slice(0, 3).join("").toLocaleUpperCase("sv");
}

/** The position written out: TeamZone's code by its name, an own position as typed. */
export function positionName(position: string | null | undefined, locale: Locale): string | null {
  const text = position?.trim();
  if (!text) return null;
  const known = POSITIONS[text];
  return known ? known[locale === "en" ? "en" : "sv"] : text;
}

/** The positions a team of [sport] can ask for in a place, named; handball's start hb_, the goalkeeper is both sports'. */
export function positionOptions(sport: string, locale: Locale): { key: string; name: string }[] {
  return Object.entries(POSITIONS)
    .filter(([key]) => key === "goalkeeper" || (sport === "handball") === key.startsWith("hb_"))
    .map(([key, names]) => ({ key, name: names[locale === "en" ? "en" : "sv"] }));
}

/** The font size in the disc, in metres: smaller the more letters (CDM, 100, NAA). */
export const insideSize = (text: string) => {
  const length = Array.from(text).length;
  return length <= 2 ? 1.55 : length === 3 ? 1.15 : 0.9;
};

type Shown =Pick<Board, "showNames" | "showPositions" | "showNumbers">;

/** What the disc says and what stands under it (null for nothing). */
export function playerLabel(player: Labelled, board: Shown, locale: Locale): { inside: string | null; below: string | null } {
  const name = board.showNames;
  const position = board.showPositions ?? false;
  // Boards made before the choice showed the number always.
  const number = board.showNumbers ?? true;
  const values = {
    number: player.number !== null ? String(player.number) : null,
    initials: initials(player.name),
    position: positionShort(player.position),
  };
  const fallback = values.number ?? values.initials;

  if (position && (name || !number)) {
    // The position in the disc; the name, and the number when asked, under it.
    const inside = values.position ?? fallback;
    if (!name) return { inside, below: null };
    const short = shortName(player.name);
    const withNumber = number && values.number !== null && inside !== values.number;
    return { inside, below: short ? (withNumber ? `${short} (${values.number})` : short) : withNumber ? values.number : null };
  }
  if (position) {
    // Position and number: the number in the disc, the position written out under it.
    return { inside: fallback, below: positionName(player.position, locale) };
  }
  if (name && !number) return { inside: values.initials ?? values.number, below: null };
  return { inside: fallback, below: name ? shortName(player.name) : null };
}
