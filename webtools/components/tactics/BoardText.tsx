"use client";

// Beside a presented board: its description and the note of the frame in
// hand. Used when presenting and when following a live lesson.
import { activeBoard, useEditor } from "./store.ts";

export function BoardText({ emptyHint }: { emptyHint: string }) {
  const board = useEditor(activeBoard);
  const frameIndex = useEditor(state => state.frameIndex);
  const description = board?.description?.trim() ?? "";
  const note = board?.frames[frameIndex]?.note?.trim() ?? "";
  return (
    <aside className="tb-present-text" aria-label="Beskrivning">
      {description ? <p>{description}</p> : <p className="tb-present-empty">{emptyHint}</p>}
      {note && (
        <>
          <h3>Frame {frameIndex + 1}</h3>
          <p>{note}</p>
        </>
      )}
    </aside>
  );
}

/** Whether a board has anything to show beside it. */
export function hasBoardText(state: ReturnType<typeof useEditor.getState>): boolean {
  const board = activeBoard(state);
  return !!(board?.description?.trim() || board?.frames[state.frameIndex]?.note?.trim());
}
