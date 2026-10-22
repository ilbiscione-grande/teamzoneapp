"use client";

// The host's pointer on a participant's board: a red dot with a glow, in
// metres on the pitch, moving with the host's pointer.
import { Circle, Group } from "react-konva";
import { useLive } from "./live-store.ts";

export function Laser() {
  const pointer = useLive(state => state.pointer);
  if (!pointer) return null;
  return (
    <Group x={pointer.x} y={pointer.y} listening={false}>
      <Circle radius={2.2} fill="rgba(239,68,68,0.25)" perfectDrawEnabled={false} />
      <Circle radius={0.8} fill="#ef4444" stroke="#ffffff" strokeWidth={0.2} perfectDrawEnabled={false} />
    </Group>
  );
}
