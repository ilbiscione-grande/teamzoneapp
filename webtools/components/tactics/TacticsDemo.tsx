"use client";

// Development only: the workspace on a board in memory, with a few players,
// a ball and a cone, so the board can be tried without an account. With
// ?delad=1 it shows the board as a shared link does.
import { useSearchParams } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { applyFormation, createObject, insertFrame, newDocument, updateFrame } from "../../lib/tactics/document.ts";
import { formations } from "../../lib/tactics/formations.ts";
import type { ProjectDocument } from "../../lib/tactics/model.ts";
import { SharedViewer } from "./SharedViewer.tsx";
import { useChat } from "./live/chat-store.ts";
import { useDraw } from "./live/draw-store.ts";
import { useLive } from "./live/live-store.ts";
import { useEditor } from "./store.ts";
import { TacticsWorkspace } from "./TacticsEditor.tsx";

function demoDocument(): ProjectDocument {
  let document = newDocument("Uppställning");
  const board = document.boards[0];
  document = updateFrame(document, board.id, 0, objects => {
    const placed = applyFormation(applyFormation(objects, "home", formations["4-3-3"]), "away", formations["4-4-2"]);
    return [...placed, createObject("ball", { x: 52.5, y: 34 }), createObject("cone", { x: 30, y: 60 })];
  });
  return document;
}

export function TacticsDemo() {
  const shared = useSearchParams().get("delad") === "1";
  const [ready, setReady] = useState(false);
  const document = useMemo(() => {
    const base = demoDocument();
    if (!shared) return base;
    // Two frames, the striker running on, to play.
    const board = insertFrame(base.boards[0], 0);
    const nine = board.frames[1].objects.find(item => item.type === "player" && item.side === "home" && item.number === 9);
    const frames = board.frames.map((frame, index) => index === 1 && nine
      ? { ...frame, objects: frame.objects.map(item => item.id === nine.id ? { ...item, x: item.x + 18, y: item.y + 6 } : item) }
      : frame);
    return { ...base, boards: [{ ...board, frames }] };
  }, [shared]);
  useEffect(() => {
    if (shared) return;
    useEditor.getState().load({
      id: "demo", name: "Demo", kind: "match", teamzone_team_id: null, team_name: null, board_count: 1, revision: 1,
      created_at: new Date().toISOString(), updated_at: new Date().toISOString(), document,
    }, document);
    // For trying things from the console.
    Object.assign(window, { tacticsEditor: useEditor, tacticsLive: useLive, tacticsChat: useChat, tacticsDraw: useDraw });
    setReady(true);
  }, [document, shared]);
  if (shared) {
    return <SharedViewer shared={{ name: "Demo", kind: "match", updated_at: new Date().toISOString(), team_name: "P2012", board_id: null, boards: document.boards }} />;
  }
  return ready ? <TacticsWorkspace /> : null;
}
