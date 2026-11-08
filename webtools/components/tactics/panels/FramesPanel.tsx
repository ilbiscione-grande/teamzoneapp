"use client";

// The frames (side by side on a phone, FrameCarousel): each one with its move's length and note, a new one copied
// from the one in hand, moving and removing it; and the effects of the
// frame in hand: what shows how as the board moves into it, several to an
// object if wanted, chosen for the objects selected on the pitch and tried
// out with a preview; and whether the move starts and stops softly.
import {
  duplicateFrame, insertFrame, moveFrame, objectLabel, removeFrame, setFrameDuration, setFrameEasing, toggleEffect, updateBoard,
} from "../../../lib/tactics/document.ts";
import { effectsLast, hasEffectEveryFrame, setEffectEveryFrame, setLastingEffects } from "../../../lib/tactics/every-frame.ts";
import type { Board, Easing, Effect, TacticsObject, ZoomLevel, ZoomSpeed } from "../../../lib/tactics/model.ts";
import { effectsOf } from "../../../lib/tactics/timeline.ts";
import { activeObjects, useEditor } from "../store.ts";
import { AllFrames } from "./AllFrames.tsx";
import { FrameCarousel } from "./FrameCarousel.tsx";
import { InfoIcon, usePhone } from "../ViewerTools.tsx";
import { useState } from "react";
import { easingLabels, effectKinds, effects, effectSuits, shortEasingLabels, zoomLabels, zoomSpeedLabels } from "./effects.ts";
import { useLanguage } from "../../language";

const durations = [500, 750, 1000, 1500, 2000, 3000, 4000];
const seconds = (ms: number, intl: string) => `${(ms / 1000).toLocaleString(intl)} s`;

export function FramesPanel({ board }: { board: Board }) {
  const { t, intl } = useLanguage();
  const frameIndex = useEditor(state => Math.min(state.frameIndex, board.frames.length - 1));
  const selection = useEditor(state => state.selection);
  const playing = useEditor(state => state.playing);
  const allFrames = useEditor(state => state.allFrames);
  const phone = usePhone();
  // How frames work, behind the i by the heading.
  const [info, setInfo] = useState(false);
  const { setFrame, change, patch, patchLook, select, preview } = useEditor.getState();
  const frames = board.frames;
  const frame = frames[frameIndex];
  const changeBoard = (next: (current: Board) => Board) => change(document => updateBoard(document, board.id, next));

  const add = () => {
    changeBoard(current => insertFrame(current, frameIndex));
    setFrame(frameIndex + 1);
  };
  const copy = () => {
    changeBoard(current => duplicateFrame(current, frameIndex));
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

  /** One frame to take: its number, the move's time, its effects and note. */
  const card = (index: number) => {
    const item = frames[index];
    // The first frame has no move into it, so an effect chosen for all frames plays from the second.
    const count = index === 0 ? 0 : item.objects.reduce((sum, object) => sum + effectsOf(object).length, 0);
    return (
      <button type="button" aria-current={index === frameIndex} onClick={() => setFrame(index)}>
        <strong>Frame {index + 1}</strong>
        <span>{[index > 0 ? seconds(item.durationMs, intl) : t("Start"), count > 0 ? `${count} ${count === 1 ? "effekt" : "effekter"}` : null, item.note?.trim() || null].filter(Boolean).join(" · ")}</span>
      </button>
    );
  };

  const before = new Set(frames[frameIndex - 1]?.objects.map(item => item.id) ?? []);
  const selected = frame.objects.filter(item => selection.includes(item.id));
  const withEffect = frame.objects.filter(item => effectsOf(item).length > 0);
  /** Whether an object has an effect: here, or in every frame when that is what is being chosen. */
  const hasEffect = (item: TacticsObject, kind: Effect) => allFrames ? hasEffectEveryFrame(board, item.id, kind) : effectsOf(item).includes(kind);
  /** One effect on or off for these objects where it suits, read as they are now (quick clicks build on each other). */
  const toggleOn = (ids: string[], kind: Effect, on: boolean) => {
    const suited = activeObjects(useEditor.getState()).filter(item => ids.includes(item.id) && effectSuits(kind, item));
    if (allFrames) changeBoard(current => setEffectEveryFrame(current, suited.map(item => item.id), kind, on));
    else patch(Object.fromEntries(suited.map(item => [item.id, toggleEffect(item, kind, on)])));
  };
  const toggle = (kind: Effect, on: boolean) => toggleOn(selected.map(item => item.id), kind, on);
  const clear = () => patchLook(Object.fromEntries(selected.map(item => [item.id, { effects: [], lastingEffects: [], effect: null }])));

  return (
    <div className="tb-inspector tb-frames-panel">
      <div className="tb-heading-row">
        <h3>{t("Frames")}</h3>
        <button type="button" className="tb-info-button" aria-expanded={info} aria-label={t("Om frames")} title={t("Om frames")} onClick={() => setInfo(!info)}><InfoIcon /></button>
      </div>
      {info && <p className="tb-hint">{t("En ny frame är en kopia av den du står på. Flytta spelarna i den, så spelas rörelsen upp mellan dina frames.")}</p>}
      {phone
        ? <FrameCarousel count={frames.length} current={frameIndex} card={card} />
        : <ol className="tb-frame-list">{frames.map((item, index) => <li key={item.id}>{card(index)}</li>)}</ol>}
      {/* A phone: the three on one row; frames are moved in the timeline's "more". */}
      <div className={phone ? "tb-actions tb-frame-actions" : "tb-actions"}>
        <button type="button" className="wt-button small" onClick={add} disabled={playing}>{t("+ Ny frame")}</button>
        <button type="button" className="wt-button secondary small" onClick={copy} disabled={playing} title={t("En exakt kopia direkt efter den här, med effekter, anteckning och tid.")}>{t("Kopiera frame")}</button>
        {!phone && <button type="button" className="wt-button secondary small" onClick={() => move(-1)} disabled={playing || frameIndex === 0} aria-label={t("Flytta framen bakåt")}>↑</button>}
        {!phone && <button type="button" className="wt-button secondary small" onClick={() => move(1)} disabled={playing || frameIndex >= frames.length - 1} aria-label={t("Flytta framen framåt")}>↓</button>}
        <button type="button" className="wt-button secondary small" onClick={remove} disabled={playing || frames.length < 2}>{t("Ta bort")}</button>
      </div>

      {/* The move's time and how it eases, small beside the heading, so the note shows at once. */}
      <div className="tb-heading-row">
        <h3>{t("Frame {number}", { number: frameIndex + 1 })}</h3>
        {frameIndex > 0 && (
          <span className="tb-heading-picks">
            <select className="tb-heading-pick" value={frame.durationMs} aria-label={t("Förflyttning hit")} title={t("Förflyttning hit")}
              onChange={event => changeBoard(current => setFrameDuration(current, frameIndex, Number(event.target.value)))}>
              {[...new Set([...durations, frame.durationMs])].sort((a, b) => a - b).map(value => <option key={value} value={value}>{seconds(value, intl)}</option>)}
            </select>
            <select className="tb-heading-pick" value={frame.easing ?? "smooth"} aria-label={t("Rörelsen")} title={t(easingLabels[frame.easing ?? "smooth"])}
              onChange={event => changeBoard(current => setFrameEasing(current, frameIndex, event.target.value as Easing))}>
              {Object.entries(shortEasingLabels).map(([value, label]) => <option key={value} value={value}>{t(label)}</option>)}
            </select>
          </span>
        )}
      </div>
      <label className="tb-field">{t("Anteckning")}
        <textarea rows={2} maxLength={500} value={frame.note ?? ""} placeholder={t("Visas under bilden i PDF:en och i visningsläget")}
          onChange={event => changeBoard(current => ({ ...current, frames: current.frames.map((item, index) => index === frameIndex ? { ...item, note: event.target.value } : item) }))} />
      </label>

      <h3>{t("Effekter")}</h3>
      {frameIndex === 0 ? (
        <p className="tb-hint">{frames.length < 2 ? t("Effekter spelas när tavlan går in i en frame. Välj frame 2 eller senare, eller lägg till en ny frame.") : t("Effekter spelas när tavlan går in i en frame. Välj frame 2 eller senare.")}</p>
      ) : (
        <>
          {selected.length === 0 ? (
            <p className="tb-hint">{t("Markera ett eller flera objekt på planen för att ge dem en effekt i frame {number}.", { number: frameIndex + 1 })}</p>
          ) : (
            <>
              <p className="tb-hint">{t("{what}: välj en eller flera effekter när frame {number} nås.", { what: selected.length === 1 ? objectLabel(selected[0], board, t) : t("{count} markerade", { count: selected.length }), number: frameIndex + 1 })}</p>
              <AllFrames />
              <div className="tb-effects">
                {effectKinds.map(kind => {
                  const suited = selected.filter(item => effectSuits(kind, item));
                  const all = suited.length > 0 && suited.every(item => hasEffect(item, kind));
                  return (
                    <button key={kind} type="button" aria-pressed={all} disabled={suited.length === 0} title={t(effects[kind].hint)} onClick={() => toggle(kind, !all)}>
                      <span aria-hidden="true">{effects[kind].icon}</span>
                      <strong>{t(effects[kind].label)}</strong>
                      <small>{t(effects[kind].hint)}</small>
                    </button>
                  );
                })}
              </div>
              {selected.some(item => effectsOf(item).length > 0) && <button type="button" className="tb-link" onClick={clear}>{t("Inga effekter")}</button>}
            </>
          )}
          {withEffect.length > 0 && (
            <ul className="tb-effect-list" aria-label={t("Effekter i frame {number}", { number: frameIndex + 1 })}>
              {withEffect.map(item => (
                <li key={item.id} data-selected={selection.includes(item.id)}>
                  <button type="button" className="tb-effect-name" onClick={() => select([item.id])}>
                    {objectLabel(item, board, t)}
                    <small>{before.has(item.id) ? t("finns sedan förut") : t("ny i framen")}</small>
                  </button>
                  <span className="tb-effect-toggles" role="group" aria-label={t("Effekter för {name}", { name: objectLabel(item, board, t) })}>
                    {effectKinds.filter(kind => effectSuits(kind, item)).map(kind => {
                      const on = hasEffect(item, kind);
                      return (
                        <button key={kind} type="button" aria-pressed={on} title={t(effects[kind].label)} aria-label={t(effects[kind].label)}
                          onClick={() => toggleOn([item.id], kind, !on)}>{effects[kind].icon}</button>
                      );
                    })}
                  </span>
                  <label className="tb-zoom-level" title={t("Frames du lägger till efter den här får samma effekter på objektet.")}>
                    <input type="checkbox" checked={effectsLast(item)}
                      onChange={event => changeBoard(current => setLastingEffects(current, item.id, event.target.checked ? effectsOf(item) : []))} />
                    {t("Även i nya frames")}
                  </label>
                  {effectsOf(item).includes("zoom") && (
                    <span className="tb-zoom-choices">
                      <label className="tb-zoom-level">{t("Zoom")}
                        <select value={item.zoomLevel ?? "medium"} onChange={event => patchLook({ [item.id]: { zoomLevel: event.target.value as ZoomLevel } })}>
                          {Object.entries(zoomLabels).map(([value, label]) => <option key={value} value={value}>{t(label)}</option>)}
                        </select>
                      </label>
                      <label className="tb-zoom-level">{t("In")}
                        <select value={item.zoomIn ?? "fast"} onChange={event => patchLook({ [item.id]: { zoomIn: event.target.value as ZoomSpeed } })}>
                          {Object.entries(zoomSpeedLabels).map(([value, label]) => <option key={value} value={value}>{t(label)}</option>)}
                        </select>
                      </label>
                      <label className="tb-zoom-level">{t("Ut")}
                        <select value={item.zoomOut ?? "fast"} onChange={event => patchLook({ [item.id]: { zoomOut: event.target.value as ZoomSpeed } })}>
                          {Object.entries(zoomSpeedLabels).map(([value, label]) => <option key={value} value={value}>{t(label)}</option>)}
                        </select>
                      </label>
                    </span>
                  )}
                </li>
              ))}
            </ul>
          )}
          <div className="tb-actions">
            <button type="button" className="wt-button secondary small" disabled={playing} onClick={() => preview(frameIndex)}>{t("▶ Spela frame {from} → {to}", { from: frameIndex, to: frameIndex + 1 })}</button>
          </div>
          <p className="tb-hint">{t("Nya objekt tonar in och borttagna tonar ut av sig själva.")}</p>
        </>
      )}
    </div>
  );
}
