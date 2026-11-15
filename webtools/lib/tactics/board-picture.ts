// A picture of each board's first frame, kept beside the project for the
// TeamZone app, which shows it on a training exercise linked to the board
// (api.save_tactics_board_pictures). Drawn in the browser after a save, only
// for boards whose first frame looks different from when last sent.
import type { Board, Branding } from "./model.ts";
import { pictureRatio } from "./pdf-layout.ts";

/** The picture's longer side, in pixels. */
export const PICTURE_LONG_SIDE = 640;
/** What the server takes at most for one picture. */
export const PICTURE_MAX_BYTES = 200_000;
/** How many pictures one save may send. */
export const PICTURES_PER_SAVE = 60;

/** A picture's size at a longer side: landscape, or at the crop's shape. */
export function pictureSize(board: Pick<Board, "crop">, longSide: number) {
  const ratio = pictureRatio(board);
  return ratio >= 1
    ? { width: longSide, height: Math.round(longSide / ratio) }
    : { width: Math.round(longSide * ratio), height: longSide };
}

/** What the first frame's picture is drawn from: when it changes, the picture is drawn again. */
export function pictureKey(board: Board, branding: Branding | undefined): string {
  const { id: _id, name: _name, description: _description, exercise: _exercise, frames, ...look } = board;
  return JSON.stringify([look, frames[0]?.objects ?? [], branding ?? null]);
}

/** A data URL as the server takes it: its type and its base64 without the prefix; null when it is of another type or too large. */
export function pictureData(dataUrl: string): { media_type: "image/webp" | "image/png"; data: string } | null {
  const match = /^data:(image\/(?:webp|png));base64,(.+)$/.exec(dataUrl);
  if (!match) return null;
  const data = match[2];
  if ((data.length * 3) / 4 > PICTURE_MAX_BYTES) return null;
  return { media_type: match[1] as "image/webp" | "image/png", data };
}
