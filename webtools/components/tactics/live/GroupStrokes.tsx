"use client";

// Drawing on a group's copy, for a participant: the strokes of the copy on
// the board (one's own group's, or the group shown to everyone), and, while
// the pen is out on one's own group's copy, a stroke sent to the group.
import type { SupabaseClient } from "@supabase/supabase-js";
import { Group, Line } from "react-konva";
import { colorFor, mergeStrokes, type Stroke } from "../../../lib/tactics/live-draw.ts";
import { groupError } from "../../../lib/tactics/live-groups.ts";
import { useDraw } from "./draw-store.ts";
import { displayedGroup, useGroup, worksOnOwn } from "./group-store.ts";
import { LINE, StrokeCapture } from "./LiveStrokes.tsx";

const NONE: Stroke[] = [];

export function GroupStrokes({ client, sessionId, selfId }: { client: SupabaseClient; sessionId: string; selfId: string | null }) {
  const strokes = useGroup(store => displayedGroup(store)?.strokes ?? NONE);
  const own = useGroup(worksOnOwn);
  const drawing = useDraw(store => store.pen);
  const onStroke = async (points: number[]) => {
    const { data, error } = await client.schema("api").rpc("add_tactics_live_group_stroke", {
      target_session_id: sessionId, stroke_color: colorFor(selfId ?? ""), stroke_points: points,
    });
    if (error) { useDraw.getState().set({ error: groupError(error.message) }); return; }
    useDraw.getState().set({ error: "" });
    const { group } = useGroup.getState();
    if (group) useGroup.getState().set({ group: { ...group, strokes: mergeStrokes(group.strokes, [data as Stroke]) } });
  };
  return (
    <Group>
      {strokes.map(stroke => <Line key={stroke.id} points={stroke.points} stroke={stroke.color} {...LINE} />)}
      {own && drawing && selfId && <StrokeCapture color={colorFor(selfId)} onStroke={onStroke} />}
    </Group>
  );
}
