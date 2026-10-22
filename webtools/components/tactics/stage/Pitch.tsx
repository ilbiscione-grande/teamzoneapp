"use client";

// A football pitch in metres: grass with mown stripes, the lines by the
// laws of the game, and an optional grid for corridors, thirds or zones.
import { Arc, Circle, Group, Line, Rect } from "react-konva";
import { MARGIN } from "../../../lib/tactics/geometry.ts";
import { PITCH_LENGTH as L, PITCH_WIDTH as W, type PitchOverlay, type PitchView } from "../../../lib/tactics/model.ts";

const LINE = "rgba(255,255,255,0.88)";
const STROKE = 0.14;
const GRID = "rgba(255,255,255,0.32)";

// Penalty and goal areas, measured from the goal line.
const BOX_DEPTH = 16.5;
const BOX_WIDTH = 40.32;
const SIX_DEPTH = 5.5;
const SIX_WIDTH = 18.32;
const GOAL_WIDTH = 7.32;
const SPOT = 11;
const CIRCLE = 9.15;

function Ends() {
  const top = (W - BOX_WIDTH) / 2;
  const sixTop = (W - SIX_WIDTH) / 2;
  const goalTop = (W - GOAL_WIDTH) / 2;
  // The arc outside the box: the part of the circle round the spot beyond 16.5 m.
  const arcAngle = (Math.acos((BOX_DEPTH - SPOT) / CIRCLE) * 180) / Math.PI;
  return (
    <>
      {[0, 1].map(end => {
        const left = end === 0;
        const x = left ? 0 : L;
        const inward = left ? 1 : -1;
        return (
          <Group key={end}>
            <Rect x={left ? 0 : L - BOX_DEPTH} y={top} width={BOX_DEPTH} height={BOX_WIDTH} stroke={LINE} strokeWidth={STROKE} />
            <Rect x={left ? 0 : L - SIX_DEPTH} y={sixTop} width={SIX_DEPTH} height={SIX_WIDTH} stroke={LINE} strokeWidth={STROKE} />
            <Rect x={left ? -2 : L} y={goalTop} width={2} height={GOAL_WIDTH} stroke={LINE} strokeWidth={STROKE} fill="rgba(255,255,255,0.12)" />
            <Circle x={x + inward * SPOT} y={W / 2} radius={0.22} fill={LINE} />
            <Arc x={x + inward * SPOT} y={W / 2} innerRadius={CIRCLE} outerRadius={CIRCLE} angle={arcAngle * 2}
              rotation={left ? -arcAngle : 180 - arcAngle} stroke={LINE} strokeWidth={STROKE} />
            {[0, W].map(y => (
              <Arc key={y} x={x} y={y} innerRadius={1} outerRadius={1} angle={90} stroke={LINE} strokeWidth={STROKE}
                rotation={left ? (y === 0 ? 0 : 270) : (y === 0 ? 90 : 180)} />
            ))}
          </Group>
        );
      })}
    </>
  );
}

function Grid({ overlay }: { overlay: PitchOverlay }) {
  const dash = [0.8, 0.8];
  const across = (x: number) => <Line key={`x${x}`} points={[x, 0, x, W]} stroke={GRID} strokeWidth={0.12} dash={dash} />;
  const along = (y: number) => <Line key={`y${y}`} points={[0, y, L, y]} stroke={GRID} strokeWidth={0.12} dash={dash} />;
  if (overlay === "thirds") return <>{[L / 3, (2 * L) / 3].map(across)}</>;
  // Wings, half-spaces and the centre: by the edges of the penalty and goal areas.
  const corridors = [(W - BOX_WIDTH) / 2, (W - SIX_WIDTH) / 2, (W + SIX_WIDTH) / 2, (W + BOX_WIDTH) / 2];
  if (overlay === "corridors") return <>{corridors.map(along)}</>;
  if (overlay === "zones") return <>{[1, 2, 3, 4, 5].map(i => across((L * i) / 6))}{[W / 3, (2 * W) / 3].map(along)}</>;
  return null;
}

export function Pitch({ view, overlay }: { view: PitchView; overlay: PitchOverlay }) {
  const stripes = 12;
  const grass = { x: -MARGIN * 3, y: -MARGIN * 3, width: L + MARGIN * 6, height: W + MARGIN * 6 };
  return (
    <Group>
      {/* The grass catches taps and drags on the empty pitch. */}
      <Rect name="grass" {...grass} fill="#2f7d46" />
      {Array.from({ length: stripes }, (_, i) => i % 2 === 0 ? null : (
        <Rect key={i} x={(L / stripes) * i} y={0} width={L / stripes} height={W} fill="rgba(255,255,255,0.045)" listening={false} />
      ))}
      {view !== "empty" && (
        <Group listening={false}>
          <Rect x={0} y={0} width={L} height={W} stroke={LINE} strokeWidth={STROKE} />
          <Line points={[L / 2, 0, L / 2, W]} stroke={LINE} strokeWidth={STROKE} />
          <Circle x={L / 2} y={W / 2} radius={CIRCLE} stroke={LINE} strokeWidth={STROKE} />
          <Circle x={L / 2} y={W / 2} radius={0.25} fill={LINE} />
          <Ends />
        </Group>
      )}
      {overlay !== "none" && <Group listening={false}><Grid overlay={overlay} /></Group>}
    </Group>
  );
}
