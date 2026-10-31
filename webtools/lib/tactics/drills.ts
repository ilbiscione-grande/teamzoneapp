// Ready drills to start an empty board from: a few common exercises laid out
// round the middle of the pitch, and lineups. Each is a board's view and its
// objects, made afresh (new ids) every time one is chosen.
import { applyFormation, createObject, createPlayer, newId } from "./document.ts";
import { formations } from "./formations.ts";
import { PITCH_LENGTH, PITCH_WIDTH, type LineObject, type PitchView, type Point, type ShapeObject, type Side, type TacticsObject } from "./model.ts";

/** zoom: how far the view comes in on the middle of the pitch, where the drill is laid out. */
export type Drill = { key: string; name: string; about: string; view: PitchView; zoom?: number; objects: () => TacticsObject[] };

const mid = { x: PITCH_LENGTH / 2, y: PITCH_WIDTH / 2 };
const at = (dx: number, dy: number): Point => ({ x: mid.x + dx, y: mid.y + dy });
const base = (point: Point) => ({ id: newId(), x: point.x, y: point.y, rotation: 0, locked: false, hidden: false });

/** Players of one side at the points, numbered from 1. */
function players(side: Side, points: Point[], objects: TacticsObject[] = []): TacticsObject[] {
  const placed: TacticsObject[] = [];
  for (const point of points) placed.push(createPlayer(point, side, [...objects, ...placed]));
  return placed;
}

const cones = (points: Point[]) => points.map(point => createObject("cone", point));

function area(centre: Point, width: number, height: number, color = "#facc15", fill = 0.18): ShapeObject {
  return { ...base(centre), type: "rect", width, height, color, fill, dashed: true };
}

/** A pass (solid), a run (dashed) or a dribble (wavy) from one point to another. */
function move(from: Point, to: Point, kind: "pass" | "run" | "dribble" = "pass"): LineObject {
  return {
    ...base(from), type: "line", points: [0, 0, to.x - from.x, to.y - from.y], control: null, arrow: "end",
    dashed: kind === "run", wavy: kind === "dribble", color: kind === "pass" ? "#ffffff" : "#facc15", width: 0.3,
  };
}

const ball = (point: Point) => createObject("ball", point);

function goal(point: Point, rotation: number) {
  return { ...createObject("goal", point), rotation };
}

function lineup(formation: string): TacticsObject[] {
  let objects: TacticsObject[] = applyFormation([], "home", formations[formation]);
  objects = applyFormation(objects, "away", formations[formation]);
  return [...objects, ball(mid)];
}

export const drills: Drill[] = [
  {
    key: "rondo", name: "Rondo 4 mot 2", about: "Fyra håller bollen runt en ruta, två jagar.", view: "empty", zoom: 3.2,
    objects: () => {
      const outside = players("home", [at(0, -7), at(7, 0), at(0, 7), at(-7, 0)]);
      return [
        area(mid, 14, 14), ...cones([at(-7, -7), at(7, -7), at(7, 7), at(-7, 7)]),
        ...outside, ...players("away", [at(-1.5, -1), at(2, 1.5)]),
        ball({ x: outside[0].x, y: outside[0].y + 1 }), move(at(0, -6), at(6, 0)),
      ];
    },
  },
  {
    key: "passing-square", name: "Passningsfyrkant", about: "Passa och följ efter bollen till nästa kon.", view: "empty", zoom: 2.8,
    objects: () => {
      const corners = [at(-8, -8), at(8, -8), at(8, 8), at(-8, 8)];
      return [
        ...cones(corners), ...players("home", corners.map(point => ({ x: point.x, y: point.y + (point.y < mid.y ? -2 : 2) }))),
        ball({ x: corners[0].x + 1.2, y: corners[0].y - 2 }),
        move(at(-6.5, -8), at(6.5, -8)), move(at(-8, -9.5), at(6, -9.5), "run"),
      ];
    },
  },
  {
    key: "one-v-one", name: "1 mot 1 mot mål", about: "Anfallaren dribblar mot mål, försvararen möter.", view: "empty", zoom: 2.6,
    objects: () => [
      area(at(0, 0), 24, 18), goal(at(12, 0), 0), ...cones([at(-12, -4), at(-12, 4)]),
      ...players("home", [at(-10, 0)]), ...players("away", [at(4, 0), at(10, 0)]),
      ball(at(-8.8, 0)), move(at(-8, 0), at(2, -4), "dribble"),
    ],
  },
  {
    key: "small-sided", name: "Smålagsspel 5 mot 5", about: "Spel på liten plan med två mål.", view: "empty", zoom: 1.8,
    objects: () => [
      area(mid, 40, 28, "#ffffff", 0.08), goal(at(-20, 0), 180), goal(at(20, 0), 0),
      ...players("home", [at(-17.5, 0), at(-10, -7), at(-10, 7), at(-4, 0), at(2, -5)]),
      ...players("away", [at(17.5, 0), at(10, -7), at(10, 7), at(4, 0), at(-2, 5)]),
      ball(mid),
    ],
  },
  {
    key: "finishing", name: "Avslut efter dribbling", about: "Dribbla mellan konerna och avsluta på mål.", view: "attack",
    objects: () => {
      const start = { x: PITCH_LENGTH - 36, y: PITCH_WIDTH / 2 };
      return [
        ...cones([0, 1, 2, 3].map(index => ({ x: start.x + 4 + index * 3, y: PITCH_WIDTH / 2 + (index % 2 ? 1.5 : -1.5) }))),
        ...players("home", [start]), players("away", [{ x: PITCH_LENGTH - 1.5, y: PITCH_WIDTH / 2 }])[0],
        ball({ x: start.x + 1.2, y: start.y }),
        move({ x: start.x + 2, y: start.y }, { x: start.x + 16, y: start.y }, "dribble"),
        move({ x: start.x + 18, y: start.y }, { x: PITCH_LENGTH, y: PITCH_WIDTH / 2 - 2 }),
      ];
    },
  },
  { key: "lineup-433", name: "Uppställning 4-3-3", about: "Båda lagen i 4-3-3.", view: "full", objects: () => lineup("4-3-3") },
  { key: "lineup-442", name: "Uppställning 4-4-2", about: "Båda lagen i 4-4-2.", view: "full", objects: () => lineup("4-4-2") },
  { key: "lineup-7", name: "Uppställning 7 mot 7", about: "Båda lagen i 2-3-1.", view: "full", objects: () => lineup("2-3-1 (7 mot 7)") },
];
