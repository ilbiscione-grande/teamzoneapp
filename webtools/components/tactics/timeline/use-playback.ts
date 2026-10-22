"use client";

// Drives the playhead while the board plays: once per screen frame, from
// the time played since it started. At the end it stops on the last frame,
// unless it loops.
import { useEffect } from "react";
import { playheadAt } from "../../../lib/tactics/timeline.ts";
import { activeBoard, useEditor } from "../store.ts";

export function usePlayback() {
  const playing = useEditor(state => state.playing);
  useEffect(() => {
    if (!playing) return;
    const { playhead: from } = useEditor.getState();
    const started = performance.now();
    let request = 0;
    const step = (now: number) => {
      const state = useEditor.getState();
      const board = activeBoard(state);
      if (!state.playing || !board) return;
      const playhead = playheadAt(board.frames, now - started, state.speed, state.loop, from);
      if (playhead === null) {
        const last = board.frames.length - 1;
        useEditor.setState({ playing: false, playhead: last, frameIndex: last });
        return;
      }
      state.setPlayhead(playhead);
      request = requestAnimationFrame(step);
    };
    request = requestAnimationFrame(step);
    return () => cancelAnimationFrame(request);
  }, [playing]);
}
