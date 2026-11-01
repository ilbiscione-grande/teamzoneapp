"use client";

// What is set once rather than while drawing, in a dialog opened from the
// top bar or the empty Egenskaper panel: the board's name, description,
// exercise and notes, the pitch and what shows on it, the teams' names and
// colours, and the project itself (name, kind, team, template and logo).
// Publishing and the file are under Dela.
import { useEffect, useState } from "react";
import { create } from "zustand";
import { updateBoard } from "../../lib/tactics/document.ts";
import type { Board, PitchOverlay, PitchView, Side, Surroundings } from "../../lib/tactics/model.ts";
import { patternLabels, styleOf, themes, type PitchPattern, type PitchTheme } from "../../lib/tactics/pitch-style.ts";
import { BrandingFields } from "./panels/BrandingFields.tsx";
import { Swatches } from "./panels/Swatches.tsx";
import { activeBoard, useEditor, NONE } from "./store.ts";
import { ProjectFields } from "./TopBar.tsx";
import { TemplateDialog } from "./TemplateDialog.tsx";
import { HostNotes } from "./live/HostNotes.tsx";
import { ExerciseFields } from "./panels/ExerciseFields.tsx";

type Tab = "board" | "pitch" | "teams" | "project";
const tabs: Record<Tab, string> = { board: "Tavlan", pitch: "Planen", teams: "Lagen", project: "Projektet" };

/** Open from anywhere in the editor: the top bar's button and the board's panel. */
export const useSettings = create<{ tab: Tab | null; open: (tab?: Tab) => void; close: () => void }>(set => ({
  tab: null,
  open: (tab = "board") => set({ tab }),
  close: () => set({ tab: null }),
}));

const views: Record<PitchView, string> = { full: "Hel plan", attack: "Anfallshalva", defend: "Försvarshalva", empty: "Tom yta" };
const overlays: Record<PitchOverlay, string> = { none: "Inget rutnät", corridors: "Korridorer", thirds: "Tredjedelar", zones: "18 zoner" };

function change(board: Board, next: (current: Board) => Board) {
  useEditor.getState().change(document => updateBoard(document, board.id, next));
}

function BoardFields({ board }: { board: Board }) {
  const kind = useEditor(state => state.meta?.kind);
  // The notes are the owner's; another leader of the team changes the boards only.
  const owner = useEditor(state => state.meta?.access === "owner");
  const set = (next: (current: Board) => Board) => change(board, next);
  return (
    <>
      <label className="tb-field">Namn<input value={board.name} maxLength={60} onChange={event => set(current => ({ ...current, name: event.target.value }))} /></label>
      <label className="tb-field">Beskrivning
        <textarea rows={4} maxLength={2000} value={board.description ?? ""} placeholder="T.ex. organisation, anvisningar och coachpunkter. Visas bredvid tavlan i visningsläget."
          onChange={event => set(current => ({ ...current, description: event.target.value }))} />
      </label>
      <p className="tb-hint">Anteckningar för varje frame skriver du under Frames.</p>
      {kind === "training" && <ExerciseFields board={board} />}
      {owner && <HostNotes compact />}
    </>
  );
}

function PitchFields({ board }: { board: Board }) {
  const attachBall = useEditor(state => state.attachBall);
  const setAttachBall = useEditor(state => state.setAttachBall);
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const style = styleOf(board.pitch);
  const set = (next: (current: Board) => Board) => change(board, next);
  return (
    <>
      <p className="tb-hint">Gäller tavlan {board.name || "Tavla"}.</p>
      <div className="tb-row">
        <label className="tb-field">Plan
          <select value={board.view} onChange={event => set(current => ({ ...current, view: event.target.value as PitchView }))}>
            {Object.entries(views).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </label>
        <label className="tb-field">Rutnät
          <select value={board.overlay} onChange={event => set(current => ({ ...current, overlay: event.target.value as PitchOverlay }))}>
            {Object.entries(overlays).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </label>
      </div>
      <div className="tb-row">
        <label className="tb-field">Planstil
          <select value={style.theme} onChange={event => set(current => ({ ...current, pitch: { ...styleOf(current.pitch), theme: event.target.value as PitchTheme } }))}>
            {Object.entries(themes).map(([value, theme]) => <option key={value} value={value}>{theme.label}</option>)}
          </select>
        </label>
        <label className="tb-field">Mönster
          <select value={style.pattern} onChange={event => set(current => ({ ...current, pitch: { ...styleOf(current.pitch), pattern: event.target.value as PitchPattern } }))}>
            {Object.entries(patternLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </label>
      </div>
      <label className="tb-field">Omgivning
        <select value={board.surroundings ?? "none"} onChange={event => set(current => ({ ...current, surroundings: event.target.value as Surroundings }))}>
          <option value="none">Ingen</option><option value="arena">Arena med läktare</option><option value="training">Träningsplan</option>
        </select>
      </label>
      {boards.length > 1 && (
        <button type="button" className="tb-link" onClick={() => useEditor.getState().change(document => ({ ...document, boards: document.boards.map(item => ({ ...item, pitch: style, surroundings: board.surroundings })) }))}>
          Använd planstil och omgivning på alla tavlor
        </button>
      )}
      <h3 className="tb-settings-heading">På planen</h3>
      <label className="tb-check"><input type="checkbox" checked={board.showNames} onChange={event => set(current => ({ ...current, showNames: event.target.checked }))} />Visa spelarnas namn</label>
      <label className="tb-check"><input type="checkbox" checked={board.showPositions ?? false} onChange={event => set(current => ({ ...current, showPositions: event.target.checked }))} />Visa spelarnas positioner</label>
      <label className="tb-check"><input type="checkbox" checked={board.showFacing ?? false} onChange={event => set(current => ({ ...current, showFacing: event.target.checked }))} />Visa blickriktning (vrid spelaren med ramen)</label>
      <label className="tb-check"><input type="checkbox" checked={attachBall} onChange={event => setAttachBall(event.target.checked)} />Bollen fäster vid spelare</label>
    </>
  );
}

function TeamFields({ board }: { board: Board }) {
  const team = (side: Side, changes: Partial<Board["teams"][Side]>) =>
    change(board, current => ({ ...current, teams: { ...current.teams, [side]: { ...current.teams[side], ...changes } } }));
  return (
    <>
      <p className="tb-hint">Gäller tavlan {board.name || "Tavla"}.</p>
      <div className="tb-settings-teams">
        {(["home", "away"] as Side[]).map(side => (
          <fieldset key={side} className="tb-team">
            <legend>{side === "home" ? "Hemmalag" : "Bortalag"}</legend>
            <label className="tb-field">Namn<input value={board.teams[side].name} maxLength={40} onChange={event => team(side, { name: event.target.value })} /></label>
            <Swatches label="Färg" value={board.teams[side].color} onChange={color => team(side, { color })} />
            <Swatches label="Nummerfärg" value={board.teams[side].numberColor} onChange={numberColor => team(side, { numberColor })} />
          </fieldset>
        ))}
      </div>
    </>
  );
}

function ProjectSettings() {
  const [savingTemplate, setSavingTemplate] = useState(false);
  return (
    <>
      <ProjectFields className="tb-panel-select" />
      <BrandingFields />
      <div className="tb-actions">
        <button type="button" className="wt-button secondary small" onClick={() => setSavingTemplate(true)}>Spara som mall…</button>
      </div>
      <p className="tb-hint">Publicera i klubbens bibliotek och spara projektet som fil gör du under Dela.</p>
      {savingTemplate && <TemplateDialog onClose={() => setSavingTemplate(false)} />}
    </>
  );
}

export function SettingsDialog() {
  const tab = useSettings(state => state.tab);
  const { open, close } = useSettings.getState();
  const board = useEditor(activeBoard);
  useEffect(() => {
    if (!tab) return;
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") close(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [tab, close]);
  if (!tab || !board) return null;
  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label="Inställningar"
      onClick={event => { if (event.target === event.currentTarget) close(); }}>
      <div className="tb-modal-card tb-settings">
        <div className="tb-modal-head">
          <h2>Inställningar</h2>
          <button type="button" className="tb-modal-close" aria-label="Stäng" onClick={close}>×</button>
        </div>
        <div className="tb-settings-tabs" role="tablist">
          {(Object.entries(tabs) as [Tab, string][]).map(([value, label]) => (
            <button key={value} type="button" role="tab" aria-selected={tab === value} onClick={() => open(value)}>{label}</button>
          ))}
        </div>
        <div className="tb-inspector" role="tabpanel">
          {tab === "board" && <BoardFields board={board} />}
          {tab === "pitch" && <PitchFields board={board} />}
          {tab === "teams" && <TeamFields board={board} />}
          {tab === "project" && <ProjectSettings />}
        </div>
      </div>
    </div>
  );
}
