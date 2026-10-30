"use client";

// Under a shared board: which frame it is and its note, changing with the
// frame as it plays, and the board's description behind a button. A fixed
// height, so a longer note never makes the board jump.
import { useState } from "react";
import type { Board } from "../../lib/tactics/model.ts";
import { useEditor } from "./store.ts";

export function SharedCaption({ board }: { board: Board }) {
  const [about, setAbout] = useState(false);
  // While playing: the frame being moved into.
  const index = useEditor(state => Math.min(board.frames.length - 1, state.playing ? Math.ceil(state.playhead - 1e-6) : Math.round(state.playhead)));
  const frames = board.frames.length;
  const note = board.frames[index]?.note?.trim() ?? "";
  const description = board.description?.trim() ?? "";
  return (
    <div className="tb-caption">
      <div className="tb-caption-text">
        {frames > 1 && <strong>Frame {index + 1} av {frames}{note ? ": " : " · "}</strong>}
        {note || (frames > 1 ? <span className="tb-caption-hint">Svep åt sidan för att byta frame, tryck på planen för att spela.</span> : null)}
      </div>
      {description && <button type="button" className="tb-caption-about" onClick={() => setAbout(true)}>Om tavlan</button>}
      {about && (
        <div className="tb-caption-sheet" role="dialog" aria-label="Om tavlan" onClick={() => setAbout(false)}>
          <div onClick={event => event.stopPropagation()}>
            <div className="tb-modal-head">
              <h2>{board.name || "Om tavlan"}</h2>
              <button type="button" className="tb-modal-close" aria-label="Stäng" onClick={() => setAbout(false)}>×</button>
            </div>
            <p>{description}</p>
          </div>
        </div>
      )}
    </div>
  );
}
