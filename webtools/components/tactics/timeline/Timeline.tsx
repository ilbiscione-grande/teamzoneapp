"use client";

// Under the board: the timeline to scrub, play and pause, loop and speed,
// the frames to choose from, a new frame copied from the one in hand, its length and how it
// eases, moving and removing it. Under it a slot of fixed
// height for the frame's tools or a hint, so scrubbing never changes the board's size.
import { insertFrame, moveFrame, removeFrame, setFrameDuration, setFrameEasing, updateBoard } from "../../../lib/tactics/document.ts";
import type { Board, Easing } from "../../../lib/tactics/model.ts";
import { easingLabels } from "../panels/effects.ts";
import { isBetween, stepFrame, useEditor } from "../store.ts";
import { Scrubber } from "./Scrubber.tsx";
import { usePlayback } from "./use-playback.ts";
import { useRecording } from "./video-export.ts";
import { useLanguage } from "../../language";

const durations = [500, 750, 1000, 1500, 2000, 3000, 4000];
const speeds = [0.5, 1, 1.5, 2];

/**
 * readOnly: playing and stepping through the frames only (presenting, a shared link).
 * viewer: a shared link's players: no seconds, no loop, and 3D on the board instead.
 */
export function Timeline({ board, readOnly = false, viewer = false }: { board: Board; readOnly?: boolean; viewer?: boolean }) {
  const { t, intl } = useLanguage();
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
  const last = frames.length - 1;
  const changeBoard = (next: (current: Board) => Board) => change(document => updateBoard(document, board.id, next));

  const add = () => {
    changeBoard(current => insertFrame(current, frameIndex));
    setFrame(frameIndex + 1);
  };
  const remove = () => {
    if (frames.length < 2 || !window.confirm(`Ta bort frame ${frameIndex + 1}?`)) return;
    changeBoard(current => removeFrame(current, frameIndex));
    setFrame(Math.min(frameIndex, last - 1));
  };
  const move = (step: 1 | -1) => {
    changeBoard(current => moveFrame(current, frameIndex, step));
    setFrame(frameIndex + step);
  };

  const moving = playing || between;
  return (
    <div className="tb-timeline" aria-label={t("Frames och uppspelning")}>
      {/* A shared board keeps it all on one row, the timeline between the buttons, for the pitch's room. */}
      {viewer ? null : frames.length > 1 ? <Scrubber frames={frames} /> : <div className="tb-progress" aria-hidden="true" />}
      <div className="tb-timeline-row">
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
        {!readOnly && <div className="tb-frames" role="tablist" aria-label={t("Frames")}>
          {frames.map((frame, index) => (
            <button key={frame.id} type="button" role="tab" aria-selected={!moving && index === frameIndex}
              data-current={moving && Math.round(playhead) === index} onClick={() => setFrame(index)}>{index + 1}</button>
          ))}
          <button type="button" className="tb-frame-add" onClick={add} disabled={playing} aria-label={t("Ny frame (kopia av denna)")} title={t("Ny frame: en kopia av den här att flytta vidare i")}>+</button>
        </div>}
        {!viewer && <span className="tb-spacer" />}
        {!viewer && <button type="button" className="tb-mini-button" aria-pressed={tilt} onClick={() => setTilt(!tilt)}
          title={t("Planen sedd snett från läktaren. Redigera uppifrån.")}>3D</button>}
        {!viewer && <label className="tb-mini" title={t("Spela om och om igen")}>
          <input type="checkbox" checked={loop} onChange={event => setLoop(event.target.checked)} /><span className="tb-mini-text">{t("Slinga")}</span><span className="tb-mini-icon" aria-hidden="true">⟲</span>
        </label>}
        <select className="tb-mini-select" value={speed} aria-label={t("Hastighet")} onChange={event => setSpeed(Number(event.target.value))}>
          {speeds.map(value => <option key={value} value={value}>{value}×</option>)}
        </select>
      </div>
      {!readOnly && (
        <div className="tb-timeline-foot">
          {between ? (
            <p className="tb-timeline-hint">{t("Mellan frame {from} och {to}. Välj en frame för att redigera.", { from: Math.floor(playhead) + 1, to: Math.floor(playhead) + 2 })}</p>
          ) : !moving && frameIndex > 0 ? (
            <div className="tb-timeline-row tb-frame-tools">
              <span className="tb-mini-text">Frame {frameIndex + 1}</span>
              <label className="tb-mini"><span className="tb-mini-text">{t("Förflyttning")}</span>
                <select className="tb-mini-select" value={frames[frameIndex].durationMs}
                  onChange={event => changeBoard(current => setFrameDuration(current, frameIndex, Number(event.target.value)))}>
                  {[...new Set([...durations, frames[frameIndex].durationMs])].sort((a, b) => a - b).map(value => (
                    <option key={value} value={value}>{(value / 1000).toLocaleString(intl)} s</option>
                  ))}
                </select>
              </label>
              <select className="tb-mini-select" value={frames[frameIndex].easing ?? "smooth"} aria-label={t("Rörelsen")}
                onChange={event => changeBoard(current => setFrameEasing(current, frameIndex, event.target.value as Easing))}>
                {Object.entries(easingLabels).map(([value, label]) => <option key={value} value={value}>{t(label)}</option>)}
              </select>
              <button type="button" className="tb-mini-button" onClick={() => move(-1)} aria-label={t("Flytta framen bakåt")}>←</button>
              <button type="button" className="tb-mini-button" disabled={frameIndex >= last} onClick={() => move(1)} aria-label={t("Flytta framen framåt")}>→</button>
              <button type="button" className="tb-mini-button" onClick={remove}>{t("Ta bort frame")}</button>
            </div>
          ) : !playing && frames.length < 2 ? (
            <p className="tb-timeline-hint">{t("Tryck + för en ny frame, flytta spelarna och tryck ▶ för att se rörelsen.")}</p>
          ) : null}
        </div>
      )}
    </div>
  );
}
