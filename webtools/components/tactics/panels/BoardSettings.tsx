"use client";

// The board's own settings: its name, duplicating it, which part of the pitch shows and how it looks, the
// grid, the teams' names and colours, and whether names show on players.
import { updateBoard } from "../../../lib/tactics/document.ts";
import { exportFileName, exportProject } from "../../../lib/tactics/transfer.ts";
import type { Board, PitchOverlay, PitchView, Side, Surroundings } from "../../../lib/tactics/model.ts";
import { BrandingFields } from "./BrandingFields.tsx";
import { useEditor, NONE } from "../store.ts";
import { patternLabels, styleOf, themes, type PitchPattern, type PitchTheme } from "../../../lib/tactics/pitch-style.ts";
import { Swatches } from "./Swatches.tsx";
import { useState } from "react";
import { ProjectFields } from "../TopBar.tsx";
import { TemplateDialog } from "../TemplateDialog.tsx";
import { HostNotes } from "../live/HostNotes.tsx";
import { PublishDialog } from "../PublishDialog.tsx";
import { ExerciseFields } from "./ExerciseFields.tsx";

const views: Record<PitchView, string> = { full: "Hel plan", attack: "Anfallshalva", defend: "Försvarshalva", empty: "Tom yta" };
const overlays: Record<PitchOverlay, string> = { none: "Inget rutnät", corridors: "Korridorer", thirds: "Tredjedelar", zones: "18 zoner" };

export function BoardSettings({ board }: { board: Board }) {
  const change = (next: (current: Board) => Board) => useEditor.getState().change(document => updateBoard(document, board.id, next));
  const attachBall = useEditor(state => state.attachBall);
  const setAttachBall = useEditor(state => state.setAttachBall);
  const [savingTemplate, setSavingTemplate] = useState(false);
  const [publishing, setPublishing] = useState(false);
  const kind = useEditor(state => state.meta?.kind);
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const style = styleOf(board.pitch);
  const exportFile = () => {
    const { meta, document } = useEditor.getState();
    if (!meta || !document) return;
    const link = window.document.createElement("a");
    link.href = URL.createObjectURL(new Blob([exportProject(meta.name, meta.kind, document)], { type: "application/json" }));
    link.download = exportFileName(meta.name);
    link.click();
    setTimeout(() => URL.revokeObjectURL(link.href), 1000);
  };
  const team = (side: Side, changes: Partial<Board["teams"][Side]>) =>
    change(current => ({ ...current, teams: { ...current.teams, [side]: { ...current.teams[side], ...changes } } }));
  return (
    <div className="tb-inspector">
      <div className="tb-project">
        <h3>Projektet</h3>
        <ProjectFields className="tb-panel-select" />
        <button type="button" className="wt-button secondary small" onClick={() => setSavingTemplate(true)}>Spara som mall…</button>
        {savingTemplate && <TemplateDialog onClose={() => setSavingTemplate(false)} />}
        <button type="button" className="wt-button secondary small" onClick={() => setPublishing(true)}>Publicera…</button>
        {publishing && <PublishDialog onClose={() => setPublishing(false)} />}
        <BrandingFields />
        <button type="button" className="wt-button secondary small" onClick={exportFile}
          title="Hela projektet som en fil, att importera på startsidan">Exportera som fil</button>
      </div>
      <h3>Tavlan</h3>
      <label className="tb-field">Namn<input value={board.name} maxLength={60} onChange={event => change(current => ({ ...current, name: event.target.value }))} /></label>
      <button type="button" className="wt-button secondary small" onClick={() => useEditor.getState().duplicateBoard(board.id)}
        title="En kopia med alla frames och effekter, direkt efter den här">Duplicera tavlan</button>
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
      <div className="tb-row">
        <label className="tb-field">Planstil
          <select value={style.theme} onChange={event => change(current => ({ ...current, pitch: { ...styleOf(current.pitch), theme: event.target.value as PitchTheme } }))}>
            {Object.entries(themes).map(([value, theme]) => <option key={value} value={value}>{theme.label}</option>)}
          </select>
        </label>
        <label className="tb-field">Mönster
          <select value={style.pattern} onChange={event => change(current => ({ ...current, pitch: { ...styleOf(current.pitch), pattern: event.target.value as PitchPattern } }))}>
            {Object.entries(patternLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </label>
      </div>
      <label className="tb-field">Omgivning
        <select value={board.surroundings ?? "none"} onChange={event => change(current => ({ ...current, surroundings: event.target.value as Surroundings }))}>
          <option value="none">Ingen</option><option value="arena">Arena med läktare</option><option value="training">Träningsplan</option>
        </select>
      </label>
      {boards.length > 1 && (
        <button type="button" className="tb-link" onClick={() => useEditor.getState().change(document => ({ ...document, boards: document.boards.map(item => ({ ...item, pitch: style, surroundings: board.surroundings })) }))}>
          Använd planstil och omgivning på alla tavlor
        </button>
      )}
      <label className="tb-field">Beskrivning
        <textarea rows={4} maxLength={2000} value={board.description ?? ""} placeholder="T.ex. organisation, anvisningar och coachpunkter. Visas bredvid tavlan i visningsläget."
          onChange={event => change(current => ({ ...current, description: event.target.value }))} />
      </label>
      <p className="tb-hint">Anteckningar för varje frame skriver du under Frames.</p>
      {kind === "training" && <ExerciseFields board={board} />}
      <HostNotes compact />
      <label className="tb-check"><input type="checkbox" checked={board.showNames} onChange={event => change(current => ({ ...current, showNames: event.target.checked }))} />Visa spelarnas namn</label>
      <label className="tb-check"><input type="checkbox" checked={board.showPositions ?? false} onChange={event => change(current => ({ ...current, showPositions: event.target.checked }))} />Visa spelarnas positioner</label>
      <label className="tb-check"><input type="checkbox" checked={board.showFacing ?? false} onChange={event => change(current => ({ ...current, showFacing: event.target.checked }))} />Visa blickriktning (vrid spelaren med ramen)</label>
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
