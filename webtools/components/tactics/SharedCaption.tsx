"use client";

// Under a shared board: which frame it is and its note, changing with the
// frame as it plays. A fixed height, so a longer note never makes the board jump;
// none at all for a board without notes, whose pitch gets the room.
import type { Board } from "../../lib/tactics/model.ts";
import { useEditor } from "./store.ts";

export function SharedCaption({ board }: { board: Board }) {
  // While playing: the frame being moved into.
  const index = useEditor(state => Math.min(board.frames.length - 1, state.playing ? Math.ceil(state.playhead - 1e-6) : Math.round(state.playhead)));
  const frames = board.frames.length;
  const note = board.frames[index]?.note?.trim() ?? "";
  if (!board.frames.some(frame => frame.note?.trim())) return null;
  return (
    <div className="tb-caption">
      <div className="tb-caption-text">
        {frames > 1 && <strong>Frame {index + 1} av {frames}{note ? ": " : " · "}</strong>}
        {note || (frames > 1 ? <span className="tb-caption-hint">Svep eller ‹ › byter frame, tryck på planen för att spela.</span> : null)}
      </div>
    </div>
  );
}
