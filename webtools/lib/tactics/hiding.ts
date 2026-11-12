// Showing a board with or without some of it: a team's players hidden in one
// frame or in every frame, such as an attack played without the opponents.
// A hidden object stays in the document and in the object list; the pitch,
// playing, the PDF, the video and shared links leave it out.
import type { Board, Side, TacticsObject } from "./model.ts";

const ofSide = (item: TacticsObject, side: Side) => item.type === "player" && item.side === side;

/** Whether a team's players in a frame are all hidden, some, or none; null when it has none there. */
export function sideHidden(objects: TacticsObject[], side: Side): "all" | "some" | "none" | null {
  const players = objects.filter(item => ofSide(item, side));
  if (players.length === 0) return null;
  const hidden = players.filter(item => item.hidden).length;
  return hidden === players.length ? "all" : hidden > 0 ? "some" : "none";
}

/** A team's players hidden or shown in frame `frameIndex`, or in every frame when it is "all". */
export function hideSide(board: Board, frameIndex: number | "all", side: Side, hidden: boolean): Board {
  return {
    ...board,
    frames: board.frames.map((frame, index) => frameIndex !== "all" && index !== frameIndex ? frame : {
      ...frame,
      objects: frame.objects.map(item => (ofSide(item, side) && item.hidden !== hidden ? { ...item, hidden } : item)),
    }),
  };
}
