"use client";

// 3D: what stands up on the tilted pitch, drawn upright on a stage of its
// own over the ground (lib/tactics/projection.ts). Players as figures with
// the shirt number on the chest and a shadow at their feet, the ball in the
// air on a lofted pass with its shadow below, cones, poles, mannequins and
// goals, and text. The far ones are drawn first, so the near ones stand in
// front. The spotlight darkens the ground and the figures it leaves out.
import { Circle, Ellipse, Group, Layer, Line, Rect, Stage, Text } from "react-konva";
import { PLAYER_RADIUS } from "../../../lib/tactics/ball.ts";
import type { Spotlight } from "../../../lib/tactics/marks.ts";
import type { Board, Point } from "../../../lib/tactics/model.ts";
import { TILT, type Projector } from "../../../lib/tactics/projection.ts";
import { standingFacing, type Rendered } from "../../../lib/tactics/timeline.ts";
import { Stands3D } from "./Stands3D.tsx";

/** What stands up in 3D; lines, freehand and areas lie on the ground. */
export const STANDING = new Set(["player", "ball", "cone", "pole", "mannequin", "goal", "text"]);

const foreshorten = Math.cos((TILT.degrees * Math.PI) / 180);
/**
 * Figures are drawn larger than life, as the flat board's discs are (a disc
 * is 3.2 m across): at true size a player is a few pixels on the whole pitch.
 */
export const FIGURE = 2.2;

function Figure({ item, board, project }: { item: Rendered; board: Board; project: Projector }) {
  const base = project(item);
  const unit = project.metre * TILT.scale * base.depth * (item.grow ?? 1) * FIGURE;
  const opacity = item.opacity ?? 1;
  const shadow = (radius: number) => (
    <Ellipse x={base.x} y={base.y} radiusX={radius * unit} radiusY={radius * unit * foreshorten} fill="rgba(0,0,0,0.32)" listening={false} />
  );
  switch (item.type) {
    case "player": {
      const team = board.teams[item.side];
      const fill = item.color ?? team.color;
      const height = 2.1 * unit, width = 1.25 * unit, head = 0.42 * unit;
      const lastName = item.name?.trim().split(/\s+/).slice(-1)[0] ?? null;
      return (
        <Group opacity={opacity} listening={false}>
          {shadow(PLAYER_RADIUS * 0.75)}
          {item.glow ? <Ellipse x={base.x} y={base.y} radiusX={PLAYER_RADIUS * 1.6 * unit} radiusY={PLAYER_RADIUS * 1.6 * unit * foreshorten} fill="#facc15" opacity={item.glow * 0.45} /> : null}
          <Rect x={base.x - width / 2} y={base.y - height + head} width={width} height={height - head} fill={fill} stroke="#ffffff" strokeWidth={Math.max(1, unit * 0.08)}
            cornerRadius={[width * 0.45, width * 0.45, width * 0.18, width * 0.18]} />
          <Circle x={base.x} y={base.y - height + head * 0.2} radius={head} fill={fill} stroke="#ffffff" strokeWidth={Math.max(1, unit * 0.07)} />
          {item.number !== null && (
            <Text x={base.x - width / 2} y={base.y - height * 0.62} width={width} align="center" text={String(item.number)}
              fontSize={Math.max(8, unit * 0.95)} fontStyle="bold" fill={team.numberColor} />
          )}
          {board.showNames && lastName && (
            <Text x={base.x - unit * 6} y={base.y + unit * 0.35} width={unit * 12} align="center" text={lastName} fontSize={Math.max(8, unit * 0.8)}
              fontStyle="bold" fill="#ffffff" stroke="rgba(11,17,28,0.9)" strokeWidth={Math.max(0.6, unit * 0.08)} fillAfterStrokeEnabled />
          )}
        </Group>
      );
    }
    case "ball": {
      const lift = item.lift ?? 0;
      const up = project(item, lift + 0.4 * FIGURE);
      return (
        <Group opacity={opacity} listening={false}>
          {shadow(0.45 * (1 - lift / 20))}
          <Circle x={up.x} y={up.y} radius={Math.max(2, 0.4 * FIGURE * project.metre * TILT.scale * up.depth)} fill="#ffffff" stroke="#111827" strokeWidth={1} />
        </Group>
      );
    }
    case "cone":
      return (
        <Group opacity={opacity} listening={false}>
          {shadow(0.35 * item.scale)}
          <Line points={[base.x - 0.32 * unit * item.scale, base.y, base.x + 0.32 * unit * item.scale, base.y, base.x, base.y - 0.75 * unit * item.scale]} closed fill={item.color} stroke="#7c2d12" strokeWidth={1} />
        </Group>
      );
    case "pole":
      return (
        <Group opacity={opacity} listening={false}>
          {shadow(0.25 * item.scale)}
          <Rect x={base.x - 0.08 * unit} y={base.y - 1.7 * unit * item.scale} width={0.16 * unit} height={1.7 * unit * item.scale} fill={item.color} stroke="#713f12" strokeWidth={0.5} />
        </Group>
      );
    case "mannequin":
      return (
        <Group opacity={opacity} listening={false}>
          {shadow(0.6 * item.scale)}
          <Rect x={base.x - 0.45 * unit * item.scale} y={base.y - 1.85 * unit * item.scale} width={0.9 * unit * item.scale} height={1.85 * unit * item.scale}
            fill={item.color} cornerRadius={0.4 * unit} />
        </Group>
      );
    case "goal": {
      // A small goal: two posts and a bar, across the way it is turned.
      const half = 1.5 * item.scale, angle = ((item.rotation + 90) * Math.PI) / 180;
      const ends: Point[] = [-1, 1].map(side => ({ x: item.x + Math.cos(angle) * half * side, y: item.y + Math.sin(angle) * half * side }));
      const [a, b] = ends.map(end => project(end));
      const [ta, tb] = ends.map(end => project(end, 1.2 * item.scale));
      return (
        <Group opacity={opacity} listening={false}>
          <Line points={[a.x, a.y, ta.x, ta.y, tb.x, tb.y, b.x, b.y]} stroke="#ffffff" strokeWidth={Math.max(1.5, unit * 0.1)} lineJoin="round" />
        </Group>
      );
    }
    case "text":
      return (
        <Group opacity={opacity} listening={false}>
          <Text x={base.x - unit * 10} y={base.y - item.size * unit} width={unit * 20} align="center" text={item.text} fontSize={Math.max(8, item.size * unit)}
            fontStyle="bold" fill={item.color} stroke={item.background ? "rgba(11,17,28,0.85)" : undefined} strokeWidth={item.background ? unit * 0.12 : 0} fillAfterStrokeEnabled />
        </Group>
      );
    default:
      return null;
  }
}

/** The way each player faces, as a cone on the ground before them. */
function Facings({ objects, board, project }: { objects: Rendered[]; board: Board; project: Projector }) {
  if (!board.showFacing) return null;
  return (
    <Group listening={false}>
      {objects.filter(item => item.type === "player").map(item => {
        if (item.type !== "player") return null;
        const facing = item.facing ?? standingFacing(item);
        const points = [project(item)];
        for (let step = -28; step <= 28; step += 7) {
          const angle = ((facing + step) * Math.PI) / 180;
          points.push(project({ x: item.x + Math.cos(angle) * PLAYER_RADIUS * 3.2, y: item.y + Math.sin(angle) * PLAYER_RADIUS * 3.2 }));
        }
        return <Line key={item.id} points={points.flatMap(p => [p.x, p.y])} closed fill={item.color ?? board.teams[item.side].color} opacity={0.32} />;
      })}
    </Group>
  );
}

/** The spotlight over the ground: dark all over but for lit ellipses round its objects. */
function Dark({ spotlight, project, width, height }: { spotlight: Spotlight; project: Projector; width: number; height: number }) {
  return (
    <Layer listening={false}>
      <Rect x={0} y={0} width={width} height={height} fill="#05080c" opacity={0.6 * spotlight.amount} />
      {spotlight.spots.map((spot, index) => {
        const at = project(spot);
        const radius = 7 * project.metre * TILT.scale * at.depth;
        return (
          <Ellipse key={index} x={at.x} y={at.y - radius * 0.3} radiusX={radius} radiusY={radius * 0.75} globalCompositeOperation="destination-out"
            fillRadialGradientStartPoint={{ x: 0, y: 0 }} fillRadialGradientStartRadius={0} fillRadialGradientEndPoint={{ x: 0, y: 0 }}
            fillRadialGradientEndRadius={radius} fillRadialGradientColorStops={[0, "rgba(0,0,0,1)", 0.65, "rgba(0,0,0,1)", 1, "rgba(0,0,0,0)"]} />
        );
      })}
    </Layer>
  );
}

export function Figures3D({ objects, board, project, spotlight, width, height }: {
  objects: Rendered[]; board: Board; project: Projector; spotlight: Spotlight | null; width: number; height: number;
}) {
  // Far first: by where their feet are on the screen.
  const standing = objects.filter(item => STANDING.has(item.type)).map(item => ({ item, y: project(item).y })).sort((a, b) => a.y - b.y);
  const lit = new Set(spotlight?.spots.map(spot => `${Math.round(spot.x * 10)},${Math.round(spot.y * 10)}`) ?? []);
  const isLit = (item: Rendered) => lit.has(`${Math.round(item.x * 10)},${Math.round(item.y * 10)}`);
  const dark = spotlight && spotlight.amount > 0 ? spotlight : null;
  return (
    <Stage width={width} height={height} listening={false} className="tb-figures">
      <Layer listening={false}>
        <Stands3D board={board} project={project} />
        <Facings objects={objects} board={board} project={project} />
        {standing.filter(({ item }) => !dark || !isLit(item)).map(({ item }) => <Figure key={item.id} item={item} board={board} project={project} />)}
        <Stands3D board={board} project={project} part="front" />
      </Layer>
      {dark && <Dark spotlight={dark} project={project} width={width} height={height} />}
      {dark && (
        <Layer listening={false}>
          {standing.filter(({ item }) => isLit(item)).map(({ item }) => <Figure key={item.id} item={item} board={board} project={project} />)}
        </Layer>
      )}
    </Stage>
  );
}
