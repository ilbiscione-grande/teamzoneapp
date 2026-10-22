// Where each board picture goes in the PDF: A4 landscape, a header with the
// project and board, one big picture or four frames to a page with their
// captions, page numbers at the foot. Pure, in millimetres.
import type { Board } from "./model.ts";

export type FrameChoice = "grid" | "each" | "last";

export type Placement = {
  boardIndex: number;
  frameIndex: number;
  x: number;
  y: number;
  width: number;
  height: number;
  /** "Frame 2 av 4" and the frame's note, under the picture. */
  caption: string | null;
  note: string | null;
};

export type Page = { boardIndex: number; title: string; placements: Placement[] };

export const PAGE = { width: 297, height: 210, margin: 12, header: 16, footer: 8 };
/** The pictures' shape: the pitch with its grass, as the board fits it. */
export const PICTURE_RATIO = 3 / 2;

/** The largest picture of the board's shape that fits a box. */
function fit(box: { x: number; y: number; width: number; height: number }, captionSpace: number) {
  const height = Math.min(box.height - captionSpace, box.width / PICTURE_RATIO);
  const width = height * PICTURE_RATIO;
  return { x: box.x + (box.width - width) / 2, y: box.y, width, height };
}

/** The pages for the chosen boards and frames. */
export function layoutPages(boards: Board[], boardIndexes: number[], frames: FrameChoice): Page[] {
  const pages: Page[] = [];
  const area = {
    x: PAGE.margin,
    y: PAGE.margin + PAGE.header,
    width: PAGE.width - PAGE.margin * 2,
    height: PAGE.height - PAGE.margin * 2 - PAGE.header - PAGE.footer,
  };
  for (const boardIndex of boardIndexes) {
    const board = boards[boardIndex];
    if (!board) continue;
    const count = board.frames.length;
    const chosen = count === 1 || frames === "last" ? [count - 1] : board.frames.map((_, index) => index);
    const caption = (index: number) => count > 1 && frames !== "last" ? `Frame ${index + 1} av ${count}` : null;
    const note = (index: number) => board.frames[index]?.note?.trim() || null;
    if (frames === "grid" && chosen.length > 1) {
      // Four to a page, two by two.
      const gap = 6;
      const cell = { width: (area.width - gap) / 2, height: (area.height - gap) / 2 };
      for (let start = 0; start < chosen.length; start += 4) {
        const placements = chosen.slice(start, start + 4).map((frameIndex, slot) => {
          const box = {
            x: area.x + (slot % 2) * (cell.width + gap),
            y: area.y + Math.floor(slot / 2) * (cell.height + gap),
            ...cell,
          };
          return { boardIndex, frameIndex, ...fit(box, 9), caption: caption(frameIndex), note: note(frameIndex) };
        });
        pages.push({ boardIndex, title: board.name, placements });
      }
      continue;
    }
    for (const frameIndex of chosen) {
      pages.push({
        boardIndex, title: board.name,
        placements: [{ boardIndex, frameIndex, ...fit(area, caption(frameIndex) || note(frameIndex) ? 12 : 0), caption: caption(frameIndex), note: note(frameIndex) }],
      });
    }
  }
  return pages;
}

/** A safe file name from the project's name. */
export function pdfFileName(name: string): string {
  const safe = name.trim().replace(/[^\p{L}\p{N}]+/gu, "_").replace(/^_+|_+$/g, "");
  return `${safe || "tavla"}.pdf`;
}
