"use client";

// The frames: each one with its move's length and note, a new one copied
// from the one in hand, moving and removing it; and the effects of the
// frame in hand: what shows how as the board moves into it, several to an
// object if wanted, chosen for the objects selected on the pitch and tried
// out with a preview; and whether the move starts and stops softly.
import {
  insertFrame, moveFrame, objectLabel, removeFrame, setFrameDuration, setFrameEasing, toggleEffect, updateBoard,
} from "../../../lib/tactics/document.ts";
import type { Board, Easing, Effect, ZoomLevel } from "../../../lib/tactics/model.ts";
import { effectsOf } from "../../../lib/tactics/timeline.ts";
import { activeObjects, useEditor } from "../store.ts";
import { easingLabels, effectKinds, effects, effectSuits, zoomLabels } from "./effects.ts";

const durations = [500, 750, 1000, 1500, 2000, 3000, 4000];
const seconds = (ms: number) => `${(ms / 1000).toLocaleString("sv-SE")} s`;

export function FramesPanel({ board }: { board: Board }) {
  const frameIndex = useEditor(state => Math.min(state.frameIndex, board.frames.length - 1));
  const selection = useEditor(state => state.selection);
  const playing = useEditor(state => state.playing);
  const { setFrame, change, patch, select, preview } = useEditor.getState();
  const frames = board.frames;
  const frame = frames[frameIndex];
  const changeBoard = (next: (current: Board) => Board) => change(document => updateBoard(document, board.id, next));

  const add = () => {
    changeBoard(current => insertFrame(current, frameIndex));
    setFrame(frameIndex + 1);
  };
  const remove = () => {
    if (frames.length < 2 || !window.confirm(`Ta bort frame ${frameIndex + 1}?`)) return;
    changeBoard(current => removeFrame(current, frameIndex));
    setFrame(Math.min(frameIndex, frames.length - 2));
  };
  const move = (step: 1 | -1) => {
    changeBoard(current => moveFrame(current, frameIndex, step));
    setFrame(frameIndex + step);
  };

  const before = new Set(frames[frameIndex - 1]?.objects.map(item => item.id) ?? []);
  const selected = frame.objects.filter(item => selection.includes(item.id));
  const withEffect = frame.objects.filter(item => effectsOf(item).length > 0);
  /** One effect on or off for these objects where it suits, read as they are now (quick clicks build on each other). */
  const toggleOn = (ids: string[], kind: Effect, on: boolean) => patch(Object.fromEntries(activeObjects(useEditor.getState())
    .filter(item => ids.includes(item.id) && effectSuits(kind, item))
    .map(item => [item.id, toggleEffect(item, kind, on)])));
  const toggle = (kind: Effect, on: boolean) => toggleOn(selected.map(item => item.id), kind, on);
  const clear = () => patch(Object.fromEntries(selected.map(item => [item.id, { effects: [], effect: null }])));

  return (
    <div className="tb-inspector tb-frames-panel">
      <h3>Frames</h3>
      <ol className="tb-frame-list">
        {frames.map((item, index) => {
          const count = item.objects.reduce((sum, object) => sum + effectsOf(object).length, 0);
          return (
            <li key={item.id}>
              <button type="button" aria-current={index === frameIndex} onClick={() => setFrame(index)}>
                <strong>Frame {index + 1}</strong>
                <span>{[index > 0 ? seconds(item.durationMs) : "Start", count > 0 ? `${count} ${count === 1 ? "effekt" : "effekter"}` : null, item.note?.trim() || null].filter(Boolean).join(" · ")}</span>
              </button>
            </li>
          );
        })}
      </ol>
      <div className="tb-actions">
        <button type="button" className="wt-button small" onClick={add} disabled={playing}>+ Ny frame</button>
        <button type="button" className="wt-button secondary small" onClick={() => move(-1)} disabled={playing || frameIndex === 0} aria-label="Flytta framen bakåt">↑</button>
        <button type="button" className="wt-button secondary small" onClick={() => move(1)} disabled={playing || frameIndex >= frames.length - 1} aria-label="Flytta framen framåt">↓</button>
        <button type="button" className="wt-button secondary small" onClick={remove} disabled={playing || frames.length < 2}>Ta bort</button>
      </div>
      <p className="tb-hint">En ny frame är en kopia av den du står på. Flytta spelarna i den, så spelas rörelsen upp mellan dina frames.</p>

      <h3>Frame {frameIndex + 1}</h3>
      {frameIndex > 0 && (
        <label className="tb-field">Förflyttning hit
          <select value={frame.durationMs} onChange={event => changeBoard(current => setFrameDuration(current, frameIndex, Number(event.target.value)))}>
            {[...new Set([...durations, frame.durationMs])].sort((a, b) => a - b).map(value => <option key={value} value={value}>{seconds(value)}</option>)}
          </select>
        </label>
      )}
      {frameIndex > 0 && (
        <label className="tb-field">Rörelsen
          <select value={frame.easing ?? "smooth"} onChange={event => changeBoard(current => setFrameEasing(current, frameIndex, event.target.value as Easing))}>
            {Object.entries(easingLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </label>
      )}
      <label className="tb-field">Anteckning
        <textarea rows={2} maxLength={500} value={frame.note ?? ""} placeholder="Visas under bilden i PDF:en och i visningsläget"
          onChange={event => changeBoard(current => ({ ...current, frames: current.frames.map((item, index) => index === frameIndex ? { ...item, note: event.target.value } : item) }))} />
      </label>

      <h3>Effekter</h3>
      {frameIndex === 0 ? (
        <p className="tb-hint">Effekter spelas när tavlan går in i en frame. Välj frame 2 eller senare{frames.length < 2 ? ", eller lägg till en ny frame" : ""}.</p>
      ) : (
        <>
          {selected.length === 0 ? (
            <p className="tb-hint">Markera ett eller flera objekt på planen för att ge dem en effekt i frame {frameIndex + 1}.</p>
          ) : (
            <>
              <p className="tb-hint">{selected.length === 1 ? objectLabel(selected[0], board) : `${selected.length} markerade`}: välj en eller flera effekter när frame {frameIndex + 1} nås.</p>
              <div className="tb-effects">
                {effectKinds.map(kind => {
                  const suited = selected.filter(item => effectSuits(kind, item));
                  const all = suited.length > 0 && suited.every(item => effectsOf(item).includes(kind));
                  return (
                    <button key={kind} type="button" aria-pressed={all} disabled={suited.length === 0} title={effects[kind].hint} onClick={() => toggle(kind, !all)}>
                      <span aria-hidden="true">{effects[kind].icon}</span>
                      <strong>{effects[kind].label}</strong>
                      <small>{effects[kind].hint}</small>
                    </button>
                  );
                })}
              </div>
              {selected.some(item => effectsOf(item).length > 0) && <button type="button" className="tb-link" onClick={clear}>Inga effekter</button>}
            </>
          )}
          {withEffect.length > 0 && (
            <ul className="tb-effect-list" aria-label={`Effekter i frame ${frameIndex + 1}`}>
              {withEffect.map(item => (
                <li key={item.id} data-selected={selection.includes(item.id)}>
                  <button type="button" className="tb-effect-name" onClick={() => select([item.id])}>
                    {objectLabel(item, board)}
                    <small>{before.has(item.id) ? "finns sedan förut" : "ny i framen"}</small>
                  </button>
                  <span className="tb-effect-toggles" role="group" aria-label={`Effekter för ${objectLabel(item, board)}`}>
                    {effectKinds.filter(kind => effectSuits(kind, item)).map(kind => {
                      const on = effectsOf(item).includes(kind);
                      return (
                        <button key={kind} type="button" aria-pressed={on} title={effects[kind].label} aria-label={effects[kind].label}
                          onClick={() => toggleOn([item.id], kind, !on)}>{effects[kind].icon}</button>
                      );
                    })}
                  </span>
                  {effectsOf(item).includes("zoom") && (
                    <label className="tb-zoom-level">Zoom
                      <select value={item.zoomLevel ?? "medium"} onChange={event => patch({ [item.id]: { zoomLevel: event.target.value as ZoomLevel } })}>
                        {Object.entries(zoomLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                      </select>
                    </label>
                  )}
                </li>
              ))}
            </ul>
          )}
          <div className="tb-actions">
            <button type="button" className="wt-button secondary small" disabled={playing} onClick={() => preview(frameIndex)}>▶ Spela frame {frameIndex} → {frameIndex + 1}</button>
          </div>
          <p className="tb-hint">Nya objekt tonar in och borttagna tonar ut av sig själva.</p>
        </>
      )}
    </div>
  );
}
