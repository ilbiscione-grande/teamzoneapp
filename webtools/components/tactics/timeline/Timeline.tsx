"use client";

// Under the board: the timeline to scrub, play and pause, loop and speed,
// the frames to choose from, a new frame copied from the one in hand, its length and how it
// eases, moving and removing it, and recording the play as a video. Under it a slot of fixed
// height for the frame's tools or a hint, so scrubbing never changes the board's size.
import { useState } from "react";
import { insertFrame, moveFrame, removeFrame, setFrameDuration, setFrameEasing, updateBoard } from "../../../lib/tactics/document.ts";
import type { Board, Easing } from "../../../lib/tactics/model.ts";
import { easingLabels } from "../panels/effects.ts";
import { isBetween, useEditor } from "../store.ts";
import { Scrubber } from "./Scrubber.tsx";
import { usePlayback } from "./use-playback.ts";
import { canRecord, download, recordBoard } from "./video-export.ts";

const durations = [500, 750, 1000, 1500, 2000, 3000, 4000];
const speeds = [0.5, 1, 1.5, 2];

/** readOnly: for a shared link, playing and choosing frames only. */
export function Timeline({ board, readOnly = false }: { board: Board; readOnly?: boolean }) {
  usePlayback();
  const frameIndex = useEditor(state => state.frameIndex);
  const playing = useEditor(state => state.playing);
  const playhead = useEditor(state => state.playhead);
  const loop = useEditor(state => state.loop);
  const speed = useEditor(state => state.speed);
  const between = useEditor(isBetween);
  const { setFrame, play, pause, setLoop, setSpeed, change } = useEditor.getState();
  const [recording, setRecording] = useState<number | null>(null);
  const [error, setError] = useState("");
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
  const record = async () => {
    setError("");
    setRecording(0);
    try {
      const video = await recordBoard(share => setRecording(share));
      if (!video) setError("Webbläsaren kan inte spela in video här.");
      else download(video.blob, `${(board.name || "tavla").replace(/[^\p{L}\p{N}]+/gu, "_")}.${video.extension}`);
    } catch {
      setError("Videon kunde inte spelas in.");
    }
    setRecording(null);
  };

  const moving = playing || between;
  return (
    <div className="tb-timeline" aria-label="Frames och uppspelning">
      {frames.length > 1 ? <Scrubber frames={frames} /> : <div className="tb-progress" aria-hidden="true" />}
      <div className="tb-timeline-row">
        <button type="button" className="tb-play" disabled={frames.length < 2 || recording !== null}
          aria-label={playing ? "Pausa" : "Spela"} title={frames.length < 2 ? "Lägg till en frame för att spela" : undefined}
          onClick={() => (playing ? pause() : play())}>{playing ? "❚❚" : "▶"}</button>
        <div className="tb-frames" role="tablist" aria-label="Frames">
          {frames.map((frame, index) => (
            <button key={frame.id} type="button" role="tab" aria-selected={!moving && index === frameIndex}
              data-current={moving && Math.round(playhead) === index} onClick={() => setFrame(index)}>{index + 1}</button>
          ))}
          {!readOnly && <button type="button" className="tb-frame-add" onClick={add} disabled={playing} aria-label="Ny frame (kopia av denna)" title="Ny frame: en kopia av den här att flytta vidare i">+</button>}
        </div>
        <span className="tb-spacer" />
        <label className="tb-mini" title="Spela om och om igen">
          <input type="checkbox" checked={loop} onChange={event => setLoop(event.target.checked)} /><span className="tb-mini-text">Slinga</span><span className="tb-mini-icon" aria-hidden="true">⟲</span>
        </label>
        <select className="tb-mini-select" value={speed} aria-label="Hastighet" onChange={event => setSpeed(Number(event.target.value))}>
          {speeds.map(value => <option key={value} value={value}>{value}×</option>)}
        </select>
        {canRecord() && (
          <button type="button" className="tb-mini-button" disabled={frames.length < 2 || playing || recording !== null} onClick={() => void record()}>
            {recording !== null ? `Spelar in ${Math.round(recording * 100)} %` : "Video"}
          </button>
        )}
      </div>
      {!readOnly && (
        <div className="tb-timeline-foot">
          {between ? (
            <p className="tb-timeline-hint">Mellan frame {Math.floor(playhead) + 1} och {Math.floor(playhead) + 2}. Välj en frame för att redigera.</p>
          ) : !moving && frameIndex > 0 ? (
            <div className="tb-timeline-row tb-frame-tools">
              <span className="tb-mini-text">Frame {frameIndex + 1}</span>
              <label className="tb-mini"><span className="tb-mini-text">Förflyttning</span>
                <select className="tb-mini-select" value={frames[frameIndex].durationMs}
                  onChange={event => changeBoard(current => setFrameDuration(current, frameIndex, Number(event.target.value)))}>
                  {[...new Set([...durations, frames[frameIndex].durationMs])].sort((a, b) => a - b).map(value => (
                    <option key={value} value={value}>{(value / 1000).toLocaleString("sv-SE")} s</option>
                  ))}
                </select>
              </label>
              <select className="tb-mini-select" value={frames[frameIndex].easing ?? "smooth"} aria-label="Rörelsen"
                onChange={event => changeBoard(current => setFrameEasing(current, frameIndex, event.target.value as Easing))}>
                {Object.entries(easingLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
              <button type="button" className="tb-mini-button" onClick={() => move(-1)} aria-label="Flytta framen bakåt">←</button>
              <button type="button" className="tb-mini-button" disabled={frameIndex >= last} onClick={() => move(1)} aria-label="Flytta framen framåt">→</button>
              <button type="button" className="tb-mini-button" onClick={remove}>Ta bort frame</button>
            </div>
          ) : !playing && frames.length < 2 ? (
            <p className="tb-timeline-hint">Tryck + för en ny frame, flytta spelarna och tryck ▶ för att se rörelsen.</p>
          ) : null}
        </div>
      )}
      {error && <p className="tb-timeline-hint" role="alert">{error}</p>}
    </div>
  );
}
