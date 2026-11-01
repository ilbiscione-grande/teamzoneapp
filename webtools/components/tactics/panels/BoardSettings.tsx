"use client";

// Egenskaper with nothing chosen: a word on choosing something, and the way
// to the board's own details, which are written once and so are under
// Inställningar rather than always in the panel.
import type { Board } from "../../../lib/tactics/model.ts";
import { useSettings } from "../SettingsDialog.tsx";
import { SettingsIcon } from "../TopBarIcons.tsx";

export function BoardSettings({ board }: { board: Board }) {
  return (
    <div className="tb-inspector">
      <p className="tb-empty">Inget är markerat. Tryck på ett objekt på planen, eller välj det under Objekt, så visas dess egenskaper här.</p>
      <div className="tb-board-summary">
        <strong>{board.name || "Tavla"}</strong>
        {board.description?.trim() && <p className="tb-hint">{board.description.trim()}</p>}
      </div>
      <button type="button" className="wt-button secondary small tb-settings-open" onClick={() => useSettings.getState().open()}>
        <SettingsIcon />Tavlans uppgifter…
      </button>
      <p className="tb-hint">Namn, beskrivning, övning och anteckningar, plan, lag och projekt finns under Inställningar, även via kugghjulet ovanför planen. Byt namn på en tavla genom att dubbelklicka på dess flik.</p>
    </div>
  );
}
