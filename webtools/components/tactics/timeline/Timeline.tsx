"use client";

// Under the board: the timeline to scrub, and one row to play and pause,
// choose among the frames (scrolled sideways when there are many), add one
// copied from the one in hand, set the frame's own tools, and loop and speed.
// One row of fixed height, so that scrubbing never changes the board's size.
import { useEffect, useRef } from "react";
import { insertFrame, updateBoard } from "../../../lib/tactics/document.ts";
import type { Board } from "../../../lib/tactics/model.ts";
import { isBetween, stepFrame, useEditor } from "../store.ts";
import { FrameTools } from "./FrameTools.tsx";
import { Scrubber } from "./Scrubber.tsx";
import { usePlayback } from "./use-playback.ts";
import { useRecording } from "./video-export.ts";
import { useLanguage } from "../../language";

const speeds = [0.5, 1, 1.5, 2];

/**
 * readOnly: playing and stepping through the frames only (presenting, a shared link).
 * viewer: a shared link's players: no seconds, no loop, and 3D on the board instead.
 */
export function Timeline({ board, readOnly = false, viewer = false }: { board: Board; readOnly?: boolean; viewer?: boolean }) {
  const { t } = useLanguage();
  usePlayback();
  const frameIndex = useEditor(state => state.frameIndex);
  const playing = useEditor(state => state.playing);
  const playhead = useEditor(state => state.playhead);
  const loop = useEditor(state => state.loop);
  const speed = useEditor(state => state.speed);
  const tilt = useEditor(state => state.tilt);
  const between = useEditor(isBetween);
  const { setFrame, play, pause, setLoop, setSpeed, setTilt, change } = useEditor.getState();
  // A video is recorded from the share dialog by playing the board.
  const recording = useRecording(state => state.share);
  const frames = board.frames;
  const changeBoard = (next: (current: Board) => Board) => change(document => updateBoard(document, board.id, next));

  const add = () => {
    changeBoard(current => insertFrame(current, frameIndex));
    setFrame(frameIndex + 1);
  };
  const moving = playing || between;
  // The frame in hand, or the one being played, is kept in view among many.
  const list = useRef<HTMLDivElement>(null);
  const shown = moving ? Math.round(playhead) : frameIndex;
  useEffect(() => {
    const box = list.current;
    const chip = box?.children[shown] as HTMLElement | undefined;
    if (!box || !chip) return;
    if (chip.offsetLeft < box.scrollLeft) box.scrollLeft = chip.offsetLeft;
    else if (chip.offsetLeft + chip.offsetWidth > box.scrollLeft + box.clientWidth) box.scrollLeft = chip.offsetLeft + chip.offsetWidth - box.clientWidth;
  }, [shown, frames.length]);

  return (
    <div className="tb-timeline" aria-label={t("Frames och uppspelning")}>
      {/* A shared board keeps it all on one row, the timeline between the buttons, for the pitch's room. */}
      {viewer ? null : frames.length > 1 ? <Scrubber frames={frames} /> : <div className="tb-progress" aria-hidden="true" />}
      <div className={readOnly ? "tb-timeline-row" : "tb-timeline-row tb-timeline-edit"}>
        {/* A shared board: a step either way round the play button; the dots on the timeline are the frames. */}
        {readOnly && frames.length > 1 && (
          <button type="button" className="tb-step" aria-label={t("Föregående frame")} onClick={() => stepFrame(-1)}>‹</button>
        )}
        <button type="button" className="tb-play" disabled={frames.length < 2 || recording !== null}
          aria-label={playing ? t("Pausa") : t("Spela")} title={frames.length < 2 ? t("Lägg till en frame för att spela") : playing ? t("Pausa (mellanslag)") : t("Spela (mellanslag)")}
          onClick={() => (playing ? pause() : play())}>{playing ? "❚❚" : "▶"}</button>
        {readOnly && frames.length > 1 && (
          <button type="button" className="tb-step" aria-label={t("Nästa frame")} onClick={() => stepFrame(1)}>›</button>
        )}
        {viewer && frames.length > 1 && <Scrubber frames={frames} time={false} />}
        {!readOnly && <div className="tb-frames-wrap">
          <div ref={list} className="tb-frames" role="tablist" aria-label={t("Frames")} onWheel={event => { event.currentTarget.scrollLeft += event.deltaY; }}>
            {frames.map((frame, index) => (
              <button key={frame.id} type="button" role="tab" aria-selected={!moving && index === frameIndex}
                data-current={moving && Math.round(playhead) === index} onClick={() => setFrame(index)}>{index + 1}</button>
            ))}
          </div>
          <button type="button" className="tb-frame-add" onClick={add} disabled={playing} aria-label={t("Ny frame (kopia av denna)")} title={t("Ny frame: en kopia av den här att flytta vidare i")}>+</button>
        </div>}
        {readOnly ? !viewer && <span className="tb-spacer" /> : frames.length > 1
          ? <FrameTools board={board} moving={moving} changeBoard={changeBoard}
              hint={between ? t("Mellan frame {from} och {to}. Välj en frame för att redigera.", { from: Math.floor(playhead) + 1, to: Math.floor(playhead) + 2 }) : undefined} />
          : <p className="tb-timeline-hint">{t("Tryck + för en ny frame, flytta spelarna och tryck ▶ för att se rörelsen.")}</p>}
        {!viewer && <button type="button" className="tb-mini-button" aria-pressed={tilt} onClick={() => setTilt(!tilt)}
          title={t("Planen sedd snett från läktaren. Redigera uppifrån.")}>3D</button>}
        {!viewer && <label className="tb-mini" title={t("Spela om och om igen")}>
          <input type="checkbox" checked={loop} aria-label={t("Slinga")} onChange={event => setLoop(event.target.checked)} /><span className="tb-mini-icon" aria-hidden="true">⟲</span>
        </label>}
        <select className="tb-mini-select" value={speed} aria-label={t("Hastighet")} onChange={event => setSpeed(Number(event.target.value))}>
          {speeds.map(value => <option key={value} value={value}>{value}×</option>)}
        </select>
      </div>
    </div>
  );
}
