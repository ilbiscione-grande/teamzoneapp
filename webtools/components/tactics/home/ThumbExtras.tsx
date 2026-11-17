// What a board's small picture leaves out, drawn simply for a picture that
// should show all of a frame: lines and runs, freehand lines, areas, cones
// and other equipment, chains through players. Used where the host follows a
// live lesson's group, which places and draws these itself. In metres,
// placed as the picture places the pitch (`at`).
import type { TacticsObject } from "../../../lib/tactics/model.ts";

type At = (points: number[]) => number[];

export function ThumbExtras({ objects, at, metre }: { objects: TacticsObject[]; at: At; metre: number }) {
  const byId = new Map(objects.map(item => [item.id, item]));
  const line = (points: number[]) => at(points).join(" ");
  return (
    <g fill="none" strokeLinecap="round" strokeLinejoin="round">
      {objects.map(item => {
        if (item.hidden) return null;
        switch (item.type) {
          case "line": {
            const [x1, y1, x2, y2] = item.points;
            return <polyline key={item.id} points={line([item.x + x1, item.y + y1, item.x + x2, item.y + y2])} stroke={item.color} strokeWidth={0.5} strokeDasharray={item.dashed ? "1.5 1" : undefined} />;
          }
          case "freehand":
            return <polyline key={item.id} points={line(item.points.map((value, index) => value + (index % 2 === 0 ? item.x : item.y)))} stroke={item.color} strokeWidth={0.5} />;
          case "rect":
          case "ellipse": {
            const [x, y] = at([item.x - item.width / 2, item.y - item.height / 2]);
            const width = item.width * metre, height = item.height * metre;
            const look = { stroke: item.color, strokeWidth: 0.4, fill: item.color, fillOpacity: Math.min(0.5, item.fill), strokeDasharray: item.dashed ? "1.5 1" : undefined };
            return item.type === "rect"
              ? <rect key={item.id} x={x} y={y} width={width} height={height} {...look} />
              : <ellipse key={item.id} cx={x + width / 2} cy={y + height / 2} rx={width / 2} ry={height / 2} {...look} />;
          }
          case "chain": {
            const points = item.players.map(id => byId.get(id)).filter(Boolean).flatMap(player => [player!.x, player!.y]);
            if (points.length < 4) return null;
            if (item.closed) points.push(points[0], points[1]);
            return <polyline key={item.id} points={line(points)} stroke={item.color} strokeWidth={0.4} strokeDasharray={item.dashed ? "1.5 1" : undefined} />;
          }
          case "cone": {
            const [x, y] = at([item.x, item.y]);
            return <polygon key={item.id} points={`${x},${y - 1.4} ${x - 1.2},${y + 0.9} ${x + 1.2},${y + 0.9}`} fill={item.color} stroke="#ffffff" strokeWidth={0.2} />;
          }
          case "pole":
          case "mannequin":
          case "goal": {
            const [x, y] = at([item.x, item.y]);
            return <rect key={item.id} x={x - 0.7} y={y - 0.7} width={1.4} height={1.4} fill={item.color} stroke="#ffffff" strokeWidth={0.2} />;
          }
          default:
            return null;
        }
      })}
    </g>
  );
}
