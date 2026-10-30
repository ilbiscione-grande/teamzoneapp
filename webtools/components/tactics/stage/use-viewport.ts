"use client";

// The board's zoom and pan: pinching with two fingers, the mouse wheel and
// the buttons. While fingers move, the Konva groups are moved directly and
// React hears of it only when they lift, so the board never waits for it.
import type Konva from "konva";
import { useEffect, useRef, useState } from "react";
import { distance, midpoint, zoomAround, type Viewport } from "../../../lib/tactics/geometry.ts";
import type { Point } from "../../../lib/tactics/model.ts";

export const IDENTITY: Viewport = { x: 0, y: 0, scale: 1 };

/**
 * frame: the element fingers touch. reset: what starts the view over (a
 * new board, view or size). onPinch: a pinch began, stop other gestures.
 * everyStep: React hears of every step, for what is drawn from the state (3D).
 */
export function useViewport(frame: React.RefObject<HTMLDivElement | null>, ready: boolean, reset: unknown[], onPinch: () => void, everyStep = false) {
  // The same zoom and pan on both layers: the pitch's group is dragged, the objects' group follows.
  const pitchView = useRef<Konva.Group>(null);
  const objectView = useRef<Konva.Group>(null);
  const [viewport, setViewport] = useState<Viewport>(IDENTITY);
  const live = useRef<Viewport>(IDENTITY);
  const pinch = useRef<{ distance: number; center: Point } | null>(null);
  const onPinchRef = useRef(onPinch);
  onPinchRef.current = onPinch;
  const everyStepRef = useRef(everyStep);
  everyStepRef.current = everyStep;

  useEffect(() => {
    live.current = IDENTITY;
    setViewport(IDENTITY);
  }, reset); // eslint-disable-line react-hooks/exhaustive-deps

  const apply = (next: Viewport, commit: boolean) => {
    live.current = next;
    for (const group of [pitchView.current, objectView.current]) {
      group?.setAttrs({ x: next.x, y: next.y, scaleX: next.scale, scaleY: next.scale });
      group?.getLayer()?.batchDraw();
    }
    if (commit || everyStepRef.current) setViewport(next);
  };
  const applyRef = useRef(apply);
  applyRef.current = apply;

  // Two fingers zoom and move the board, whatever was being dragged.
  useEffect(() => {
    const element = frame.current;
    if (!element || !ready) return;
    const points = (event: TouchEvent): [Point, Point] | null => {
      if (event.touches.length < 2) return null;
      const rect = element.getBoundingClientRect();
      const at = (touch: Touch) => ({ x: touch.clientX - rect.left, y: touch.clientY - rect.top });
      return [at(event.touches[0]), at(event.touches[1])];
    };
    const onMove = (event: TouchEvent) => {
      const pair = points(event);
      if (!pair) return;
      event.preventDefault();
      if (pitchView.current?.isDragging()) pitchView.current.stopDrag();
      onPinchRef.current();
      const gap = distance(pair[0], pair[1]);
      const center = midpoint(pair[0], pair[1]);
      if (pinch.current) {
        const zoomed = zoomAround(live.current, gap / pinch.current.distance, center);
        applyRef.current({ ...zoomed, x: zoomed.x + center.x - pinch.current.center.x, y: zoomed.y + center.y - pinch.current.center.y }, false);
      }
      pinch.current = { distance: gap, center };
    };
    const onEnd = (event: TouchEvent) => {
      if (!pinch.current || event.touches.length >= 2) return;
      pinch.current = null;
      setViewport(live.current);
    };
    element.addEventListener("touchmove", onMove, { passive: false });
    element.addEventListener("touchend", onEnd);
    element.addEventListener("touchcancel", onEnd);
    return () => {
      element.removeEventListener("touchmove", onMove);
      element.removeEventListener("touchend", onEnd);
      element.removeEventListener("touchcancel", onEnd);
    };
  }, [frame, ready]);

  return {
    viewport, live, pinch, pitchView, objectView,
    apply,
    zoomBy: (factor: number, center: Point) => apply(zoomAround(live.current, factor, center), true),
    /** The pitch group dragged while zoomed in: the objects follow. */
    panMove: (at: Point) => {
      live.current = { ...live.current, ...at };
      objectView.current?.position(at);
      if (everyStepRef.current) setViewport(live.current);
    },
    panEnd: () => setViewport(live.current),
  };
}
