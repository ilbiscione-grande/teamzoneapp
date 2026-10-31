// A project's first board, small, on its card on the start page: the pitch
// in the board's view with the first frame's players and ball, drawn as the
// shared link's chat picture is (lib/tactics/preview.ts). A project without
// boards shows an empty pitch.
import { ballPattern, svgPoints } from "../../../lib/tactics/ball-look.ts";
import { teamColors } from "../../../lib/tactics/document.ts";
import type { Board } from "../../../lib/tactics/model.ts";
import { previewOf } from "../../../lib/tactics/preview.ts";

/** What a project's summary brings of its first board (20270109090000). */
export type BoardPreview = { view: Board["view"] | null; teams: Partial<Board["teams"]> | null; objects: Board["frames"][number]["objects"] };

const BALL = 1.6;
const ball = ballPattern(BALL);

export function ProjectThumb({ preview }: { preview: BoardPreview | null | undefined }) {
  const teams = { home: { ...teamColors.home, ...preview?.teams?.home }, away: { ...teamColors.away, ...preview?.teams?.away } };
  const board = { view: preview?.view ?? "full", teams, frames: [{ objects: preview?.objects ?? [] }] } as unknown as Board;
  const { lines, dots, aspect } = previewOf(board);
  const width = 100, height = width / aspect;
  return (
    <svg className="tb-thumb" viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="xMidYMid meet" aria-hidden="true">
      <defs><clipPath id="tb-thumb-ball"><circle r={BALL} /></clipPath></defs>
      <rect width={width} height={height} fill="#2f7d46" />
      <g fill="none" stroke="rgba(255,255,255,.8)" strokeWidth={0.5}>
        {lines.map((line, index) => line.round
          ? <ellipse key={index} cx={(line.left + line.width / 2) * width} cy={(line.top + line.height / 2) * height}
              rx={line.width / 2 * width} ry={line.height / 2 * height} />
          : line.width === 0
            ? <line key={index} x1={line.left * width} y1={line.top * height} x2={line.left * width} y2={(line.top + line.height) * height} />
            : <rect key={index} x={line.left * width} y={line.top * height} width={line.width * width} height={line.height * height} />)}
      </g>
      {dots.map((dot, index) => dot.ball ? (
        // A football, as on the board.
        <g key={`d${index}`} transform={`translate(${dot.left * width} ${dot.top * height})`}>
          <circle r={BALL} fill="#ffffff" />
          <g fill="#111827" clipPath="url(#tb-thumb-ball)">
            <polygon points={svgPoints(ball.middle)} />
            {ball.edge.map((points, edge) => <polygon key={edge} points={svgPoints(points)} />)}
          </g>
          <circle r={BALL} fill="none" stroke="#111827" strokeWidth={0.25} />
        </g>
      ) : (
        <circle key={`d${index}`} cx={dot.left * width} cy={dot.top * height} r={2.2} fill={dot.fill} stroke="#ffffff" strokeWidth={0.4} />
      ))}
    </svg>
  );
}
