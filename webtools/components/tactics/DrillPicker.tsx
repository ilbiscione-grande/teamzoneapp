"use client";

// An empty board offers ready drills to start from, over the pitch: one
// tap lays the drill out to change as you like. Gone once something is on
// the board, or when you start empty.
import { useState } from "react";
import { drills } from "../../lib/tactics/drills.ts";
import { updateBoard } from "../../lib/tactics/document.ts";
import { PITCH_LENGTH, PITCH_WIDTH } from "../../lib/tactics/model.ts";
import { activeBoard, activeObjects, useEditor } from "./store.ts";

export function DrillPicker() {
  const board = useEditor(activeBoard);
  const objects = useEditor(activeObjects);
  const tool = useEditor(state => state.tool);
  const playing = useEditor(state => state.playing);
  // Boards started empty on purpose, in this visit.
  const [declined, setDeclined] = useState<string[]>([]);
  if (!board || objects.length > 0 || board.frames.length > 1 || tool !== "select" || playing || declined.includes(board.id)) return null;
  const choose = (key: string) => {
    const drill = drills.find(item => item.key === key);
    if (!drill) return;
    useEditor.getState().change(document => updateBoard(document, board.id, current => ({
      ...current, view: drill.view, frames: current.frames.map((frame, index) => (index === 0 ? { ...frame, objects: drill.objects() } : frame)),
    })));
    useEditor.getState().setFocus(drill.zoom ? { at: { x: PITCH_LENGTH / 2, y: PITCH_WIDTH / 2 }, scale: drill.zoom } : null);
  };
  return (
    <div className="tb-drills" role="dialog" aria-label="Börja från en övning">
      <div className="tb-drills-head">
        <strong>Börja från en färdig övning</strong>
        <button type="button" className="tb-link" onClick={() => setDeclined([...declined, board.id])}>Börja med tom tavla</button>
      </div>
      <div className="tb-drills-grid">
        {drills.map(drill => (
          <button key={drill.key} type="button" onClick={() => choose(drill.key)}>
            <span>{drill.name}</span>
            <small>{drill.about}</small>
          </button>
        ))}
      </div>
      <p className="tb-drills-note">Allt går att flytta, ändra och ta bort efteråt. Eller välj ett verktyg till vänster och rita själv.</p>
    </div>
  );
}
