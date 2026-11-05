"use client";

// Egenskaper with nothing chosen: a word on choosing something, and the way
// to the board's own details, which are written once and so are under
// Inställningar rather than always in the panel.
import type { Board } from "../../../lib/tactics/model.ts";
import { useSettings } from "../SettingsDialog.tsx";
import { SettingsIcon } from "../TopBarIcons.tsx";
import { useT } from "../../language";

export function BoardSettings({ board }: { board: Board }) {
  const t = useT();
  return (
    <div className="tb-inspector">
      <p className="tb-empty">{t("Inget är markerat. Tryck på ett objekt på planen, eller välj det under Objekt, så visas dess egenskaper här.")}</p>
      <div className="tb-board-summary">
        <strong>{board.name || t("Tavla")}</strong>
        {board.description?.trim() && <p className="tb-hint">{board.description.trim()}</p>}
      </div>
      <button type="button" className="wt-button secondary small tb-settings-open" onClick={() => useSettings.getState().open()}>
        <SettingsIcon />{t("Tavlans uppgifter…")}
      </button>
      <p className="tb-hint">{t("Namn, beskrivning, övning och anteckningar, plan, lag och projekt finns under Inställningar, även via kugghjulet ovanför planen. Byt namn på en tavla genom att dubbelklicka på dess flik.")}</p>
    </div>
  );
}
