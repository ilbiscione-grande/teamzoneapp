// Where each board picture goes in the PDF: A4, a header with the project
// and board, one big picture or four frames to a page with their captions,
// page numbers at the foot. Landscape, unless a board's crop is taller than
// wide: then its pages stand, and its pictures take the crop's shape. A
// board's description takes a column to the right on its first page, or on
// a standing page a band under the pictures. Pure, in millimetres.
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
  /** A4 standing: the board's crop is taller than wide. */
  portrait: boolean;
  /** The board's description and where it goes: its first page only. */
  description?: { text: string } & Box;
};

export const PAGE = { width: 297, height: 210, margin: 12, header: 16, footer: 8 };
/** A page's size, standing or lying. */
export const pageSize = (portrait: boolean) => portrait ? { ...PAGE, width: PAGE.height, height: PAGE.width } : PAGE;
/** The pictures' shape without a crop: the pitch with its grass, as the board fits it. */
export const PICTURE_RATIO = 3 / 2;
/** The description's column, right of the pictures; on a standing page, its band under them. */
export const DESCRIPTION_WIDTH = 78;
export const DESCRIPTION_HEIGHT = 62;
const COLUMN_GAP = 8;

/** A board's pictures' width over height: its crop's, kept between 1:2 and 2:1, else the whole pitch's. */
export function pictureRatio(board: Pick<Board, "crop">): number {
  const crop = board.crop;
  if (!crop || crop.width <= 0 || crop.height <= 0) return PICTURE_RATIO;
  return Math.min(2, Math.max(0.5, crop.width / crop.height));
}

/** The largest picture of the board's shape that fits a box. */
function fit(box: Box, captionSpace: number, ratio: number) {
  const height = Math.min(box.height - captionSpace, box.width / ratio);
  const width = height * ratio;
  return { x: box.x + (box.width - width) / 2, y: box.y, width, height };
}

/** The pages for the chosen boards and frames. */
export function layoutPages(boards: Board[], boardIndexes: number[], frames: FrameChoice): Page[] {
  const pages: Page[] = [];
  for (const boardIndex of boardIndexes) {
    const board = boards[boardIndex];
    if (!board) continue;
    const ratio = pictureRatio(board);
    const portrait = ratio < 1;
    const size = pageSize(portrait);
    const area = {
      x: size.margin,
      y: size.margin + size.header,
      width: size.width - size.margin * 2,
      height: size.height - size.margin * 2 - size.header - size.footer,
    };
    const text = board.description?.trim() || null;
    const firstPage = pages.length;
    // The board's first page gives the description a column, or a band when standing; later pages use the whole area.
    const areaOf = (pageIndex: number): Box => !text || pageIndex !== firstPage ? area
      : portrait ? { ...area, height: area.height - DESCRIPTION_HEIGHT - COLUMN_GAP }
      : { ...area, width: area.width - DESCRIPTION_WIDTH - COLUMN_GAP };
    const describe = () => {
      const page = pages[firstPage];
      if (!text || !page) return;
      page.description = portrait
        ? { text, x: area.x, y: area.y + area.height - DESCRIPTION_HEIGHT, width: area.width, height: DESCRIPTION_HEIGHT }
        : { text, x: area.x + area.width - DESCRIPTION_WIDTH, y: area.y, width: DESCRIPTION_WIDTH, height: area.height };
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
          return { boardIndex, frameIndex, ...fit(box, 9, ratio), caption: caption(frameIndex), note: note(frameIndex) };
        });
        pages.push({ boardIndex, title: board.name, placements, portrait });
      }
      describe();
      continue;
    }
    for (const frameIndex of chosen) {
      const room = areaOf(pages.length);
      pages.push({
        boardIndex, title: board.name, portrait,
        placements: [{ boardIndex, frameIndex, ...fit(room, caption(frameIndex) || note(frameIndex) ? 12 : 0, ratio), caption: caption(frameIndex), note: note(frameIndex) }],
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
