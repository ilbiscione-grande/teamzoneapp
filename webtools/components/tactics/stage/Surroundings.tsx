"use client";

// What is drawn round the pitch, in metres from its lines. An arena:
// advertising boards along the run-off, two dugouts at the halfway line and
// stands of spectators all round. A training ground: a fence with a bench
// and a few cones. The crowd is a small picture of dots repeated over the
// stands, so the pitch layer stays quick to draw.
import { useMemo } from "react";
import { Group, Rect, Text } from "react-konva";
import { PITCH_LENGTH as L, PITCH_WIDTH as W, type Surroundings as Kind } from "../../../lib/tactics/model.ts";

/** Where the boards and the stands start, beyond the lines. */
const BOARDS = 3.4;
const STANDS = 5;
const DEPTH = 7;

/** A tile of spectators: dots in many colours on a dark terrace, the same each time. */
function crowdTile(): HTMLCanvasElement | null {
  if (typeof document === "undefined") return null;
  const canvas = document.createElement("canvas");
  canvas.width = 96;
  canvas.height = 96;
  const context = canvas.getContext("2d");
  if (!context) return null;
  context.fillStyle = "#1c2430";
  context.fillRect(0, 0, 96, 96);
  const colours = ["#e5e7eb", "#ef4444", "#3b82f6", "#facc15", "#22c55e", "#f97316", "#a855f7", "#94a3b8", "#0f172a"];
  let seed = 7;
  const next = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  for (let y = 4; y < 96; y += 8) {
    for (let x = 4; x < 96; x += 8) {
      context.fillStyle = colours[Math.floor(next() * colours.length)];
      context.beginPath();
      context.arc(x + (next() - 0.5) * 3, y + (next() - 0.5) * 2, 2.6, 0, Math.PI * 2);
      context.fill();
    }
  }
  return canvas;
}

/** Boards of alternating colours, ten metres each, along one side. */
function boardRow(x: number, y: number, length: number, along: "x" | "y") {
  const pieces = Math.ceil(length / 10);
  return Array.from({ length: pieces }, (_, i) => {
    const size = Math.min(10, length - i * 10);
    const dark = i % 2 === 0;
    const at = along === "x" ? { x: x + i * 10, y, width: size, height: 0.9 } : { x, y: y + i * 10, width: 0.9, height: size };
    return (
      <Group key={`${along}${x},${y},${i}`}>
        <Rect {...at} fill={dark ? "#0b3a6f" : "#f8fafc"} listening={false} perfectDrawEnabled={false} />
        {along === "x" && size > 6 && (
          <Text x={at.x} y={at.y + 0.08} width={size} text="TEAMZONE" align="center" fontSize={0.7} fontStyle="bold"
            fill={dark ? "#f8fafc" : "#0b3a6f"} listening={false} perfectDrawEnabled={false} />
        )}
      </Group>
    );
  });
}

function Arena() {
  const tile = useMemo(crowdTile, []);
  // The crowd tile's 96 px cover 6 m of terrace.
  const pattern = tile ? { fillPatternImage: tile as unknown as HTMLImageElement, fillPatternScale: { x: 6 / 96, y: 6 / 96 } } : { fill: "#1c2430" };
  const stand = (x: number, y: number, width: number, height: number, key: string) => (
    <Rect key={key} x={x} y={y} width={width} height={height} {...pattern} listening={false} perfectDrawEnabled={false} />
  );
  return (
    <Group listening={false}>
      {stand(-STANDS - DEPTH, -STANDS - DEPTH, L + 2 * (STANDS + DEPTH), DEPTH, "top")}
      {stand(-STANDS - DEPTH, W + STANDS, L + 2 * (STANDS + DEPTH), DEPTH, "bottom")}
      {stand(-STANDS - DEPTH, -STANDS, DEPTH, W + 2 * STANDS, "left")}
      {stand(L + STANDS, -STANDS, DEPTH, W + 2 * STANDS, "right")}
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
