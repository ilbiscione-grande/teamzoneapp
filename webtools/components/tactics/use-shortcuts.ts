"use client";

// Keyboard: undo, redo, remove the selection, nudge it with the arrows,
// Escape back to selecting. Typing in a field is left alone.
import { useEffect } from "react";
import { activeObjects, useEditor } from "./store.ts";

export function useShortcuts() {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.tagName === "SELECT" || target.isContentEditable)) return;
      const state = useEditor.getState();
      const command = event.ctrlKey || event.metaKey;
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
      } else if (event.key.startsWith("Arrow") && state.selection.length) {
        event.preventDefault();
        const step = event.shiftKey ? 2 : 0.5;
        const dx = event.key === "ArrowLeft" ? -step : event.key === "ArrowRight" ? step : 0;
        const dy = event.key === "ArrowUp" ? -step : event.key === "ArrowDown" ? step : 0;
        const moved = activeObjects(state).filter(item => state.selection.includes(item.id) && !item.locked);
        state.patch(Object.fromEntries(moved.map(item => [item.id, { x: item.x + dx, y: item.y + dy }])));
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
}
