"use client";

// Under a participant's board: the question on the pitch (and how to
// answer it, or that the answers are shown), where the lesson is (board,
// frame), who has the floor, and why something could not be sent.
import { activeBoard, isBetween, useEditor, NONE } from "../store.ts";
import { useDraw } from "./draw-store.ts";
import { latestQuestion, useQuestions } from "./question-store.ts";
import { useT } from "../../language";

export function LiveWhere({ hasFloor }: { hasFloor: boolean }) {
  const t = useT();
  const board = useEditor(activeBoard);
  const boards = useEditor(store => store.document?.boards ?? NONE);
  const playhead = useEditor(store => store.playhead);
  const between = useEditor(isBetween);
  const floorName = useDraw(store => store.floorName);
  const floorHolder = useDraw(store => store.floorHolder);
  const error = useDraw(store => store.error);
  const question = useQuestions(latestQuestion);
  const questionError = useQuestions(store => store.error);
  if (!board) return null;
  const frame = Math.floor(playhead) + 1;
  const where = between ? t("Mellan frame {first} och {second}", { first: frame, second: frame + 1 }) : t("Frame {number} av {count}", { number: Math.round(playhead) + 1, count: board.frames.length });
  return (
    <div className="tb-live-where" aria-live="polite">
      {question && question.status === "open" && (
        <p className="tb-live-ask"><strong>{t("Fråga:")}</strong> {question.prompt}
          <span> {question.board_id !== board.id ? t("Läraren ställde den på en annan tavla.") : question.mine ? t("Ditt svar är skickat. Tryck igen för att flytta det.") : t("Tryck på planen för att svara.")}</span>
        </p>
      )}
      {question && question.status === "closed" && question.revealed && question.board_id === board.id && (
        <p className="tb-live-ask"><strong>{t("Svaren:")}</strong> {question.prompt} <span>{question.mine ? t("Den röda värmen visar var alla svarade, den gula ringen är ditt svar.") : t("Den röda värmen visar var alla svarade.")}</span></p>
      )}
      {questionError && <p className="tb-live-floor" role="alert">{t(questionError)}</p>}
      {hasFloor && <p className="tb-live-floor">{t("Du har ordet: flytta spelarna och objekten på tavlan.")}</p>}
      {!hasFloor && floorHolder && floorName && <p className="tb-live-floor">{t("{name} har ordet.", { name: floorName })}</p>}
      {error && <p className="tb-live-floor" role="alert">{t(error)}</p>}
      <strong>{board.name || t("Tavla")}</strong>{boards.length > 1 && <span>{t(" · tavla {number} av {count}", { number: boards.findIndex(item => item.id === board.id) + 1, count: boards.length })}</span>}
      {board.frames.length > 1 && <span> · {where}</span>}
    </div>
  );
}

/** The pen, when the host lets participants draw, and clearing one's own notes. */
export function LiveDrawButtons() {
  const t = useT();
  const drawMode = useDraw(store => store.drawMode);
  const pen = useDraw(store => store.pen);
  const boardId = useEditor(store => store.boardId);
  const ownHere = useDraw(store => store.own.some(stroke => stroke.board_id === boardId));
  if (drawMode === "off") return null;
  return (
    <>
      <button type="button" className="tb-present-toggle" aria-pressed={pen} onClick={() => useDraw.getState().set({ pen: !pen, error: "" })}
        title={drawMode === "own" ? t("Rita egna anteckningar, bara du ser dem") : t("Rita, alla ser det")}>{t("✏️ Rita")}</button>
      {drawMode === "own" && ownHere && (
        <button type="button" className="tb-present-toggle" onClick={() => useDraw.getState().set({ own: useDraw.getState().own.filter(stroke => stroke.board_id !== boardId) })}>{t("Sudda mina")}</button>
      )}
    </>
  );
}
