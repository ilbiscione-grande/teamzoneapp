"use client";

// Development only: the workspace on a board in memory, with a few players,
// a ball and a pass, so the board can be tried without an account.
import { useEffect, useState } from "react";
import { applyFormation, createObject, newDocument, updateFrame } from "../../lib/tactics/document.ts";
import { formations } from "../../lib/tactics/formations.ts";
import { useEditor } from "./store.ts";
import { TacticsWorkspace } from "./TacticsEditor.tsx";

export function TacticsDemo() {
  const [ready, setReady] = useState(false);
  useEffect(() => {
    let document = newDocument("Uppställning");
    const board = document.boards[0];
    document = updateFrame(document, board.id, 0, objects => {
      const placed = applyFormation(applyFormation(objects, "home", formations["4-3-3"]), "away", formations["4-4-2"]);
      return [...placed, createObject("ball", { x: 52.5, y: 34 }), createObject("cone", { x: 30, y: 60 })];
    });
    useEditor.getState().load({
      id: "demo", name: "Demo", kind: "match", teamzone_team_id: null, team_name: null, board_count: 1, revision: 1,
      created_at: new Date().toISOString(), updated_at: new Date().toISOString(), document,
    }, document);
    setReady(true);
  }, []);
  return ready ? <TacticsWorkspace /> : null;
}
