"use client";

// Keyboard: undo, redo, remove the selection, Escape back to selecting;
// space plays and pauses, the arrows left and right step between frames,
// Ctrl (⌘) with the arrows nudges the selection, and Page Up, Page Down,
// Home and End move it up and down in the drawing order. Typing in a field is
// left alone, and so is a key a control has already handled (the timeline).
// Off while presenting: the presenter has keys of its own.
import { useEffect } from "react";
import { stack, type Stacking } from "../../lib/tactics/document.ts";
import { activeBoard, activeObjects, stepFrame, useEditor } from "./store.ts";

/** Page Up and Down move the selection a step up or down in the drawing order, Home and End to the top or bottom. */
const STACKING: Record<string, Stacking> = { PageUp: "up", PageDown: "down", Home: "top", End: "bottom" };

export function useShortcuts(enabled = true) {
  useEffect(() => {
    if (!enabled) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.defaultPrevented) return;
      const target = event.target as HTMLElement | null;
      if (target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.tagName === "SELECT" || target.isContentEditable)) return;
      const state = useEditor.getState();
      const command = event.ctrlKey || event.metaKey;
      const frames = activeBoard(state)?.frames.length ?? 0;
      if (command && event.key.toLowerCase() === "z") {
        event.preventDefault();
        if (event.shiftKey) state.redo(); else state.undo();
      } else if (command && event.key.toLowerCase() === "y") {
        event.preventDefault();
        state.redo();
      } else if (event.key === "Delete" || event.key === "Backspace") {
        if (state.selection.length) { event.preventDefault(); state.removeSelected(); }
      } else if (event.key === "Escape") {
        state.setTool("select");
        state.select([]);
      } else if (event.key === " " && !command) {
        // Also keeps a focused button (the one just clicked) from being pressed again.
        event.preventDefault();
        if (state.playing) state.pause();
        else if (frames > 1) state.play();
      } else if (command && event.key.startsWith("Arrow") && state.selection.length) {
        event.preventDefault();
        const step = event.shiftKey ? 2 : 0.5;
        const dx = event.key === "ArrowLeft" ? -step : event.key === "ArrowRight" ? step : 0;
        const dy = event.key === "ArrowUp" ? -step : event.key === "ArrowDown" ? step : 0;
        const moved = activeObjects(state).filter(item => state.selection.includes(item.id) && !item.locked);
        state.patch(Object.fromEntries(moved.map(item => [item.id, { x: item.x + dx, y: item.y + dy }])));
      } else if (!command && Object.hasOwn(STACKING, event.key) && state.selection.length) {
        event.preventDefault();
        const selection = state.selection;
        state.changeObjects(objects => stack(objects, selection, STACKING[event.key]));
      } else if (!command && (event.key === "ArrowLeft" || event.key === "ArrowRight") && frames > 1) {
        event.preventDefault();
        stepFrame(event.key === "ArrowRight" ? 1 : -1);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [enabled]);
}
