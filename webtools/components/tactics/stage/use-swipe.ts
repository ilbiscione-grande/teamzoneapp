"use client";

// A swipe across the board or a tap on it, for watching on a phone: a
// quick move sideways steps a frame, a tap plays or pauses. A second finger
// (a pinch) is no swipe; a zoomed-in board is left to pan.
import { useRef } from "react";

const SWIPE = 50, TAP = 10, TAP_MS = 350;

export function useSwipe(enabled: boolean, onSwipe?: (direction: 1 | -1) => void, onTap?: () => void) {
  const start = useRef<{ x: number; y: number; at: number } | null>(null);
  return {
    down: (event: React.PointerEvent) => {
      start.current = enabled && event.isPrimary ? { x: event.clientX, y: event.clientY, at: performance.now() } : null;
    },
    up: (event: React.PointerEvent) => {
      const from = start.current;
      start.current = null;
      if (!from || !enabled || !event.isPrimary) return;
      const dx = event.clientX - from.x, dy = event.clientY - from.y;
      if (Math.abs(dx) > SWIPE && Math.abs(dx) > Math.abs(dy) * 1.5) onSwipe?.(dx < 0 ? 1 : -1);
      else if (Math.hypot(dx, dy) < TAP && performance.now() - from.at < TAP_MS) onTap?.();
    },
    cancel: () => { start.current = null; },
  };
}
