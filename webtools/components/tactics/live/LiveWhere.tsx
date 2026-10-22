"use client";

// Under a participant's board: where the lesson is (board, frame), who has
// the floor, and why a drawing could not be sent.
import { activeBoard, isBetween, useEditor, NONE } from "../store.ts";
import { useDraw } from "./draw-store.ts";

export function LiveWhere({ hasFloor }: { hasFloor: boolean }) {
  const board = useEditor(activeBoard);
  const boards = useEditor(store => store.document?.boards ?? NONE);
  const playhead = useEditor(store => store.playhead);
  const between = useEditor(isBetween);
  const floorName = useDraw(store => store.floorName);
  const floorHolder = useDraw(store => store.floorHolder);
  const error = useDraw(store => store.error);
  if (!board) return null;
  const frame = Math.floor(playhead) + 1;
  const where = between ? `Mellan frame ${frame} och ${frame + 1}` : `Frame ${Math.round(playhead) + 1} av ${board.frames.length}`;
  return (
    <div className="tb-live-where" aria-live="polite">
      {hasFloor && <p className="tb-live-floor">Du har ordet: flytta spelarna och objekten på tavlan.</p>}
      {!hasFloor && floorHolder && floorName && <p className="tb-live-floor">{floorName} har ordet.</p>}
      {error && <p className="tb-live-floor" role="alert">{error}</p>}
      <strong>{board.name || "Tavla"}</strong>{boards.length > 1 && <span> · tavla {boards.findIndex(item => item.id === board.id) + 1} av {boards.length}</span>}
      {board.frames.length > 1 && <span> · {where}</span>}
    </div>
  );
}

/** The pen, when the host lets participants draw, and clearing one's own notes. */
export function LiveDrawButtons() {
  const drawMode = useDraw(store => store.drawMode);
  const pen = useDraw(store => store.pen);
  const boardId = useEditor(store => store.boardId);
  const ownHere = useDraw(store => store.own.some(stroke => stroke.board_id === boardId));
  if (drawMode === "off") return null;
  return (
    <>
      <button type="button" className="tb-present-toggle" aria-pressed={pen} onClick={() => useDraw.getState().set({ pen: !pen, error: "" })}
        title={drawMode === "own" ? "Rita egna anteckningar, bara du ser dem" : "Rita, alla ser det"}>✏️ Rita</button>
      {drawMode === "own" && ownHere && (
        <button type="button" className="tb-present-toggle" onClick={() => useDraw.getState().set({ own: useDraw.getState().own.filter(stroke => stroke.board_id !== boardId) })}>Sudda mina</button>
      )}
    </>
  );
}
