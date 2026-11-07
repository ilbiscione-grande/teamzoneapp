"use client";

// The selected objects copied on: to the next frame in one press, or to any
// other frame of the board, or to the first frame of another board; or set
// as they are here in every frame they are in. Says where they went; the
// board in hand stays shown.
import { useState } from "react";
import { copyObjects, type FramePlace } from "../../../lib/tactics/copy.ts";
import { updateBoard } from "../../../lib/tactics/document.ts";
import { copyToEveryFrame, otherFramesWith } from "../../../lib/tactics/every-frame.ts";
import type { Board } from "../../../lib/tactics/model.ts";
import { useEditor, NONE } from "../store.ts";
import { useT } from "../../language";

export function CopyTo({ board, ids }: { board: Board; ids: string[] }) {
  const t = useT();
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
    const what = result.ids.length === 1 ? t("Objektet") : t("{count} objekt", { count: result.ids.length });
    setDone(result.replaced > 0
      ? t("{what} kopierat till {where} ({count} fanns redan där och fick samma läge).", { what, where, count: result.replaced })
      : t("{what} kopierat till {where}.", { what, where }));
  };
  const elsewhere = otherFramesWith(board, frameIndex, ids);
  const copyEverywhere = () => {
    if (!window.confirm(t("Det du har markerat får samma utseende och plats i alla frames där det finns, så rörelserna mellan dem försvinner. Effekterna ligger kvar."))) return;
    useEditor.getState().change(document => updateBoard(document, board.id, current => copyToEveryFrame(current, frameIndex, ids)));
    setDone(elsewhere === 1 ? t("Kopierat till en annan frame.") : t("Kopierat till {count} andra frames.", { count: elsewhere }));
  };
  const choose = (value: string) => {
    if (value.startsWith("frame:")) {
      const index = Number(value.slice(6));
      copy({ boardId: board.id, frameIndex: index }, t("frame {number}", { number: index + 1 }));
    } else if (value.startsWith("board:")) {
      const other = others.find(item => item.id === value.slice(6));
      if (other) copy({ boardId: other.id, frameIndex: 0 }, t("{name}, frame 1", { name: other.name || t("tavlan") }));
    }
  };

  return (
    <div className="tb-copy-to">
      <div className="tb-actions">
        {next !== null && (
          <button type="button" className="wt-button secondary small" onClick={() => copy({ boardId: board.id, frameIndex: next }, `frame ${next + 1}`)}>
            {t("Kopiera till nästa frame")}
          </button>
        )}
        {elsewhere > 0 && (
          <button type="button" className="wt-button secondary small" title={t("Utseende, storlek, plats och rotation blir som i den här framen, i alla frames objektet finns i.")} onClick={copyEverywhere}>
            {t("Kopiera till alla frames")}
          </button>
        )}
        <select className="tb-panel-select" value="" aria-label={t("Kopiera till")} onChange={event => choose(event.target.value)}>
          <option value="">{t("Kopiera till…")}</option>
          {frames.length > 0 && (
            <optgroup label={t("Den här tavlan")}>
              {frames.map(index => <option key={index} value={`frame:${index}`}>{t("Frame {number}", { number: index + 1 })}{index === next ? ` ${t("(nästa)")}` : ""}</option>)}
            </optgroup>
          )}
          {others.length > 0 && (
            <optgroup label={t("Annan tavla, första frame")}>
              {others.map(other => <option key={other.id} value={`board:${other.id}`}>{other.name || t("Tavla")}</option>)}
            </optgroup>
          )}
        </select>
      </div>
      {done && <p className="tb-hint" role="status">{done}</p>}
    </div>
  );
}
