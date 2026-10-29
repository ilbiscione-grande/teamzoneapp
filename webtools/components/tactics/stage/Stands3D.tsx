"use client";

// 3D: an arena round the tilted pitch (Surroundings "arena"), drawn upright
// with the figures. Behind the pitch ("back"): the far stand rising row on
// row under a roof, the stands at the ends, floodlight masts in the corners
// and advertising boards along the far side and the ends. In front of it
// ("front"): the boards along the near side and the near masts. The near
// stand is where the view is taken from, so it is not drawn.
import { useMemo } from "react";
import { Group, Line, Rect, Text } from "react-konva";
import { PITCH_LENGTH as L, PITCH_WIDTH as W, type Board, type Point } from "../../../lib/tactics/model.ts";
import { TILT, type Projector } from "../../../lib/tactics/projection.ts";
import { crowdTile } from "./crowd.ts";

/** Metres from the lines: the boards, the stands' foot and their back, and how high they rise. */
const BOARDS = 3.4, FOOT = 5, BACK = 16, LOW = 1.2, HIGH = 13;
const BOARD_HEIGHT = 0.9;

const flat = (points: { x: number; y: number }[]) => points.flatMap(point => [point.x, point.y]);

/** A stand as a slope from its foot to its back, `rows` lines across it. */
function Stand({ foot, back, project, pattern, rows = 6 }: { foot: [Point, Point]; back: [Point, Point]; project: Projector; pattern: object; rows?: number }) {
  const corners = [project(foot[0], LOW), project(foot[1], LOW), project(back[1], HIGH), project(back[0], HIGH)];
  const lerp = (a: Point, b: Point, t: number) => ({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t });
  const across = Array.from({ length: rows - 1 }, (_, i) => {
    const t = (i + 1) / rows, lift = LOW + (HIGH - LOW) * t;
    return [project(lerp(foot[0], back[0], t), lift), project(lerp(foot[1], back[1], t), lift)];
  });
  // Stairways up the stand every 14 m or so.
  const length = Math.hypot(foot[1].x - foot[0].x, foot[1].y - foot[0].y);
  const stairs = Math.max(1, Math.round(length / 14));
  const up = Array.from({ length: stairs - 1 }, (_, i) => {
    const t = (i + 1) / stairs;
    return [project(lerp(foot[0], foot[1], t), LOW), project(lerp(back[0], back[1], t), HIGH)];
  });
  return (
    <Group listening={false}>
      <Line points={flat(corners)} closed {...pattern} />
      {/* Darker towards the back, where the roof shades it. */}
      <Line points={flat(corners)} closed fillLinearGradientStartPoint={corners[0]} fillLinearGradientEndPoint={corners[3]}
        fillLinearGradientColorStops={[0, "rgba(0,0,0,0)", 1, "rgba(0,0,0,0.45)"]} />
      {across.map((row, i) => <Line key={`r${i}`} points={flat(row)} stroke="rgba(15,23,42,0.55)" strokeWidth={1} />)}
      {up.map((stair, i) => <Line key={`s${i}`} points={flat(stair)} stroke="#94a3b8" strokeWidth={2} opacity={0.6} />)}
      <Line points={flat([corners[0], corners[1]])} stroke="#334155" strokeWidth={2} />
    </Group>
  );
}

/** A roof over a stand's back: from its back edge, reaching over part of the stand. */
function Roof({ back, reach, project }: { back: [Point, Point]; reach: Point; project: Projector }) {
  const front = back.map(point => ({ x: point.x + reach.x, y: point.y + reach.y }));
  const corners = [project(back[0], HIGH + 3), project(back[1], HIGH + 3), project(front[1], HIGH + 2.4), project(front[0], HIGH + 2.4)];
  return <Line points={flat(corners)} closed fill="#1e293b" stroke="#475569" strokeWidth={1} opacity={0.95} listening={false} />;
}

/** Upright boards in alternating colours along one side, ten metres each. */
function Boards({ from, to, project, words }: { from: Point; to: Point; project: Projector; words: boolean }) {
  const length = Math.hypot(to.x - from.x, to.y - from.y);
  const pieces = Math.ceil(length / 10);
  const colours = ["#0b3a6f", "#f8fafc", "#b91c1c", "#0f766e", "#f8fafc", "#facc15"];
  return (
    <Group listening={false}>
      {Array.from({ length: pieces }, (_, i) => {
        const a = { x: from.x + ((to.x - from.x) * i) / pieces, y: from.y + ((to.y - from.y) * i) / pieces };
        const b = { x: from.x + ((to.x - from.x) * (i + 1)) / pieces, y: from.y + ((to.y - from.y) * (i + 1)) / pieces };
        const quad = [project(a), project(b), project(b, BOARD_HEIGHT), project(a, BOARD_HEIGHT)];
        const colour = colours[i % colours.length];
        const middle = project({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }, BOARD_HEIGHT / 2);
        const size = 0.55 * project.metre * TILT.scale * middle.depth;
        const width = Math.abs(quad[1].x - quad[0].x);
        return (
          <Group key={i}>
            <Line points={flat(quad)} closed fill={colour} stroke="rgba(0,0,0,0.35)" strokeWidth={0.5} />
            {words && width > size * 6 && (
              <Text x={middle.x - width / 2} y={middle.y - size / 2} width={width} align="center" text="TEAMZONE" fontSize={size} fontStyle="bold"
                fill={colour === "#f8fafc" || colour === "#facc15" ? "#0b3a6f" : "#f8fafc"} />
            )}
          </Group>
        );
      })}
    </Group>
  );
}

/** A floodlight mast: a pole to the lamps, lit. */
function Mast({ at, project }: { at: Point; project: Projector }) {
  const foot = project(at), top = project(at, 34);
  const size = 3 * project.metre * TILT.scale * top.depth;
  return (
    <Group listening={false}>
      <Line points={[foot.x, foot.y, top.x, top.y]} stroke="#94a3b8" strokeWidth={Math.max(1.5, size * 0.12)} />
      <Rect x={top.x - size} y={top.y - size * 0.7} width={size * 2} height={size * 0.9} fill="#f8fafc" stroke="#475569" strokeWidth={1}
        shadowColor="#fef9c3" shadowBlur={size * 2} shadowOpacity={0.9} cornerRadius={size * 0.15} />
    </Group>
  );
}

export function Stands3D({ board, project, part = "back" }: { board: Board; project: Projector; part?: "back" | "front" }) {
  const tile = useMemo(crowdTile, []);
  if (board.surroundings !== "arena") return null;
  // The crowd as a picture repeated over the stands, in screen pixels.
  const pattern = tile ? { fillPatternImage: tile as unknown as HTMLImageElement, fillPatternScale: { x: 0.5, y: 0.5 } } : { fill: "#1c2430" };
  if (part === "front") {
    return (
      <Group listening={false}>
        <Boards from={{ x: -BOARDS, y: W + BOARDS }} to={{ x: L + BOARDS, y: W + BOARDS }} project={project} words />
        <Mast at={{ x: -BACK, y: W + BACK }} project={project} />
        <Mast at={{ x: L + BACK, y: W + BACK }} project={project} />
      </Group>
    );
  }
  return (
    <Group listening={false}>
      <Mast at={{ x: -BACK, y: -BACK }} project={project} />
      <Mast at={{ x: L + BACK, y: -BACK }} project={project} />
      {/* The ends first, then the far stand over their corners. */}
      <Stand foot={[{ x: -FOOT, y: W + FOOT }, { x: -FOOT, y: -FOOT }]} back={[{ x: -BACK, y: W + FOOT }, { x: -BACK, y: -FOOT }]} project={project} pattern={pattern} />
      <Stand foot={[{ x: L + FOOT, y: -FOOT }, { x: L + FOOT, y: W + FOOT }]} back={[{ x: L + BACK, y: -FOOT }, { x: L + BACK, y: W + FOOT }]} project={project} pattern={pattern} />
      <Stand foot={[{ x: -FOOT, y: -FOOT }, { x: L + FOOT, y: -FOOT }]} back={[{ x: -BACK, y: -BACK }, { x: L + BACK, y: -BACK }]} project={project} pattern={pattern} rows={8} />
      <Roof back={[{ x: -BACK, y: -BACK }, { x: L + BACK, y: -BACK }]} reach={{ x: 0, y: 6 }} project={project} />
      <Boards from={{ x: -BOARDS, y: -BOARDS }} to={{ x: L + BOARDS, y: -BOARDS }} project={project} words />
      <Boards from={{ x: -BOARDS, y: W + BOARDS }} to={{ x: -BOARDS, y: -BOARDS }} project={project} words={false} />
      <Boards from={{ x: L + BOARDS, y: -BOARDS }} to={{ x: L + BOARDS, y: W + BOARDS }} project={project} words={false} />
    </Group>
  );
}
