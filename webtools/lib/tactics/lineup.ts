// A TeamZone team's formations with what each place asks for, and the
// suggestion of who plays where (docs/implementation/player-attributes.md).
// Places carry the app's codes: GK, then each line from the own goal, left to
// right as the team attacks: 1A, 1B … 2A … Tacticsboard's formationPositions
// gives the spots in the same order, so code n is spot n.
import { createPlayer } from "./document.ts";
import { formationPositions } from "./formations.ts";
import type { PlayerObject, Side, SquadPlayer, TacticsObject } from "./model.ts";

export type MatchFormat = "5v5" | "7v7" | "9v9" | "11v11";
export type Requirement = { attribute: string; weight: 1 | 2 };
/** A place: its code, the general position of its line, and what it asks for (a position, a foot, attributes). */
export type FormationSlot = { code: string; group: string; position: string | null; foot?: "left" | "right" | null; requirements: Requirement[] };
export type TeamFormation = {
  id: string; name: string; lines: string; match_format: MatchFormat | "3v3"; revision: number; slots: FormationSlot[];
  /** A ready-made formation: read-only, copied to change. */
  template?: boolean;
};

const FORMAT_ORDER = ["11v11", "9v9", "7v7", "5v5", "3v3"];

/** Formations grouped by match format, the largest first. */
export function byFormat(formations: TeamFormation[]): [string, TeamFormation[]][] {
  return FORMAT_ORDER.map(format => [format, formations.filter(item => item.match_format === format)] as [string, TeamFormation[]])
    .filter(([, items]) => items.length > 0);
}

/** "11 mot 11" for 11v11. */
export const formatName = (format: string, english = false) => format.replace("v", english ? " v " : " mot ");

export type SuggestedSlot = {
  code: string; group: string; locked: boolean;
  person_id: string | null; name?: string | null; number?: number | null;
  score?: number; position_fit?: "main" | "other" | "group" | "none";
  strengths?: string[]; development?: string[];
  /** The foot the place asks for, and how the player's fits it. */
  foot?: "left" | "right" | null; foot_fit?: "good" | "both" | "weaker" | "wrong" | null;
  alternatives?: { person_id: string; name: string; score: number }[];
};
export type Suggestion = { slots: SuggestedSlot[]; bench: { person_id: string; name: string; number: number | null }[] };

/** The match format of a formation with a goalkeeper: 4-3-3 is 11 a side. */
export function matchFormat(lines: number[]): MatchFormat | null {
  const players = lines.reduce((sum, n) => sum + n, 0) + 1;
  return players === 11 ? "11v11" : players === 9 ? "9v9" : players === 7 ? "7v7" : players === 5 ? "5v5" : null;
}

/** The places of a formation with a goalkeeper, in spot order, each with the general position of its line. */
export function formationSlots(lines: number[]): { code: string; group: string }[] {
  return [
    { code: "GK", group: "goalkeeper" },
    ...lines.flatMap((count, line) => Array.from({ length: count }, (_, place) => ({
      code: `${line + 1}${String.fromCharCode(65 + place)}`,
      group: line === 0 && lines.length > 1 ? "defender" : line === lines.length - 1 ? "forward" : "midfielder",
    }))),
  ];
}

/** "4-3-3" → [4, 3, 3]. */
export const linesOf = (text: string) => text.split("-").map(Number);

/** A short name for a place, as the app's line-up shows it (MV, VB, MB, CM, VY, ANF …). */
export function slotLabel(lines: number[], code: string, english = false): string {
  if (code === "GK") return english ? "GK" : "MV";
  const line = Number(code.slice(0, -1)) - 1;
  const place = code.charCodeAt(code.length - 1) - 65;
  const count = lines[line] ?? 0;
  const edge = count >= 3 && (place === 0 || place === count - 1);
  const left = place === 0;
  const pick = (sv: string, en: string) => english ? en : sv;
  if (line === 0 && lines.length > 1) return edge ? (left ? pick("VB", "LB") : pick("HB", "RB")) : pick("MB", "CB");
  if (line === lines.length - 1) return count === 3 && edge ? (left ? pick("VY", "LW") : pick("HY", "RW")) : pick("ANF", "ST");
  if (lines.length === 4) return line === 1 ? pick("DM", "DM") : edge ? (left ? pick("VY", "LW") : pick("HY", "RW")) : pick("OM", "AM");
  return edge ? (left ? pick("VM", "LM") : pick("HM", "RM")) : pick("CM", "CM");
}

/**
 * Puts a suggestion on the pitch for [side]: each suggested player at the spot
 * of their place, kept when already on the board (so they move) and added from
 * the squad when not. The side's squad players left out of the suggestion go;
 * players without a TeamZone person fill places left empty, or stay put.
 */
export function applySuggestion(objects: TacticsObject[], side: Side, lines: number[], slots: SuggestedSlot[], squad: SquadPlayer[]): TacticsObject[] {
  const spots = formationPositions(lines, side);
  const chosen = new Map(slots.flatMap((slot, index) => slot.person_id && spots[index] ? [[slot.person_id, spots[index]] as const] : []));
  const ours = (item: TacticsObject): item is PlayerObject => item.type === "player" && item.side === side && !item.hidden;
  let next = objects.filter(item => !(ours(item) && item.personId && !chosen.has(item.personId)));
  const spare = next.filter((item): item is PlayerObject => ours(item) && !item.personId);
  next = next.map(item => ours(item) && item.personId && chosen.has(item.personId) ? { ...item, ...chosen.get(item.personId)! } : item);
  const onBoard = new Set(next.flatMap(item => ours(item) && item.personId ? [item.personId] : []));
  const moved = new Map<string, { x: number; y: number }>();
  slots.forEach((slot, index) => {
    const spot = spots[index];
    if (!spot) return;
    if (slot.person_id) {
      if (onBoard.has(slot.person_id)) return;
      const player = squad.find(entry => entry.personId === slot.person_id)
        ?? { personId: slot.person_id, name: slot.name ?? "", number: slot.number ?? null, position: null };
      next = [...next, createPlayer(spot, side, next, player)];
      return;
    }
    const filler = spare.shift();
    if (filler) moved.set(filler.id, spot);
  });
  return next.map(item => moved.has(item.id) ? { ...item, ...moved.get(item.id)! } : item);
}
