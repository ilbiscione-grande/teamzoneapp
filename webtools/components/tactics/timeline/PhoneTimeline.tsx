"use client";

// The timeline on a phone: one row of the same height whatever the board has,
// so the pitch keeps its room: play, the frames and a new one, and "more".
// More opens over the foot of the pitch, not under it: the frame's time and
// motion, moving or removing it, 3D, loop and speed. A tap outside closes it.
import { useEffect, useRef, useState } from "react";
import type { Board } from "../../../lib/tactics/model.ts";
import { useEditor } from "../store.ts";
import { FrameStrip } from "./FrameStrip.tsx";
import { FrameTools } from "./FrameTools.tsx";
import { PlaySettings } from "./Timeline.tsx";
import { useRecording } from "./video-export.ts";
import { useLanguage } from "../../language";

export function PhoneTimeline({ board, moving, onAdd, changeBoard }: {
  board: Board; moving: boolean; onAdd: () => void; changeBoard: (next: (current: Board) => Board) => void;
}) {
  const { t } = useLanguage();
  const playing = useEditor(state => state.playing);
  const recording = useRecording(state => state.share);
  const [more, setMore] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!more) return;
    const close = (event: PointerEvent) => { if (!root.current?.contains(event.target as Node)) setMore(false); };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, [more]);
  const frames = board.frames;
  const { play, pause } = useEditor.getState();

  return (
    <div ref={root} className="tb-timeline tb-phone-timeline" aria-label={t("Frames och uppspelning")}>
      {more && (
        <div className="tb-phone-more" role="group" aria-label={t("Mer för frames och uppspelning")}>
          {frames.length > 1
            ? <FrameTools board={board} moving={moving} changeBoard={changeBoard} />
            : <p className="tb-timeline-hint">{t("Tryck + för en ny frame, flytta spelarna och tryck ▶ för att se rörelsen.")}</p>}
          <div className="tb-phone-more-row"><PlaySettings /></div>
        </div>
      )}
      <div className="tb-timeline-row tb-timeline-edit">
        <button type="button" className="tb-play" disabled={frames.length < 2 || recording !== null}
          aria-label={playing ? t("Pausa") : t("Spela")} onClick={() => (playing ? pause() : play())}>{playing ? "❚❚" : "▶"}</button>
        <FrameStrip frames={frames} moving={moving} onAdd={onAdd} />
        <button type="button" className="tb-mini-button tb-phone-more-button" aria-expanded={more}
          aria-label={t("Mer för frames och uppspelning")} onClick={() => setMore(!more)}>⋯</button>
      </div>
    </div>
  );
}
