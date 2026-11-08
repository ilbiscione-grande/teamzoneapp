"use client";

// The frames on a phone: side by side, the frame in hand in the middle and a
// part of the one before and after showing at the edges. A tap on one of those
// takes it; a swipe sideways steps one frame, however far it goes.
import { useRef, useState, type ReactNode } from "react";
import { useEditor } from "../store.ts";

/** How far a finger must go sideways to step, in pixels. */
const STEP = 40;

export function FrameCarousel({ count, current, card }: { count: number; current: number; card: (index: number) => ReactNode }) {
  const [drag, setDrag] = useState(0);
  const start = useRef<{ x: number; y: number; sideways: boolean | null } | null>(null);
  const moved = useRef(false);
  // The latest pull, read when the finger lifts (the state may not have drawn yet).
  const pulled = useRef(0);
  const pull = (value: number) => { pulled.current = value; setDrag(value); };
  const go = (index: number) => useEditor.getState().setFrame(Math.max(0, Math.min(count - 1, index)));

  return (
    <div className="tb-frame-carousel"
      onPointerDown={event => { start.current = { x: event.clientX, y: event.clientY, sideways: null }; moved.current = false; }}
      onPointerMove={event => {
        const from = start.current;
        if (!from) return;
        const dx = event.clientX - from.x, dy = event.clientY - from.y;
        // The way the finger first goes decides: sideways steps frames, up and down scrolls the panel.
        if (from.sideways === null && Math.hypot(dx, dy) > 6) from.sideways = Math.abs(dx) > Math.abs(dy);
        if (!from.sideways) return;
        moved.current = true;
        // Past the first or last frame it gives only a little.
        const edge = (dx > 0 && current === 0) || (dx < 0 && current === count - 1);
        pull(edge ? dx / 4 : dx);
      }}
      onPointerUp={() => {
        if (moved.current && Math.abs(pulled.current) > STEP) go(current + (pulled.current < 0 ? 1 : -1));
        start.current = null;
        pull(0);
      }}
      onPointerCancel={() => { start.current = null; pull(0); }}
      onClickCapture={event => { if (moved.current) { event.stopPropagation(); event.preventDefault(); moved.current = false; } }}>
      <ol className="tb-frame-track" data-dragging={drag !== 0}
        style={{ transform: `translateX(calc(16% - ${current} * (68% + 8px) + ${drag}px))` }}>
        {Array.from({ length: count }, (_, index) => (
          <li key={index} aria-current={index === current} data-before={index < current}>{card(index)}</li>
        ))}
      </ol>
    </div>
  );
}
