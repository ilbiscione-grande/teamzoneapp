// Where each board picture goes in the PDF: A4 landscape, a header with the
// project and board, one big picture or four frames to a page with their
// captions, page numbers at the foot. A board's description takes a column
// to the right on its first page. Pure, in millimetres.
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

export type Box = { x: number; y: number; width: number; height: number };

export type Page = {
  boardIndex: number;
  title: string;
  placements: Placement[];
  /** The board's description and where it goes: its first page only. */
  description?: { text: string } & Box;
};

export const PAGE = { width: 297, height: 210, margin: 12, header: 16, footer: 8 };
/** The pictures' shape: the pitch with its grass, as the board fits it. */
export const PICTURE_RATIO = 3 / 2;
/** The description's column, right of the pictures. */
export const DESCRIPTION_WIDTH = 78;
const COLUMN_GAP = 8;

/** The largest picture of the board's shape that fits a box. */
function fit(box: Box, captionSpace: number) {
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
    const text = board.description?.trim() || null;
    const firstPage = pages.length;
    // The board's first page gives the description a column; later pages use the whole width.
    const areaOf = (pageIndex: number): Box => text && pageIndex === firstPage
      ? { ...area, width: area.width - DESCRIPTION_WIDTH - COLUMN_GAP }
      : area;
    const describe = () => {
      const page = pages[firstPage];
      if (text && page) page.description = { text, x: area.x + area.width - DESCRIPTION_WIDTH, y: area.y, width: DESCRIPTION_WIDTH, height: area.height };
    };
    const count = board.frames.length;
    const chosen = count === 1 || frames === "last" ? [count - 1] : board.frames.map((_, index) => index);
    const caption = (index: number) => count > 1 && frames !== "last" ? `Frame ${index + 1} av ${count}` : null;
    const note = (index: number) => board.frames[index]?.note?.trim() || null;
    if (frames === "grid" && chosen.length > 1) {
      // Four to a page, two by two.
      const gap = 6;
      for (let start = 0; start < chosen.length; start += 4) {
        const room = areaOf(pages.length);
        const cell = { width: (room.width - gap) / 2, height: (room.height - gap) / 2 };
        const placements = chosen.slice(start, start + 4).map((frameIndex, slot) => {
          const box = {
            x: room.x + (slot % 2) * (cell.width + gap),
            y: room.y + Math.floor(slot / 2) * (cell.height + gap),
            ...cell,
          };
          return { boardIndex, frameIndex, ...fit(box, 9), caption: caption(frameIndex), note: note(frameIndex) };
        });
        pages.push({ boardIndex, title: board.name, placements });
      }
      describe();
      continue;
    }
    for (const frameIndex of chosen) {
      const room = areaOf(pages.length);
      pages.push({
        boardIndex, title: board.name,
        placements: [{ boardIndex, frameIndex, ...fit(room, caption(frameIndex) || note(frameIndex) ? 12 : 0), caption: caption(frameIndex), note: note(frameIndex) }],
      });
    }
    describe();
  }
  return pages;
}

/** A safe file name from the project's name. */
export function pdfFileName(name: string): string {
  const safe = name.trim().replace(/[^\p{L}\p{N}]+/gu, "_").replace(/^_+|_+$/g, "");
  return `${safe || "tavla"}.pdf`;
}
