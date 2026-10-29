"use client";

// What is drawn round the pitch, in metres from its lines. An arena: a
// darker run-off, advertising boards along it, two dugouts at the halfway
// line, stands of spectators in rows under roofs all round and floodlights
// in the corners. A training ground: a fence with a bench
// and a few cones. The crowd is a small picture of dots repeated over the
// stands, so the pitch layer stays quick to draw.
import { useMemo } from "react";
import { Circle, Group, Line, Rect, Text } from "react-konva";
import { PITCH_LENGTH as L, PITCH_WIDTH as W, type Surroundings as Kind } from "../../../lib/tactics/model.ts";
import { crowdTile } from "./crowd.ts";

/** Where the boards and the stands start, beyond the lines. */
const BOARDS = 3.4;
const STANDS = 5;
const DEPTH = 7;

const COLOURS = ["#0b3a6f", "#f8fafc", "#b91c1c", "#0f766e", "#f8fafc", "#facc15"];
const onLight = (colour: string) => colour === "#f8fafc" || colour === "#facc15";

/** Boards of changing colours, ten metres each, along one side. */
function boardRow(x: number, y: number, length: number, along: "x" | "y") {
  const pieces = Math.ceil(length / 10);
  return Array.from({ length: pieces }, (_, i) => {
    const size = Math.min(10, length - i * 10);
    const colour = COLOURS[i % COLOURS.length];
    const at = along === "x" ? { x: x + i * 10, y, width: size, height: 0.9 } : { x, y: y + i * 10, width: 0.9, height: size };
    return (
      <Group key={`${along}${x},${y},${i}`}>
        <Rect {...at} fill={colour} stroke="rgba(0,0,0,0.3)" strokeWidth={0.04} listening={false} perfectDrawEnabled={false} />
        {along === "x" && size > 6 && (
          <Text x={at.x} y={at.y + 0.08} width={size} text="TEAMZONE" align="center" fontSize={0.7} fontStyle="bold"
            fill={onLight(colour) ? "#0b3a6f" : "#f8fafc"} listening={false} perfectDrawEnabled={false} />
        )}
      </Group>
    );
  });
}

type Side = "top" | "bottom" | "left" | "right";

/**
 * A stand seen from above: the crowd in rows, stairways across it every
 * 14 m, darker towards the back and a roof over the back third.
 */
function Stand({ x, y, width, height, away, pattern }: { x: number; y: number; width: number; height: number; away: Side; pattern: object }) {
  const along = away === "top" || away === "bottom";
  const depth = along ? height : width, length = along ? width : height;
  // From the front (by the pitch) to the back.
  const at = (t: number) => (away === "top" ? y + height * (1 - t) : away === "bottom" ? y + height * t : away === "left" ? x + width * (1 - t) : x + width * t);
  const rows = Array.from({ length: Math.floor(depth) - 1 }, (_, i) => at((i + 1) / depth));
  const stairs = Array.from({ length: Math.max(0, Math.round(length / 14) - 1) }, (_, i) => (along ? x : y) + (length * (i + 1)) / Math.round(length / 14));
  const front = { x: along ? x : at(0), y: along ? at(0) : y }, back = { x: along ? x : at(1), y: along ? at(1) : y };
  const roof = 0.35;
  const roofFrom = at(1 - roof), roofTo = at(1);
  return (
    <Group listening={false}>
      <Rect x={x} y={y} width={width} height={height} {...pattern} listening={false} perfectDrawEnabled={false} />
      <Rect x={x} y={y} width={width} height={height} listening={false} perfectDrawEnabled={false}
        fillLinearGradientStartPoint={{ x: front.x - x, y: front.y - y }} fillLinearGradientEndPoint={{ x: back.x - x, y: back.y - y }}
        fillLinearGradientColorStops={[0, "rgba(0,0,0,0)", 1, "rgba(0,0,0,0.4)"]} />
      {rows.map(row => <Line key={`r${row}`} points={along ? [x, row, x + width, row] : [row, y, row, y + height]} stroke="rgba(15,23,42,0.55)" strokeWidth={0.12} listening={false} />)}
      {stairs.map(stair => <Line key={`s${stair}`} points={along ? [stair, y, stair, y + height] : [x, stair, x + width, stair]} stroke="#94a3b8" strokeWidth={0.6} opacity={0.7} listening={false} />)}
      <Rect x={along ? x : Math.min(roofFrom, roofTo)} y={along ? Math.min(roofFrom, roofTo) : y}
        width={along ? width : Math.abs(roofTo - roofFrom)} height={along ? Math.abs(roofTo - roofFrom) : height}
        fill="#1e293b" opacity={0.85} stroke="#475569" strokeWidth={0.15} listening={false} perfectDrawEnabled={false} />
    </Group>
  );
}

/** A floodlight in a corner: the lamps and the light they throw towards the pitch. */
function Floodlight({ x, y }: { x: number; y: number }) {
  return (
    <Group listening={false}>
      <Circle x={x} y={y} radius={26} listening={false} perfectDrawEnabled={false}
        fillRadialGradientStartPoint={{ x: 0, y: 0 }} fillRadialGradientStartRadius={0} fillRadialGradientEndPoint={{ x: 0, y: 0 }}
        fillRadialGradientEndRadius={26} fillRadialGradientColorStops={[0, "rgba(254,249,195,0.22)", 1, "rgba(254,249,195,0)"]} />
      <Rect x={x - 1.6} y={y - 1} width={3.2} height={2} fill="#f8fafc" stroke="#475569" strokeWidth={0.15} cornerRadius={0.3} listening={false} />
    </Group>
  );
}

function Arena() {
  const tile = useMemo(crowdTile, []);
  // The crowd tile's 96 px cover 6 m of terrace.
  const pattern = tile ? { fillPatternImage: tile as unknown as HTMLImageElement, fillPatternScale: { x: 6 / 96, y: 6 / 96 } } : { fill: "#1c2430" };
  const outer = STANDS + DEPTH;
  return (
    <Group listening={false}>
      {/* The run-off round the lines, a shade darker than the pitch. */}
      {[[-STANDS, -STANDS, L + 2 * STANDS, STANDS], [-STANDS, W, L + 2 * STANDS, STANDS], [-STANDS, 0, STANDS, W], [L, 0, STANDS, W]].map(([x, y, width, height]) => (
        <Rect key={`${x},${y}`} x={x} y={y} width={width} height={height} fill="rgba(0,0,0,0.12)" listening={false} perfectDrawEnabled={false} />
      ))}
      <Stand x={-outer} y={-outer} width={L + 2 * outer} height={DEPTH} away="top" pattern={pattern} />
      <Stand x={-outer} y={W + STANDS} width={L + 2 * outer} height={DEPTH} away="bottom" pattern={pattern} />
      <Stand x={-outer} y={-STANDS} width={DEPTH} height={W + 2 * STANDS} away="left" pattern={pattern} />
      <Stand x={L + STANDS} y={-STANDS} width={DEPTH} height={W + 2 * STANDS} away="right" pattern={pattern} />
      {/* A walkway between the boards and the stands. */}
      <Rect x={-STANDS} y={-STANDS} width={L + 2 * STANDS} height={W + 2 * STANDS} stroke="#3f4a57" strokeWidth={0.6} listening={false} />
      {boardRow(-BOARDS, -BOARDS - 0.9, L + 2 * BOARDS, "x")}
      {boardRow(-BOARDS, W + BOARDS, L + 2 * BOARDS, "x")}
      {boardRow(-BOARDS - 0.9, -BOARDS, W + 2 * BOARDS, "y")}
      {boardRow(L + BOARDS, -BOARDS, W + 2 * BOARDS, "y")}
      {/* Dugouts either side of halfway, by the near touchline. */}
      {[-11, 3].map(dx => (
        <Rect key={dx} x={L / 2 + dx} y={W + 1.3} width={8} height={1.7} fill="rgba(15,23,42,0.75)" stroke="#cbd5e1" strokeWidth={0.08}
          cornerRadius={0.4} listening={false} perfectDrawEnabled={false} />
      ))}
      {[[-outer + 1.5, -outer + 1.5], [L + outer - 1.5, -outer + 1.5], [-outer + 1.5, W + outer - 1.5], [L + outer - 1.5, W + outer - 1.5]].map(([x, y]) => (
        <Floodlight key={`${x},${y}`} x={x} y={y} />
      ))}
    </Group>
  );
}

function Training() {
  const fence = 6;
  return (
    <Group listening={false}>
      <Rect x={-fence} y={-fence} width={L + 2 * fence} height={W + 2 * fence} stroke="#cbd5e1" strokeWidth={0.18} dash={[0.5, 0.35]} opacity={0.8} listening={false} />
      <Rect x={L / 2 - 4} y={W + 2.4} width={8} height={1.1} fill="#6b4f2e" cornerRadius={0.3} listening={false} perfectDrawEnabled={false} />
      {[[-2.5, -2.5], [L + 2.5, -2.5], [-2.5, W + 2.5], [L + 2.5, W + 2.5]].map(([x, y]) => (
        <Rect key={`${x},${y}`} x={x - 0.4} y={y - 0.4} width={0.8} height={0.8} fill="#f97316" rotation={45} listening={false} perfectDrawEnabled={false} />
      ))}
    </Group>
  );
}

export function Surroundings({ kind }: { kind: Kind | undefined }) {
  if (kind === "arena") return <Arena />;
  if (kind === "training") return <Training />;
  return null;
}
