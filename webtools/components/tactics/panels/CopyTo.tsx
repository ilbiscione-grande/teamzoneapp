"use client";

// The selected objects copied on: to the next frame in one press, or to any
// other frame of the board, or to the first frame of another board. Says
// where they went; the board in hand stays shown.
import { useState } from "react";
import { copyObjects, type FramePlace } from "../../../lib/tactics/copy.ts";
import type { Board } from "../../../lib/tactics/model.ts";
import { useEditor, NONE } from "../store.ts";

export function CopyTo({ board, ids }: { board: Board; ids: string[] }) {
  const frameIndex = useEditor(state => state.frameIndex);
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const [done, setDone] = useState("");
  const next = frameIndex + 1 < board.frames.length ? frameIndex + 1 : null;
  const others = boards.filter(other => other.id !== board.id);
  const frames = board.frames.map((_, index) => index).filter(index => index !== frameIndex);
  if (frames.length === 0 && others.length === 0) return null;

  const copy = (to: FramePlace, where: string) => {
    const { change, document } = useEditor.getState();
    if (!document) return;
    const result = copyObjects(document, { boardId: board.id, frameIndex }, ids, to);
    if (result.ids.length === 0) return;
    change(() => result.document);
    const count = result.ids.length === 1 ? "Objektet" : `${result.ids.length} objekt`;
    setDone(`${count} kopierat till ${where}${result.replaced > 0 ? ` (${result.replaced} fanns redan där och fick samma läge)` : ""}.`);
  };
  const choose = (value: string) => {
    if (value.startsWith("frame:")) {
      const index = Number(value.slice(6));
      copy({ boardId: board.id, frameIndex: index }, `frame ${index + 1}`);
    } else if (value.startsWith("board:")) {
      const other = others.find(item => item.id === value.slice(6));
      if (other) copy({ boardId: other.id, frameIndex: 0 }, `${other.name || "tavlan"}, frame 1`);
    }
  };

  return (
    <div className="tb-copy-to">
      <div className="tb-actions">
        {next !== null && (
          <button type="button" className="wt-button secondary small" onClick={() => copy({ boardId: board.id, frameIndex: next }, `frame ${next + 1}`)}>
            Kopiera till nästa frame
          </button>
        )}
        <select className="tb-panel-select" value="" aria-label="Kopiera till" onChange={event => choose(event.target.value)}>
          <option value="">Kopiera till…</option>
          {frames.length > 0 && (
            <optgroup label="Den här tavlan">
              {frames.map(index => <option key={index} value={`frame:${index}`}>Frame {index + 1}{index === next ? " (nästa)" : ""}</option>)}
            </optgroup>
          )}
          {others.length > 0 && (
            <optgroup label="Annan tavla, första frame">
              {others.map(other => <option key={other.id} value={`board:${other.id}`}>{other.name || "Tavla"}</option>)}
            </optgroup>
          )}
        </select>
      </div>
      {done && <p className="tb-hint" role="status">{done}</p>}
    </div>
  );
}
