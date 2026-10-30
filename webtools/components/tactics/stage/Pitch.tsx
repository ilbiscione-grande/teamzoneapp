"use client";

// A football pitch in metres: the surface in the board's theme with a
// pattern mown into it (pitch-style.ts), what stands round it, the lines by
// the laws of the game, the project's logo, and an optional grid for
// corridors, thirds or zones.
import { Arc, Circle, Group, Line, Rect, Ring } from "react-konva";
import { PITCH_LENGTH as L, PITCH_WIDTH as W, type Branding, type PitchOverlay, type PitchStyle, type PitchView, type Surroundings as Kind } from "../../../lib/tactics/model.ts";
import { patternPieces, styleOf, themes, type ThemeLook } from "../../../lib/tactics/pitch-style.ts";
import { PitchLogo } from "./PitchLogo.tsx";
import { Surroundings } from "./Surroundings.tsx";

const STROKE = 0.14;

// Penalty and goal areas, measured from the goal line.
const BOX_DEPTH = 16.5;
const BOX_WIDTH = 40.32;
const SIX_DEPTH = 5.5;
const SIX_WIDTH = 18.32;
const GOAL_WIDTH = 7.32;
const SPOT = 11;
const CIRCLE = 9.15;

function Ends({ line }: { line: string }) {
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
            <Rect x={left ? 0 : L - BOX_DEPTH} y={top} width={BOX_DEPTH} height={BOX_WIDTH} stroke={line} strokeWidth={STROKE} />
            <Rect x={left ? 0 : L - SIX_DEPTH} y={sixTop} width={SIX_DEPTH} height={SIX_WIDTH} stroke={line} strokeWidth={STROKE} />
            <Rect x={left ? -2 : L} y={goalTop} width={2} height={GOAL_WIDTH} stroke={line} strokeWidth={STROKE} fill="rgba(255,255,255,0.12)" />
            {/* The net: a mesh across the goal behind the line. */}
            {[0.5, 1, 1.5].map(dx => (
              <Line key={`d${dx}`} points={[left ? -dx : L + dx, goalTop, left ? -dx : L + dx, goalTop + GOAL_WIDTH]} stroke={line} strokeWidth={0.04} opacity={0.6} />
            ))}
            {Array.from({ length: 7 }, (_, i) => goalTop + (GOAL_WIDTH * (i + 1)) / 8).map(y => (
              <Line key={`n${y}`} points={[left ? -2 : L, y, left ? 0 : L + 2, y]} stroke={line} strokeWidth={0.04} opacity={0.6} />
            ))}
            <Circle x={x + inward * SPOT} y={W / 2} radius={0.22} fill={line} />
            <Arc x={x + inward * SPOT} y={W / 2} innerRadius={CIRCLE} outerRadius={CIRCLE} angle={arcAngle * 2}
              rotation={left ? -arcAngle : 180 - arcAngle} stroke={line} strokeWidth={STROKE} />
            {[0, W].map(y => (
              <Arc key={y} x={x} y={y} innerRadius={1} outerRadius={1} angle={90} stroke={line} strokeWidth={STROKE}
                rotation={left ? (y === 0 ? 0 : 270) : (y === 0 ? 90 : 180)} />
            ))}
          </Group>
        );
      })}
    </>
  );
}

function Grid({ overlay, color }: { overlay: PitchOverlay; color: string }) {
  const dash = [0.8, 0.8];
  const across = (x: number) => <Line key={`x${x}`} points={[x, 0, x, W]} stroke={color} strokeWidth={0.12} dash={dash} />;
  const along = (y: number) => <Line key={`y${y}`} points={[0, y, L, y]} stroke={color} strokeWidth={0.12} dash={dash} />;
  if (overlay === "thirds") return <>{[L / 3, (2 * L) / 3].map(across)}</>;
  // Wings, half-spaces and the centre: by the edges of the penalty and goal areas.
  const corridors = [(W - BOX_WIDTH) / 2, (W - SIX_WIDTH) / 2, (W + SIX_WIDTH) / 2, (W + BOX_WIDTH) / 2];
  if (overlay === "corridors") return <>{corridors.map(along)}</>;
  if (overlay === "zones") return <>{[1, 2, 3, 4, 5].map(i => across((L * i) / 6))}{[W / 3, (2 * W) / 3].map(along)}</>;
  return null;
}

/** The pattern's lighter pieces, kept inside the pitch. */
function Pattern({ style, look }: { style: PitchStyle; look: ThemeLook }) {
  const pieces = patternPieces(style.pattern, L, W);
  if (pieces.length === 0) return null;
  return (
    <Group clipX={0} clipY={0} clipWidth={L} clipHeight={W} listening={false}>
      {pieces.map((piece, i) => {
        if (piece.kind === "rect") return <Rect key={i} {...piece} fill={look.pattern} listening={false} perfectDrawEnabled={false} />;
        if (piece.kind === "band") return <Line key={i} points={piece.points} closed fill={look.pattern} listening={false} perfectDrawEnabled={false} />;
        return <Ring key={i} x={L / 2} y={W / 2} innerRadius={piece.inner} outerRadius={piece.outer} fill={look.pattern} listening={false} perfectDrawEnabled={false} />;
      })}
    </Group>
  );
}

/** Tilted, how far the ground reaches past the lines: to the foot of the stands, so the sky shows beyond. */
export const tiltedReach = (surroundings: Kind | undefined) => (surroundings === "arena" ? 5 : 8);

/** tilted: 3D, where the surroundings stand up on a stage of their own and the ground ends at the stands. */
export function Pitch({ view, overlay, style, surroundings, branding, upright = 0, tilted = false }: {
  view: PitchView; overlay: PitchOverlay; style?: Partial<PitchStyle>; surroundings?: Kind; branding?: Branding; upright?: number; tilted?: boolean;
}) {
  const whole = styleOf(style);
  const look = themes[whole.theme];
  // Far beyond the frame whatever the zoom, so a press anywhere off the pitch still pans.
  const reach = tilted ? tiltedReach(surroundings) : 200;
  const ground = { x: -reach, y: -reach, width: L + reach * 2, height: W + reach * 2 };
  return (
    <Group>
      {/* The surface catches taps and drags on the empty pitch. */}
      <Rect name="grass" {...ground} fill={look.ground} />
      {!tilted && <Surroundings kind={surroundings} />}
      <Pattern style={whole} look={look} />
      <PitchLogo branding={branding} upright={upright} />
      {view !== "empty" && (
        <Group listening={false}>
          <Rect x={0} y={0} width={L} height={W} stroke={look.line} strokeWidth={STROKE} />
          <Line points={[L / 2, 0, L / 2, W]} stroke={look.line} strokeWidth={STROKE} />
          <Circle x={L / 2} y={W / 2} radius={CIRCLE} stroke={look.line} strokeWidth={STROKE} />
          <Circle x={L / 2} y={W / 2} radius={0.25} fill={look.line} />
          <Ends line={look.line} />
        </Group>
      )}
      {overlay !== "none" && <Group listening={false}><Grid overlay={overlay} color={look.grid} /></Group>}
    </Group>
  );
}
