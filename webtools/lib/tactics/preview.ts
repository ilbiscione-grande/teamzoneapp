// A shared link's preview in a chat (WhatsApp, Messenger, a text message):
// a board's first frame as plain boxes and dots, in shares (0–1) of the
// picture, for the server to draw without the board's own canvas. The
// lines of the pitch and its players and ball; nothing else.
import { viewRect } from "./geometry.ts";
import { PITCH_LENGTH as L, PITCH_WIDTH as W, type Board, type ProjectKind } from "./model.ts";

/** A project's kind in words; here so the server can use them too. */
export const kindNames: Record<ProjectKind, string> = { match: "Match", training: "Träning", education: "Utbildning" };

export type PreviewBox = { left: number; top: number; width: number; height: number; round?: boolean };
export type PreviewDot = { left: number; top: number; fill: string; ink: string; label: string; ball: boolean };
export type Preview = { lines: PreviewBox[]; dots: PreviewDot[]; aspect: number };

const BOX = { depth: 16.5, width: 40.32 }, SIX = { depth: 5.5, width: 18.32 }, CIRCLE = 9.15;

/** The board's first frame for a preview; `aspect` is the view's width over its height. */
export function previewOf(board: Board): Preview {
  const rect = viewRect(board.view === "empty" ? "full" : board.view, 3);
  const box = (x: number, y: number, width: number, height: number, round = false): PreviewBox => ({
    left: (x - rect.x) / rect.width, top: (y - rect.y) / rect.height, width: width / rect.width, height: height / rect.height, round,
  });
  const lines = board.view === "empty" ? [] : [
    box(0, 0, L, W),
    box(L / 2, 0, 0, W),
    box(L / 2 - CIRCLE, W / 2 - CIRCLE, CIRCLE * 2, CIRCLE * 2, true),
    box(0, (W - BOX.width) / 2, BOX.depth, BOX.width),
    box(L - BOX.depth, (W - BOX.width) / 2, BOX.depth, BOX.width),
    box(0, (W - SIX.width) / 2, SIX.depth, SIX.width),
    box(L - SIX.depth, (W - SIX.width) / 2, SIX.depth, SIX.width),
  ];
  const inView = (x: number, y: number) => x >= rect.x && x <= rect.x + rect.width && y >= rect.y && y <= rect.y + rect.height;
  const dots: PreviewDot[] = [];
  for (const item of board.frames[0]?.objects ?? []) {
    if (item.hidden || !inView(item.x, item.y)) continue;
    const at = { left: (item.x - rect.x) / rect.width, top: (item.y - rect.y) / rect.height };
    if (item.type === "player") {
      const team = board.teams[item.side];
      dots.push({ ...at, fill: item.color ?? team.color, ink: team.numberColor, label: item.number === null ? "" : String(item.number), ball: false });
    } else if (item.type === "ball" && !item.attachedTo) {
      dots.push({ ...at, fill: "#ffffff", ink: "#111827", label: "", ball: true });
    }
  }
  return { lines, dots, aspect: rect.width / rect.height };
}

/** The line under the title: what it is and how much. */
export function previewSummary(kindLabel: string, boardCount: number, teamName: string | null): string {
  return [kindLabel, boardCount === 1 ? "1 tavla" : `${boardCount} tavlor`, teamName].filter(Boolean).join(" · ");
}
