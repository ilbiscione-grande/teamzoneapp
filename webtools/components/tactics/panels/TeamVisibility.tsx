"use client";

// Either team hidden or shown, in the frame in hand or in every frame: an
// attack played with the opponents and then without them. Hidden players stay
// in the object list, where one at a time can be shown again.
import { updateBoard } from "../../../lib/tactics/document.ts";
import { hideSide, sideHidden } from "../../../lib/tactics/hiding.ts";
import type { Board, Side } from "../../../lib/tactics/model.ts";
import { useEditor } from "../store.ts";
import { useT } from "../../language";

export function TeamVisibility({ board, frameIndex }: { board: Board; frameIndex: number }) {
  const t = useT();
  const sides = (["home", "away"] as Side[]).filter(side => board.frames.some(frame => sideHidden(frame.objects, side) !== null));
  if (sides.length === 0) return null;
  const set = (side: Side, where: number | "all", hidden: boolean) =>
    useEditor.getState().change(document => updateBoard(document, board.id, current => hideSide(current, where, side, hidden)));
  const many = board.frames.length > 1;

  return (
    <>
      <h3>{t("Visa och dölj")}</h3>
      {sides.map(side => {
        const here = sideHidden(board.frames[frameIndex]?.objects ?? [], side);
        const everywhere = board.frames.every(frame => { const state = sideHidden(frame.objects, side); return state === null || state === "all"; });
        return (
          <div key={side} className="tb-field">{t(board.teams[side].name)}
            <div className="tb-actions">
              {here !== null && (
                <button type="button" className="wt-button secondary small" aria-pressed={here === "all"} onClick={() => set(side, frameIndex, here !== "all")}>
                  {here === "all" ? t("Visa i framen") : t("Dölj i framen")}
                </button>
              )}
              {many && (
                <button type="button" className="wt-button secondary small" aria-pressed={everywhere} onClick={() => set(side, "all", !everywhere)}>
                  {everywhere ? t("Visa i alla frames") : t("Dölj i alla frames")}
                </button>
              )}
            </div>
          </div>
        );
      })}
      <p className="tb-hint">{t("Dolda spelare finns kvar under Objekt, där du kan visa en i taget. De syns inte på planen, när tavlan spelas, i PDF, video eller delade länkar.")}</p>
    </>
  );
}
