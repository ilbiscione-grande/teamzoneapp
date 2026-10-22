"use client";

// Drawings over a live lesson's board, in metres on the pitch: the shared
// strokes and a participant's own notes for the board in hand, and, while
// the pen is out, a layer that turns a finger or the mouse into a stroke.
// A finished stroke is kept here (own notes) or sent (the shared layer).
import type { SupabaseClient } from "@supabase/supabase-js";
import type Konva from "konva";
import { useRef } from "react";
import { Group, Line, Rect } from "react-konva";
import { colorFor, drawError, thinStroke, type Stroke } from "../../../lib/tactics/live-draw.ts";
import { useEditor } from "../store.ts";
import { useDraw } from "./draw-store.ts";

const LINE = { strokeWidth: 0.4, lineCap: "round" as const, lineJoin: "round" as const, tension: 0.35, listening: false, perfectDrawEnabled: false };

export function LiveStrokes({ pen }: { pen?: { client: SupabaseClient; sessionId: string; selfId: string } }) {
  const boardId = useEditor(state => state.boardId);
  const strokes = useDraw(state => state.strokes);
  const own = useDraw(state => state.own);
  const drawing = useDraw(state => state.pen);
  const shown = [...strokes, ...own].filter(stroke => stroke.board_id === boardId);
  return (
    <Group>
      {shown.map(stroke => <Line key={stroke.id} points={stroke.points} stroke={stroke.color} {...LINE} />)}
      {pen && drawing && boardId && <Capture boardId={boardId} {...pen} />}
    </Group>
  );
}

function Capture({ client, sessionId, selfId, boardId }: { client: SupabaseClient; sessionId: string; selfId: string; boardId: string }) {
  const line = useRef<Konva.Line>(null);
  const points = useRef<number[]>([]);
  const pointer = useRef<number | null>(null);
  const color = colorFor(selfId);
  const at = (event: Konva.KonvaEventObject<PointerEvent>) => event.target.getParent()?.getRelativePointerPosition() ?? null;

  const finish = async () => {
    const drawn = thinStroke(points.current);
    points.current = [];
    pointer.current = null;
    line.current?.points([]);
    line.current?.getLayer()?.batchDraw();
    if (drawn.length < 4) return;
    const { drawMode } = useDraw.getState();
    if (drawMode === "own") {
      const stroke: Stroke = { id: `own-${Date.now()}`, board_id: boardId, profile_id: selfId, name: "", color, points: drawn, created_at: new Date().toISOString() };
      useDraw.getState().set({ own: [...useDraw.getState().own, stroke] });
      return;
    }
    const { data, error } = await client.schema("api").rpc("add_tactics_live_stroke", { target_session_id: sessionId, target_board_id: boardId, stroke_color: color, stroke_points: drawn });
    if (error) { useDraw.getState().set({ error: drawError(error.message) }); return; }
    useDraw.getState().set({ error: "" });
    useDraw.getState().addStrokes([data as Stroke]);
  };

  return (
    <>
      <Line ref={line} points={[]} stroke={color} {...LINE} />
      {/* Catches the pen over the whole pitch; nearly clear, as Konva needs a fill to hit. */}
      <Rect x={-200} y={-200} width={505} height={468} fill="rgba(0,0,0,0.001)"
        onPointerDown={event => {
          if (pointer.current !== null) { points.current = []; pointer.current = null; return; } // a second finger: a pinch, not a stroke
          const point = at(event);
          if (!point) return;
          event.cancelBubble = true;
          pointer.current = event.evt.pointerId;
          points.current = [point.x, point.y];
        }}
        onPointerMove={event => {
          if (pointer.current !== event.evt.pointerId) return;
          const point = at(event);
          if (!point) return;
          points.current.push(point.x, point.y);
          line.current?.points(points.current);
          line.current?.getLayer()?.batchDraw();
        }}
        onPointerUp={event => { if (pointer.current === event.evt.pointerId) void finish(); }}
        onPointerLeave={() => { if (pointer.current !== null) void finish(); }} />
    </>
  );
}
