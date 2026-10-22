"use client";

// The board's own settings: its name, which part of the pitch shows, the
// grid, the teams' names and colours, and whether names show on players.
import { updateBoard } from "../../../lib/tactics/document.ts";
import type { Board, PitchOverlay, PitchView, Side } from "../../../lib/tactics/model.ts";
import { useEditor } from "../store.ts";
import { Swatches } from "./Swatches.tsx";
import { useState } from "react";
import { ProjectFields } from "../TopBar.tsx";
import { TemplateDialog } from "../TemplateDialog.tsx";

const views: Record<PitchView, string> = { full: "Hel plan", attack: "Anfallshalva", defend: "Försvarshalva", empty: "Tom yta" };
const overlays: Record<PitchOverlay, string> = { none: "Inget rutnät", corridors: "Korridorer", thirds: "Tredjedelar", zones: "18 zoner" };

export function BoardSettings({ board }: { board: Board }) {
  const change = (next: (current: Board) => Board) => useEditor.getState().change(document => updateBoard(document, board.id, next));
  const attachBall = useEditor(state => state.attachBall);
  const setAttachBall = useEditor(state => state.setAttachBall);
  const [savingTemplate, setSavingTemplate] = useState(false);
  const frameIndex = useEditor(state => Math.min(state.frameIndex, board.frames.length - 1));
  const team = (side: Side, changes: Partial<Board["teams"][Side]>) =>
    change(current => ({ ...current, teams: { ...current.teams, [side]: { ...current.teams[side], ...changes } } }));
  return (
    <div className="tb-inspector">
      <div className="tb-project">
        <h3>Projektet</h3>
        <ProjectFields className="tb-panel-select" />
        <button type="button" className="wt-button secondary small" onClick={() => setSavingTemplate(true)}>Spara som mall…</button>
        {savingTemplate && <TemplateDialog onClose={() => setSavingTemplate(false)} />}
      </div>
      <h3>Tavlan</h3>
      <label className="tb-field">Namn<input value={board.name} maxLength={60} onChange={event => change(current => ({ ...current, name: event.target.value }))} /></label>
      <div className="tb-row">
        <label className="tb-field">Plan
          <select value={board.view} onChange={event => change(current => ({ ...current, view: event.target.value as PitchView }))}>
            {Object.entries(views).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </label>
        <label className="tb-field">Rutnät
          <select value={board.overlay} onChange={event => change(current => ({ ...current, overlay: event.target.value as PitchOverlay }))}>
            {Object.entries(overlays).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </label>
      </div>
      <label className="tb-field">{board.frames.length > 1 ? `Anteckning för ram ${frameIndex + 1}` : "Anteckning"}
        <textarea rows={2} maxLength={500} value={board.frames[frameIndex]?.note ?? ""} placeholder="Visas under bilden i PDF:en"
          onChange={event => change(current => ({ ...current, frames: current.frames.map((frame, index) => index === frameIndex ? { ...frame, note: event.target.value } : frame) }))} />
      </label>
      <label className="tb-check"><input type="checkbox" checked={board.showNames} onChange={event => change(current => ({ ...current, showNames: event.target.checked }))} />Visa spelarnas namn</label>
      <label className="tb-check"><input type="checkbox" checked={board.showPositions ?? false} onChange={event => change(current => ({ ...current, showPositions: event.target.checked }))} />Visa spelarnas positioner</label>
      <label className="tb-check"><input type="checkbox" checked={attachBall} onChange={event => setAttachBall(event.target.checked)} />Bollen fäster vid spelare</label>
      {(["home", "away"] as Side[]).map(side => (
        <fieldset key={side} className="tb-team">
          <legend>{side === "home" ? "Hemmalag" : "Bortalag"}</legend>
          <label className="tb-field">Namn<input value={board.teams[side].name} maxLength={40} onChange={event => team(side, { name: event.target.value })} /></label>
          <Swatches label="Färg" value={board.teams[side].color} onChange={color => team(side, { color })} />
          <Swatches label="Nummerfärg" value={board.teams[side].numberColor} onChange={numberColor => team(side, { numberColor })} />
        </fieldset>
      ))}
    </div>
  );
}
