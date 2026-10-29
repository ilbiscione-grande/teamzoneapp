// How a board's pitch looks: a theme (the surface's colours and the ink the
// lines are drawn in) and a pattern mown into it. Chosen per board; a board
// from before this has natural grass in stripes.
import type { PitchStyle } from "./model.ts";

export type PitchTheme = "grass" | "night" | "artificial" | "indoor" | "chalk" | "whiteboard";
export type PitchPattern = "stripes" | "crosswise" | "checks" | "diagonal" | "circles" | "plain";

export type ThemeLook = {
  label: string;
  /** The surface. */
  ground: string;
  /** The pattern's lighter parts, laid over the surface. */
  pattern: string;
  /** The pitch's lines and goals. */
  line: string;
  /** The grid of corridors, thirds or zones. */
  grid: string;
  /** What white drawing (passes, runs, trails) shows as: dark on a light surface. */
  ink: string;
  light: boolean;
};

export const themes: Record<PitchTheme, ThemeLook> = {
  grass: { label: "Gräs", ground: "#2f7d46", pattern: "rgba(255,255,255,0.045)", line: "rgba(255,255,255,0.88)", grid: "rgba(255,255,255,0.32)", ink: "#ffffff", light: false },
  night: { label: "Kvällsgräs", ground: "#17432a", pattern: "rgba(255,255,255,0.035)", line: "rgba(255,255,255,0.8)", grid: "rgba(255,255,255,0.26)", ink: "#ffffff", light: false },
  artificial: { label: "Konstgräs", ground: "#1f8a5b", pattern: "rgba(255,255,255,0.06)", line: "rgba(255,255,255,0.92)", grid: "rgba(255,255,255,0.34)", ink: "#ffffff", light: false },
  indoor: { label: "Inomhus (trägolv)", ground: "#b7834f", pattern: "rgba(255,255,255,0.07)", line: "rgba(255,255,255,0.9)", grid: "rgba(255,255,255,0.38)", ink: "#ffffff", light: false },
  chalk: { label: "Svarta tavlan", ground: "#26332c", pattern: "rgba(255,255,255,0.025)", line: "rgba(236,240,232,0.85)", grid: "rgba(236,240,232,0.3)", ink: "#f1f5f0", light: false },
  whiteboard: { label: "Whiteboard (bra för utskrift)", ground: "#f8fafc", pattern: "rgba(15,23,42,0.035)", line: "rgba(15,23,42,0.75)", grid: "rgba(15,23,42,0.25)", ink: "#111827", light: true },
};

export const patternLabels: Record<PitchPattern, string> = {
  stripes: "Ränder på längden",
  crosswise: "Ränder på tvären",
  checks: "Rutor",
  diagonal: "Diagonaler",
  circles: "Cirklar",
  plain: "Jämnt",
};

export const DEFAULT_STYLE: PitchStyle = { theme: "grass", pattern: "stripes" };

/** A board's style, made whole: unknown or missing parts fall back to grass in stripes. */
export function styleOf(style: Partial<PitchStyle> | null | undefined): PitchStyle {
  return {
    theme: style?.theme && style.theme in themes ? style.theme : DEFAULT_STYLE.theme,
    pattern: style?.pattern && style.pattern in patternLabels ? style.pattern : DEFAULT_STYLE.pattern,
  };
}

export const lookOf = (style: Partial<PitchStyle> | null | undefined) => themes[styleOf(style).theme];

/** A white drawing on a light surface shows in the theme's ink; any other colour as chosen. */
export function inkFor(color: string, look: ThemeLook): string {
  if (!look.light) return color;
  const plain = color.trim().toLowerCase();
  return plain === "#fff" || plain === "#ffffff" || plain === "white" ? look.ink : color;
}

export type PatternPiece =
  | { kind: "rect"; x: number; y: number; width: number; height: number }
  | { kind: "band"; points: number[] }
  | { kind: "ring"; inner: number; outer: number };

/** The lighter pieces of a pattern on a pitch of this length and width, in metres. */
export function patternPieces(pattern: PitchPattern, length: number, width: number): PatternPiece[] {
  switch (pattern) {
    case "stripes": {
      const n = 12;
      return Array.from({ length: n / 2 }, (_, i) => ({ kind: "rect" as const, x: (length / n) * (2 * i + 1), y: 0, width: length / n, height: width }));
    }
    case "crosswise": {
      const n = 8;
      return Array.from({ length: n / 2 }, (_, i) => ({ kind: "rect" as const, x: 0, y: (width / n) * (2 * i + 1), width: length, height: width / n }));
    }
    case "checks": {
      const across = 12, down = 8, w = length / across, h = width / down;
      const pieces: PatternPiece[] = [];
      for (let i = 0; i < across; i++) for (let j = 0; j < down; j++) if ((i + j) % 2 === 1) pieces.push({ kind: "rect", x: i * w, y: j * h, width: w, height: h });
      return pieces;
    }
    case "diagonal": {
      // Bands at 45° across the whole pitch; the pitch clips them.
      const step = 9, pieces: PatternPiece[] = [];
      for (let start = -width, i = 0; start < length; start += step, i++) {
        if (i % 2 === 0) continue;
        pieces.push({ kind: "band", points: [start, 0, start + step, 0, start + step + width, width, start + width, width] });
      }
      return pieces;
    }
    case "circles": {
      const step = 6, reach = Math.hypot(length, width) / 2, pieces: PatternPiece[] = [];
      for (let r = step, i = 1; r < reach + step; r += step, i++) if (i % 2 === 1) pieces.push({ kind: "ring", inner: r, outer: r + step });
      return pieces;
    }
    default:
      return [];
  }
}
