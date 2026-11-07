"use client";

// Beside the frames: the length of the move into the frame in hand and how it
// eases, moving the frame and removing it. Always there, only greyed while
// the board is moving, so scrubbing moves nothing around.
import { moveFrame, removeFrame, setFrameDuration, setFrameEasing } from "../../../lib/tactics/document.ts";
import type { Board, Easing } from "../../../lib/tactics/model.ts";
import { easingLabels, shortEasingLabels } from "../panels/effects.ts";
import { useEditor } from "../store.ts";
import { useLanguage } from "../../language";

const durations = [500, 750, 1000, 1500, 2000, 3000, 4000];

export function FrameTools({ board, moving, hint, changeBoard }: {
  board: Board; moving: boolean; hint?: string; changeBoard: (next: (current: Board) => Board) => void;
}) {
  const { t, intl } = useLanguage();
  const frameIndex = useEditor(state => state.frameIndex);
  const { setFrame } = useEditor.getState();
  const last = board.frames.length - 1;
  const frame = board.frames[Math.min(frameIndex, last)];
  const first = frameIndex === 0;

  const remove = () => {
    if (!window.confirm(`Ta bort frame ${frameIndex + 1}?`)) return;
    changeBoard(current => removeFrame(current, frameIndex));
    setFrame(Math.min(frameIndex, last - 1));
  };
  const move = (step: 1 | -1) => {
    changeBoard(current => moveFrame(current, frameIndex, step));
    setFrame(frameIndex + step);
  };

  return (
    <div className="tb-frame-tools" title={hint}>
      <select className="tb-mini-select" value={frame.durationMs} disabled={moving || first} aria-label={t("Förflyttning")} title={t("Förflyttning hit")}
        onChange={event => changeBoard(current => setFrameDuration(current, frameIndex, Number(event.target.value)))}>
        {[...new Set([...durations, frame.durationMs])].sort((a, b) => a - b).map(value => (
          <option key={value} value={value}>{(value / 1000).toLocaleString(intl)} s</option>
        ))}
      </select>
      <select className="tb-mini-select" value={frame.easing ?? "smooth"} disabled={moving || first} aria-label={t("Rörelsen")} title={t(easingLabels[frame.easing ?? "smooth"])}
        onChange={event => changeBoard(current => setFrameEasing(current, frameIndex, event.target.value as Easing))}>
        {Object.entries(shortEasingLabels).map(([value, label]) => <option key={value} value={value}>{t(label)}</option>)}
      </select>
      <button type="button" className="tb-mini-button" disabled={moving || first} onClick={() => move(-1)} aria-label={t("Flytta framen bakåt")} title={t("Flytta framen bakåt")}>←</button>
      <button type="button" className="tb-mini-button" disabled={moving || frameIndex >= last} onClick={() => move(1)} aria-label={t("Flytta framen framåt")} title={t("Flytta framen framåt")}>→</button>
      <button type="button" className="tb-mini-button" disabled={moving} onClick={remove} aria-label={t("Ta bort frame")} title={t("Ta bort frame")}>🗑</button>
    </div>
  );
}
