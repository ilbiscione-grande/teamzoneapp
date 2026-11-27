// Draws Tacticsboard's fifteen starter exercises (TeamZone's own items in
// the library, seeded empty in 20261214090000) and writes the migration that
// fills them: each a board with its set-up, the pattern drawn as arrows, and
// a few frames playing it, plus the details a coach filters by.
// Run: node ops/tacticsboard_build_starters.ts
import { writeFileSync } from "node:fs";
import { newBoard, newFrame, newId } from "file:///C:/Dev/TeamzoneApp/webtools/lib/tactics/document.ts";
import type {
  AgeClass, Board, Effect, GameForm, GamePhase, LineObject, PitchOverlay, PitchView, Side, TacticsObject,
} from "file:///C:/Dev/TeamzoneApp/webtools/lib/tactics/model.ts";

type Spot = [number, number];
type Actor = { side: Side; at: Spot; keeper?: boolean; joker?: boolean };
type Step = {
  note: string;
  ms?: number;
  move?: Record<string, Spot>;
  bend?: Record<string, Spot>;
  /** The player who has the ball after the step, or a spot where it lies loose. */
  ball?: string | Spot;
  chip?: boolean;
  effects?: Record<string, Effect[]>;
};
type Exercise = {
  title: string;
  part: "warmup" | "main" | "finish";
  minutes: number;
  players: number;
  area: string;
  phase: GamePhase | null;
  ages: AgeClass[];
  forms: GameForm[];
  organisation: string;
  coaching: string;
  view: PitchView;
  overlay?: PitchOverlay;
  /** The part of the pitch shown when presenting and on the card: [x, y, width, height]. */
  crop?: [number, number, number, number];
  teams?: [string, string];
  setup: TacticsObject[];
  arrows: LineObject[];
  cast: Record<string, Actor>;
  /** Who has the ball first, or where it lies; null for a drill without one. */
  ball: string | Spot | null;
  steps: Step[];
};

const MID: Spot = [52.5, 34];
const at = (dx: number, dy: number): Spot => [MID[0] + dx, MID[1] + dy];
const round = (value: number) => Math.round(value * 100) / 100;
const base = ([x, y]: Spot) => ({ id: newId(), x: round(x), y: round(y), rotation: 0, locked: false, hidden: false });

const cone = (spot: Spot, color = "#f97316"): TacticsObject => ({ ...base(spot), type: "cone", color, scale: 1 });
const cones = (spots: Spot[], color?: string) => spots.map(spot => cone(spot, color));
const pole = (spot: Spot): TacticsObject => ({ ...base(spot), type: "pole", color: "#facc15", scale: 1 });
/** A goal; the mouth faces right at 0°, left at 180°. scale 1 is 3.2 m across, 2.3 a full-size goal. */
const goal = (spot: Spot, facing: "left" | "right", scale = 1): TacticsObject =>
  ({ ...base(spot), type: "goal", color: "#ffffff", scale, rotation: facing === "right" ? 0 : 180 });
/** An area by its centre and size. */
function area(centre: Spot, width: number, height: number, color = "#ffffff", fill = 0.08, dashed = true): TacticsObject {
  return { ...base(centre), type: "rect", width, height, color, fill, dashed };
}
/** A cone at each corner of an area. */
const corners = ([x, y]: Spot, width: number, height: number) =>
  cones([[x - width / 2, y - height / 2], [x + width / 2, y - height / 2], [x + width / 2, y + height / 2], [x - width / 2, y + height / 2]]);
function label(spot: Spot, text: string, size = 1.6): TacticsObject {
  return { ...base(spot), type: "text", text, size, color: "#ffffff", background: true, onPitch: true, align: "center", style: "bold" } as TacticsObject;
}

/** A pass (solid, white), a run (dashed, yellow) or a dribble (wavy, yellow); bend: the curve's middle. */
function arrow(from: Spot, to: Spot, kind: "pass" | "run" | "dribble" = "pass", bend?: Spot, aerial = false): LineObject {
  const [x, y] = from;
  return {
    ...base(from), type: "line", points: [0, 0, round(to[0] - x), round(to[1] - y)],
    control: bend ? { x: round(bend[0] - x), y: round(bend[1] - y) } : null, arrow: "end",
    dashed: kind === "run", wavy: kind === "dribble", color: kind === "pass" ? "#ffffff" : "#facc15", width: 0.3,
    ...(aerial ? { aerial: true } : {}),
  };
}
/** A ball that lies still through the frames, beside the one the exercise plays with. */
const looseBall = (spot: Spot): TacticsObject => ({ ...base(spot), type: "ball", attachedTo: null, offset: null });

// The ball at the feet, on the side the holder plays towards.
const offsetFor = (side: Side) => (side === "home" ? { x: 1.2, y: 0.5 } : { x: -1.2, y: 0.5 });

function board(exercise: Exercise): Board {
  const ids = new Map(Object.keys(exercise.cast).map(key => [key, newId()]));
  const numbers = new Map<string, number>();
  for (const side of ["home", "away"] as Side[]) {
    const keys = Object.keys(exercise.cast).filter(key => exercise.cast[key].side === side);
    // The keepers wear 1, the others count from 2 (from 1 when there is no keeper).
    let next = keys.some(key => exercise.cast[key].keeper) ? 2 : 1;
    for (const key of keys) numbers.set(key, exercise.cast[key].keeper ? 1 : next++);
  }
  const ballId = newId();
  let places: Record<string, Spot> = Object.fromEntries(Object.entries(exercise.cast).map(([key, actor]) => [key, actor.at]));
  let ball = exercise.ball;
  const frameOf = (step: Step | null, index: number) => {
    const players: TacticsObject[] = Object.entries(places).map(([key, [x, y]]) => {
      const actor = exercise.cast[key];
      const moved = step?.move?.[key] !== undefined;
      return {
        ...base([x, y]), id: ids.get(key)!, type: "player", side: actor.side, number: numbers.get(key)!, name: null,
        position: actor.keeper ? "MV" : null, personId: null,
        color: actor.keeper ? (actor.side === "home" ? "#facc15" : "#22c55e") : actor.joker ? "#9333ea" : null,
        pathControl: step?.bend?.[key] ? { x: step.bend[key][0], y: step.bend[key][1] } : null,
        effects: step?.effects?.[key] ?? (moved ? ["arrow"] : []),
      } as TacticsObject;
    });
    const passed = step?.ball !== undefined;
    const ballEffects = step?.effects?.ball ?? (passed ? ["trail"] : []);
    let ballObject: TacticsObject | null = null;
    if (ball === null) {
      // A drill without a ball.
    } else if (typeof ball === "string") {
      const [hx, hy] = places[ball];
      const offset = offsetFor(exercise.cast[ball].side);
      ballObject = {
        ...base([hx + offset.x, hy + offset.y]), id: ballId, type: "ball", attachedTo: ids.get(ball)!, offset,
        pathControl: null, effects: ballEffects, ...(step?.chip ? { flight: "chip" } : {}),
      } as TacticsObject;
    } else {
      ballObject = { ...base(ball), id: ballId, type: "ball", attachedTo: null, offset: null, pathControl: null, effects: ballEffects,
        ...(step?.chip ? { flight: "chip" } : {}) } as TacticsObject;
    }
    // The pattern's arrows show on the set-up only; the frames after play it.
    const objects = [...exercise.setup, ...(index === 0 ? exercise.arrows : []), ...players, ...(ballObject ? [ballObject] : [])];
    return { ...newFrame(objects), durationMs: step?.ms ?? 1500, note: step?.note ?? "Uppställning" };
  };
  const frames = [frameOf(null, 0)];
  exercise.steps.forEach((step, index) => {
    places = { ...places, ...(step.move ?? {}) };
    if (step.ball !== undefined) ball = step.ball;
    frames.push(frameOf(step, index + 1));
  });
  const [home, away] = exercise.teams ?? ["Blå", "Röd"];
  return {
    ...newBoard(exercise.title, home, away),
    view: exercise.view, overlay: exercise.overlay ?? "none", showNames: false, description: exercise.organisation,
    ...(exercise.crop ? { crop: { x: exercise.crop[0], y: exercise.crop[1], width: exercise.crop[2], height: exercise.crop[3] } } : {}),
    frames,
  };
}

/** A crop round a centre, as wide as asked and as tall as the card's picture (105 + 8 by 68 + 8). */
const cropAround = ([x, y]: Spot, width: number): [number, number, number, number] => {
  const height = round(width * 76 / 113);
  return [round(x - width / 2), round(y - height / 2), width, height];
};

const exercises: Exercise[] = [];

// 1. Rondo 6 mot 2 in 15 × 15 m.
{
  const c = MID, s = 7.5;
  exercises.push({
    title: "Aktiveringsrondo 6 mot 2", part: "warmup", minutes: 10, players: 8, area: "15 × 15 m", phase: null,
    ages: ["10-12", "13-15", "16+"], forms: ["7v7", "9v9", "11v11"],
    organisation: "Sex spelare runt en ruta på 15 × 15 meter håller bollen, två i mitten jagar. Bollen i rörelse med hög passningshastighet i en liten yta: väcker fötter och huvud inför passet. " +
      "Den som slår passningen som bryts, eller som bollen går ut på, byter med den av de två som jagat längst. Kör 3 × 3 minuter med vila emellan.",
    coaching: "Öppna kroppen mot nästa passning redan innan bollen kommer.\nMax två touch, en touch när det går.\nSpela mellan de två i mitten när luckan finns: det är rondons mål.\nSpelarna på kanten rör sig längs linjen för att alltid vara spelbara.\nDe två i mitten pressar tillsammans: en på bollen, en skär passningen.",
    view: "empty", crop: cropAround(c, 30),
    setup: [area(c, 15, 15, "#facc15", 0.14), ...corners(c, 15, 15)],
    arrows: [arrow(at(-s + 1, -3.5), at(s - 1, 3), "pass"), arrow(at(-1, -s + 1), at(-s + 1, -4), "pass")],
    cast: {
      a: { side: "home", at: at(-3, -s) }, b: { side: "home", at: at(4, -s) }, c: { side: "home", at: at(s, 2) },
      d: { side: "home", at: at(3, s) }, e: { side: "home", at: at(-4, s) }, f: { side: "home", at: at(-s, -3) },
      x: { side: "away", at: at(-2, 1.5) }, y: { side: "away", at: at(2, -2.5) },
    },
    ball: "a",
    steps: [
      { note: "A till F längs kanten. Den närmaste i mitten pressar, den andra stänger mitten.", ball: "f", move: { x: at(-5, -0.5), y: at(1, -2) } },
      { note: "F spelar mellan de två till C på andra sidan: en passning som tar bort båda.", ball: "c", move: { x: at(-3.5, 1), y: at(2, -2.5) } },
      { note: "C vänder med första touchen och spelar vidare till D. B och E rör sig för att bli spelbara.", ball: "d", move: { x: at(3, 3.5), y: at(4, 0), b: at(1, -s), e: at(-6, s) } },
    ],
  });
}

// 2. Running school with the ball: four lanes of slalom cones.
{
  const lanes = [-9, -3, 3, 9];
  const startX = MID[0] - 12, endX = MID[0] + 12;
  const setup: TacticsObject[] = [];
  const arrows: LineObject[] = [];
  const cast: Record<string, Actor> = {};
  lanes.forEach((dy, lane) => {
    const y = MID[1] + dy;
    setup.push(cone([startX, y], "#facc15"), cone([endX, y], "#facc15"));
    for (let i = 0; i < 5; i++) setup.push(cone([startX + 5 + i * 3.5, y], "#f97316"));
    cast[`s${lane}`] = { side: "home", at: [startX - 1.5, y] };
    // The other lanes' balls; lane one's is the one the frames play with.
    if (lane > 0) setup.push(looseBall([startX - 0.3, y + 0.5]));
    cast[`e${lane}`] = { side: "home", at: [endX + 1.5, y] };
  });
  arrows.push(arrow([startX, MID[1] - 9], [endX - 1.5, MID[1] - 9], "dribble"), arrow([startX, MID[1] - 3], [endX - 1.5, MID[1] - 3], "dribble"));
  exercises.push({
    title: "Löpskola med boll", part: "warmup", minutes: 8, players: 8, area: "25 × 20 m", phase: null,
    ages: ["7-9", "10-12", "13-15"], forms: ["5v5", "7v7", "9v9"],
    organisation: "Fyra banor med fem koner var, en spelare i varje ände. Spelaren med boll dribblar genom konerna, passar till kompisen i andra änden och tar dennes plats. " +
      "Korta stafetter med teknikinslag som höjer pulsen och skärper tekniken. Byt teknik varje varv: insida, utsida, bara vänster, bara höger, fint vid sista konen.",
    coaching: "Små touch nära foten genom konerna.\nBlicken upp mellan konerna, inte bara på bollen.\nBromsa bollen med sulan i varje vändning.\nÖka tempot varvet ut: sista varvet som en tävling mellan banorna.",
    view: "empty", crop: cropAround(MID, 36), setup, arrows, cast, ball: "s0",
    steps: [
      { note: "Dribbla genom konerna i bana ett.", ms: 2400, move: { s0: [endX - 2.5, MID[1] - 9] }, bend: { s0: [MID[0], MID[1] - 10.5] } },
      { note: "Passa till kompisen i andra änden och ta dennes plats.", ball: "e0", move: { s0: [endX + 1, MID[1] - 10.5] } },
      { note: "Kompisen dribblar tillbaka genom banan.", ms: 2400, move: { e0: [startX + 2, MID[1] - 9] }, bend: { e0: [MID[0], MID[1] - 7.5] } },
    ],
  });
}

// 3. Speed and change of direction: two zigzag lanes, the pair races.
{
  const lanes = [-5, 5];
  const zig = (dy: number): Spot[] => [at(-10, dy), at(-5, dy - 2.5), at(0, dy + 2.5), at(5, dy - 2.5), at(10, dy)];
  const setup: TacticsObject[] = [];
  for (const dy of lanes) {
    const [start, ...rest] = zig(dy);
    setup.push(cone(start, "#facc15"), ...cones(rest.slice(0, 3)), pole(at(12, dy - 1.5)), pole(at(12, dy + 1.5)));
  }
  const arrows = [
    arrow(at(-10, -5), at(-5, -7.5), "run"), arrow(at(-5, -7.5), at(0, -2.5), "run"), arrow(at(0, -2.5), at(5, -7.5), "run"), arrow(at(5, -7.5), at(12, -5), "run"),
  ];
  exercises.push({
    title: "Snabbhet och riktningsförändring", part: "warmup", minutes: 10, players: 8, area: "25 × 15 m", phase: null,
    ages: ["10-12", "13-15", "16+"], forms: ["7v7", "9v9", "11v11"],
    organisation: "Två banor bredvid varandra med koner i sicksack och ett mål av två pinnar i slutet. Två spelare startar samtidigt och tävlar: sprint till varje kon, vänd och sprint igen. " +
      "Korta sprintar med snabba vändningar förbereder kroppen för explosiva moment i huvuddelen. Gå tillbaka i lugnt tempo, 6–8 lopp var.",
    coaching: "Sänk tyngdpunkten innan vändningen.\nKorta steg in i vändningen, långa steg ut ur den.\nBromsa med den yttre foten och tryck ifrån med den.\nFull fart i 4–6 sekunder, sedan vila: kvalitet före mängd.\nVariant: starta på signal, liggande eller med ryggen mot banan.",
    view: "empty", crop: cropAround(at(-4, 0), 42), setup, arrows,
    cast: {
      a: { side: "home", at: at(-11.5, -5) }, b: { side: "away", at: at(-11.5, 5) }, w1: { side: "home", at: at(-14.5, -5) }, w2: { side: "away", at: at(-14.5, 5) },
      w3: { side: "home", at: at(-17.5, -5) }, w4: { side: "away", at: at(-17.5, 5) }, w5: { side: "home", at: at(-20.5, -5) }, w6: { side: "away", at: at(-20.5, 5) },
    },
    ball: null,
    steps: [
      { note: "Start! Sprint till första konen.", ms: 700, move: { a: at(-5, -7.5), b: at(-5, 2.5) }, effects: { a: ["arrow"], b: ["arrow"] } },
      { note: "Vänd på yttre foten och sprint till nästa.", ms: 700, move: { a: at(0, -2.5), b: at(0, 7.5) } },
      { note: "En vändning till.", ms: 700, move: { a: at(5, -7.5), b: at(5, 2.5) } },
      { note: "Raka vägen genom målet. Nästa par startar.", ms: 900, move: { a: at(14, -5), b: at(14, 5), w1: at(-11.5, -5), w2: at(-11.5, 5), w3: at(-14.5, -5), w4: at(-14.5, 5), w5: at(-17.5, -5), w6: at(-17.5, 5) } },
    ],
  });
}

// 4. Pressing in pairs, 2 v 1.
{
  const c = MID;
  exercises.push({
    title: "Press i par 2 mot 1", part: "main", minutes: 15, players: 6, area: "20 × 15 m", phase: "regaining",
    ages: ["10-12", "13-15", "16+"], forms: ["7v7", "9v9", "11v11"],
    organisation: "En yta på 20 × 15 meter med två konmål på kortsidan. Två spelare pressar en bollhållare i den begränsade ytan och tränar vinklar och samarbete i pressen. " +
      "Röd får bollen från tränaren och ska dribbla igenom något av konmålen. Blå startar från andra kortsidan. Vinner blå bollen: spela den till tränaren. Byt roller efter varje lopp.",
    coaching: "Första pressaren springer i en båge och styr bollhållaren åt ett håll.\nAndra pressaren täcker bakom på den sida bollen styrs mot.\nSakta ner de sista metrarna: låg tyngdpunkt, sidan till.\nPrata: \"Jag tar!\" och \"Jag täcker!\".\nVinn bollen när den andra har stängt vägen.",
    view: "empty", crop: cropAround(at(2.5, 0), 38),
    setup: [area(c, 20, 15, "#ffffff", 0.08), ...corners(c, 20, 15), ...cones([at(10, -5.5), at(10, -2.5), at(10, 2.5), at(10, 5.5)], "#facc15")],
    arrows: [arrow(at(10, 0), at(1.5, 0.5), "run", at(6, -4)), arrow(at(13, 0), at(4, 3.5), "run", at(9, 3))],
    cast: {
      r: { side: "away", at: at(-8.5, 0) }, b1: { side: "home", at: at(11, 0) }, b2: { side: "home", at: at(14, 0) },
      q1: { side: "away", at: at(-12, -3) }, q2: { side: "home", at: at(17, 0) }, t: { side: "away", at: at(-12, 3), joker: true },
    },
    ball: "t",
    steps: [
      { note: "Tränaren spelar in till röd, blå startar.", ball: "r", move: { r: at(-7, 0), b1: at(3, -1.5), b2: at(5, 2) } },
      { note: "Första pressaren går i båge och stänger vänster: röd tvingas mot högra konmålet.", move: { r: at(-3, 1.5), b1: at(-0.5, -0.5), b2: at(2.5, 3.5) }, bend: { b1: [MID[0] + 1, MID[1] - 3] } },
      { note: "Andra pressaren har täckt: de två vinner bollen tillsammans.", ball: "b2", move: { r: at(-0.5, 3), b1: at(-0.5, 2), b2: at(0.5, 3.8) }, effects: { b2: ["ring"] } },
      { note: "Bollen till tränaren. Nästa trio.", ball: "t", move: { b2: at(-1, 3.5) } },
    ],
  });
}

// 5. Triggers and signals, 4 v 4 + 2 jokers.
{
  const c = MID, s = 12.5;
  exercises.push({
    title: "Utlösare och signaler 4 mot 4 + 2", part: "main", minutes: 20, players: 10, area: "25 × 25 m", phase: "regaining",
    ages: ["13-15", "16+"], forms: ["9v9", "11v11"],
    organisation: "Spel 4 mot 4 i en yta på 25 × 25 meter med två lila jokrar på kanterna som spelar med laget som har bollen. Laget med boll ska hålla den, tio passningar i rad ger ett poäng. " +
      "Laget utan boll tränar att läsa tydliga signaler för press och reagera samtidigt: när signalen kommer kliver alla fyra på en gång. 4 × 4 minuter.",
    coaching: "Signaler att pressa: bakåtpassning, dålig mottagning, spelare med ryggen mot spelriktningen och passning mot kanten.\nRopa signalen högt, till exempel \"Nu!\", så att alla kliver samtidigt.\nDen närmaste pressar bollen, de andra tar närmaste passningsalternativ.\nIngen signal: håll ihop och vänta, jaga inte ensam.",
    view: "empty", crop: cropAround(c, 42),
    setup: [area(c, 25, 25, "#ffffff", 0.08), ...corners(c, 25, 25)],
    arrows: [arrow(at(1, -4), at(-5, -6), "pass"), arrow(at(-2, 2), at(-5, -3.5), "run"), arrow(at(4, -2), at(1, -6), "run"), arrow(at(5, 5), at(0, 2), "run")],
    cast: {
      r1: { side: "away", at: at(-5, -7) }, r2: { side: "away", at: at(1, -4) }, r3: { side: "away", at: at(-6, 6) }, r4: { side: "away", at: at(7, 8) },
      b1: { side: "home", at: at(-2, 2) }, b2: { side: "home", at: at(4, -2) }, b3: { side: "home", at: at(5, 5) }, b4: { side: "home", at: at(-1, 9) },
      j1: { side: "away", at: at(0, -s - 1), joker: true }, j2: { side: "away", at: at(0, s + 1), joker: true },
    },
    ball: "r2",
    steps: [
      { note: "Röd spelar bakåt till en spelare med ryggen mot planen: signalen!", ball: "r1" },
      { note: "\"Nu!\" Alla fyra kliver samtidigt: en pressar bollen, tre stänger passningarna.", move: { b1: at(-4.5, -4), b2: at(1, -5), b3: at(-3, 4), b4: at(5, 6.5) }, effects: { b1: ["arrow", "ring"] } },
      { note: "Röd har ingen väg framåt och måste chansa. Blå vinner bollen.", ball: "b2", move: { r1: at(-7, -8), b1: at(-5.5, -6.5), r2: at(2, -3.5) }, effects: { b2: ["ring"] } },
    ],
  });
}

// 6. Press to finish, 6 v 6 with keepers.
{
  const c = MID, L = 50, W = 35;
  const left = c[0] - L / 2, right = c[0] + L / 2;
  exercises.push({
    title: "Press till avslut 6 mot 6", part: "finish", minutes: 15, players: 14, area: "50 × 35 m", phase: "regaining",
    ages: ["13-15", "16+"], forms: ["9v9", "11v11"],
    organisation: "Matchspel 6 mot 6 med målvakter på en plan på 50 × 35 meter. Planen delas på mitten med koner. Varje bollvinst högt upp, på motståndarnas planhalva, ska leda till ett snabbt avslut inom tre passningar. " +
      "Mål efter bollvinst på motståndarnas halva räknas dubbelt. Målvakten startar spelet vid varje ny boll.",
    coaching: "Pressa direkt när motståndarnas målvakt spelar ut till en back.\nStyr spelet mot kanten, där sidlinjen hjälper till.\nEfter bollvinst: framåt först. Max tre passningar till avslut, räkna högt.\nDe som inte vinner bollen löper mot mål direkt, inte bort från det.",
    view: "empty", crop: cropAround(c, 62),
    setup: [area(c, L, W, "#ffffff", 0.06), ...corners(c, L, W), ...cones([at(0, -W / 2), at(0, -W / 4), at(0, 0), at(0, W / 4), at(0, W / 2)], "#facc15"),
      goal([left, c[1]], "right", 1.6), goal([right, c[1]], "left", 1.6)],
    arrows: [arrow(at(13, -6), at(20, -10), "run", at(18, -6.5)), arrow(at(6, 3), at(18, 8), "run")],
    cast: {
      bk: { side: "home", at: [left + 1, c[1]], keeper: true }, b1: { side: "home", at: at(-14, -6) }, b2: { side: "home", at: at(-14, 7) },
      b3: { side: "home", at: at(5, -2) }, b4: { side: "home", at: at(13, -6) }, b5: { side: "home", at: at(6, 3) },
      rk: { side: "away", at: [right - 1, c[1]], keeper: true }, r1: { side: "away", at: at(18, -9) }, r2: { side: "away", at: at(18, 9) },
      r3: { side: "away", at: at(9, 1) }, r4: { side: "away", at: at(-3, -8) }, r5: { side: "away", at: at(-5, 7) },
    },
    ball: "rk",
    steps: [
      { note: "Röds målvakt spelar ut till vänsterbacken. Signalen: blå pressar.", ball: "r1", move: { r1: at(19, -11) } },
      { note: "Blå 4 pressar i båge och styr mot sidlinjen, 3 och 5 stänger inåt.", move: { b4: at(17, -9), b3: at(12, -4), b5: at(13, 3) }, bend: { b4: [MID[0] + 17, MID[1] - 6] } },
      { note: "Bollvinst högt upp! Passning ett: in till 3.", ball: "b3", move: { b4: at(17, -10) } },
      { note: "Passning två: 3 till 5, som tar sig mot mål.", ball: "b5", move: { b5: at(17, 3), b3: at(14, -3) } },
      { note: "Avslut inom tre passningar.", ball: [right - 0.5, c[1] + 0.8], ms: 700 },
    ],
  });
}

// 7. Build-up from the keeper, 4 + keeper v 2, on the own half.
{
  const gx = 1;
  exercises.push({
    title: "Uppspel från målvakt 4 mot 2", part: "main", minutes: 15, players: 7, area: "Halvplan", phase: "build_up",
    ages: ["10-12", "13-15", "16+"], forms: ["7v7", "9v9", "11v11"],
    organisation: "Backlinje och målvakt tränar att skapa spelbara vinklar mot en pressande motståndare. Målvakten och fyra backar mot två anfallare på egen planhalva. " +
      "Blå ska spela sig ut och dribbla igenom ett av två konmål vid mittlinjen. Vinner röd bollen får de avsluta på mål. Ny boll från målvakten varje gång.",
    coaching: "Mittbackarna går isär och brett, ut mot straffområdets hörn, när målvakten har bollen.\nYtterbackarna högt och brett, nära sidlinjen.\nÖppna kroppen vid mottagningen så du ser hela planen.\nSpela till den som är fri: runt pressen eller igenom den.\nMålvakten är alltid ett säkert alternativ bakåt.",
    view: "defend", teams: ["Blå", "Röd"],
    setup: [goal([0, 34], "right", 2.3), ...cones([[48, 8], [48, 16], [48, 52], [48, 60]], "#facc15")],
    arrows: [arrow([3, 34], [13, 50], "pass"), arrow([14, 51], [28, 60], "pass"), arrow([24, 63], [46, 59], "dribble")],
    cast: {
      gk: { side: "home", at: [gx + 2, 34], keeper: true }, cb1: { side: "home", at: [14, 20] }, cb2: { side: "home", at: [14, 48] },
      lb: { side: "home", at: [26, 8] }, rb: { side: "home", at: [26, 60] },
      f1: { side: "away", at: [24, 28] }, f2: { side: "away", at: [26, 40] },
    },
    ball: "gk",
    steps: [
      { note: "Målvakten spelar ut till högra mittbacken, som står brett.", ball: "cb2", move: { cb2: [13, 50], f2: [19, 44] } },
      { note: "Anfallaren pressar: ytterbacken är fri. Spela runt pressen.", ball: "rb", move: { f2: [16, 48], rb: [27, 61] } },
      { note: "Ytterbacken dribblar fram och genom konmålet.", ms: 2000, move: { rb: [49, 56] }, bend: { rb: [40, 61] } },
    ],
  });
}

// 8. Through the thirds, 8 v 8 with keepers.
{
  const c = MID, L = 72, W = 50;
  const left = c[0] - L / 2, right = c[0] + L / 2, third = L / 3;
  exercises.push({
    title: "Genom tredjedelarna 8 mot 8", part: "main", minutes: 20, players: 18, area: "70 × 50 m", phase: "build_up",
    ages: ["13-15", "16+"], forms: ["9v9", "11v11"],
    organisation: "Positionsspel 8 mot 8 med målvakter på en plan på ungefär 70 × 50 meter, delad i tre lika stora zoner. Laget måste ha minst en passning i varje tredjedel innan det får göra mål. " +
      "Övningen belönar laget för att spela sig igenom planens alla tredjedelar med kontroll. Mål efter att ha spelat genom alla tre zoner med en spelare mellan motståndarens linjer räknas dubbelt.",
    coaching: "Sök spelare mellan motståndarens linjer: dit vill vi.\nBredd: ytterspelarna nära sidlinjen drar isär motståndarna.\nHellre en passning bakåt än en chansning framåt.\nRörelse utan boll: skapa vinklar så att bollhållaren har två alternativ.",
    view: "empty", crop: cropAround(c, 84),
    setup: [area([left + third / 2, c[1]], third, W, "#ffffff", 0.05), area([c[0], c[1]], third, W, "#facc15", 0.07), area([right - third / 2, c[1]], third, W, "#ffffff", 0.05),
      goal([left, c[1]], "right", 2.3), goal([right, c[1]], "left", 2.3),
      label([left + third / 2, c[1] - W / 2 + 2.5], "1"), label([c[0], c[1] - W / 2 + 2.5], "2"), label([right - third / 2, c[1] - W / 2 + 2.5], "3")],
    arrows: [arrow(at(-26, 8), at(-12, 3), "pass"), arrow(at(-11, 3), at(2, -4), "pass"), arrow(at(3, -4), at(18, -16), "pass")],
    cast: {
      bk: { side: "home", at: [left + 1.5, c[1]], keeper: true }, b1: { side: "home", at: at(-26, -9) }, b2: { side: "home", at: at(-26, 8) },
      b3: { side: "home", at: at(-14, -20) }, b4: { side: "home", at: at(-14, 21) }, b5: { side: "home", at: at(-12, 2) },
      b6: { side: "home", at: at(2, -5) }, b7: { side: "home", at: at(10, 12) }, b8: { side: "home", at: at(18, -16) },
      rk: { side: "away", at: [right - 1.5, c[1]], keeper: true }, r1: { side: "away", at: at(-16, -7) }, r2: { side: "away", at: at(-16, 8) },
      r3: { side: "away", at: at(-4, -12) }, r4: { side: "away", at: at(-3, 1) }, r5: { side: "away", at: at(-4, 14) },
      r6: { side: "away", at: at(12, -6) }, r7: { side: "away", at: at(12, 6) }, r8: { side: "away", at: at(22, 0) },
    },
    ball: "b2",
    steps: [
      { note: "Zon 1: mittbacken spelar in till sexan mellan anfallarna.", ball: "b5", move: { r2: at(-14, 5), b5: at(-11, 3) } },
      { note: "Zon 2: sexan hittar spelaren mellan motståndarens linjer.", ball: "b6", move: { r4: at(-5, -1), b6: at(3, -4) } },
      { note: "Zon 3: vidare ut till yttern, som har tid och yta.", ball: "b8", move: { r6: at(9, -5), b8: at(19, -15) } },
      { note: "Inlägg och avslut: alla tre zoner har haft en passning.", ball: [right - 0.5, c[1] - 1.5], move: { b7: at(30, 2), b8: at(24, -14) }, ms: 1200 },
    ],
  });
}

// 9. Build-up to goal, 7 v 7.
{
  const c = MID, L = 55, W = 36;
  const left = c[0] - L / 2, right = c[0] + L / 2;
  exercises.push({
    title: "Uppbyggnad till mål 7 mot 7", part: "finish", minutes: 15, players: 14, area: "55 × 36 m", phase: "build_up",
    ages: ["10-12", "13-15", "16+"], forms: ["7v7", "9v9"],
    organisation: "Spel 7 mot 7 med målvakter på en sjumannaplan. Laget måste slå minst fyra passningar i uppbyggnaden innan avslut är tillåtet. " +
      "Målvakten startar spelet efter varje mål och varje boll över kortlinjen. Tränaren räknar passningarna högt.",
    coaching: "Backarna går brett direkt när vi vinner bollen eller målvakten har den.\nMålvakten är med i spelet: ett säkert alternativ bakåt.\nSpela framåt när det är öppet, annars runt.\nTänk på kroppsställningen vid mottagning: se framåt.",
    view: "empty", crop: cropAround(c, 66),
    setup: [area(c, L, W, "#ffffff", 0.06), ...corners(c, L, W), goal([left, c[1]], "right", 1.6), goal([right, c[1]], "left", 1.6)],
    arrows: [arrow([left + 2, c[1]], at(-18, 12), "pass"), arrow(at(-17, 13), at(-8, 2), "pass"), arrow(at(-7, 2), at(3, 14), "pass"), arrow(at(4, 14), at(13, 2), "pass")],
    cast: {
      bk: { side: "home", at: [left + 1.5, c[1]], keeper: true }, b1: { side: "home", at: at(-18, -12) }, b2: { side: "home", at: at(-18, 12) },
      b3: { side: "home", at: at(-8, 2) }, b4: { side: "home", at: at(3, -13) }, b5: { side: "home", at: at(3, 14) }, b6: { side: "home", at: at(13, 1) },
      rk: { side: "away", at: [right - 1.5, c[1]], keeper: true }, r1: { side: "away", at: at(16, -8) }, r2: { side: "away", at: at(16, 8) },
      r3: { side: "away", at: at(5, -3) }, r4: { side: "away", at: at(-3, -10) }, r5: { side: "away", at: at(-3, 9) }, r6: { side: "away", at: at(-12, 0) },
    },
    ball: "bk",
    steps: [
      { note: "1: målvakten startar till högerbacken.", ball: "b2", move: { b2: at(-17, 13) } },
      { note: "2: in till mittfältaren.", ball: "b3", move: { r6: at(-11, 4), b3: at(-7, 2) } },
      { note: "3: ut till yttern på kanten.", ball: "b5", move: { r5: at(-1, 11), b5: at(4, 14) } },
      { note: "4: in till anfallaren som kommer emot.", ball: "b6", move: { b6: at(13, 2), r2: at(15, 5) } },
      { note: "Fyra passningar: nu får laget avsluta.", ball: [right - 0.5, c[1] - 0.8], ms: 700 },
    ],
  });
}

// 10. Zonal defending, 5 v 5 on the own half.
{
  const line = (ys: number[], x: number): Spot[] => ys.map(y => [x, y]);
  const [d1, d2, d3, d4] = line([14, 27, 41, 54], 22);
  exercises.push({
    title: "Zonförsvar och förflyttning 5 mot 5", part: "main", minutes: 15, players: 11, area: "Halvplan", phase: "defending",
    ages: ["13-15", "16+"], forms: ["9v9", "11v11"],
    organisation: "Blå försvarar ett mål med målvakt: fyra i en backlinje och en framför. Röd har fem spelare som flyttar bollen från sida till sida och försöker spela in bakom linjen eller avsluta. " +
      "Laget tränar att flytta som en enhet och täcka zoner när bollen byter sida. Vinner blå bollen ska de spela den till en av två konmål vid mittlinjen.",
    coaching: "Flytta när bollen är på väg, inte när den har kommit fram.\nDen närmaste kliver mot bollen, de andra drar ihop mot bollsidan.\nHåll 8–10 meter mellan spelarna i linjen.\nBortre ytterbacken går in och täcker centralt: den bortre kanten får vara fri.\nLinjen följer med upp när bollen spelas bakåt.",
    view: "defend",
    setup: [goal([0, 34], "right", 2.3), ...cones([[50, 14], [50, 20], [50, 48], [50, 54]], "#facc15")],
    arrows: [arrow([38, 6], [36, 60], "pass", [44, 34], true), arrow([22, 14], [24, 22], "run"), arrow([22, 54], [22, 47], "run")],
    cast: {
      gk: { side: "home", at: [2, 34], keeper: true }, d1: { side: "home", at: d1 }, d2: { side: "home", at: d2 }, d3: { side: "home", at: d3 }, d4: { side: "home", at: d4 },
      m: { side: "home", at: [30, 30] },
      a1: { side: "away", at: [36, 6] }, a2: { side: "away", at: [40, 22] }, a3: { side: "away", at: [42, 38] }, a4: { side: "away", at: [37, 60] }, a5: { side: "away", at: [30, 46] },
    },
    ball: "a1",
    steps: [
      { note: "Bollen på vänsterkanten: linjen förskjuter mot bollsidan. Närmaste back kliver, bortre back går in centralt.", ms: 1400,
        move: { d1: [24, 9], d2: [20, 19], d3: [20, 30], d4: [20, 41], m: [30, 18] } },
      { note: "Röd byter sida med en lång passning. Blå flyttar medan bollen är i luften.", ball: "a4", chip: true, ms: 2000,
        move: { d1: [20, 26], d2: [20, 37], d3: [20, 48], d4: [24, 58], m: [30, 48] } },
      { note: "Ny bollsida: samma avstånd, samma princip. Mitten är stängd.", ms: 1200, move: { a5: [32, 44], a3: [40, 36] } },
    ],
  });
}

// 11. Compactness, 8 v 4.
{
  const c = MID, L = 40, W = 30;
  exercises.push({
    title: "Kompakthet 8 mot 4", part: "main", minutes: 20, players: 12, area: "40 × 30 m", phase: "defending",
    ages: ["13-15", "16+"], forms: ["9v9", "11v11"],
    organisation: "Åtta röda runt och i en yta på 40 × 30 meter mot fyra blå. Röd ska spela in bollen i den gula mittzonen till en medspelare. Överläge för det anfallande laget tvingar försvararna att hålla avstånden och täcka de centrala ytorna. " +
      "Blå får ett poäng för varje bollvinst och för varje minut utan att röd har spelat in i mittzonen. Byt fyra var tredje minut.",
    coaching: "De fyra håller ihop: högst tio meter mellan varandra.\nStäng mitten först, låt röd spela utanpå.\nFlytta mot bollen tillsammans, som om ni var bundna med ett rep.\nDen närmaste kliver, de andra täcker bakom och stänger in-passningen.",
    view: "empty", crop: cropAround(c, 52),
    setup: [area(c, L, W, "#ffffff", 0.06), ...corners(c, L, W), area(c, 12, 10, "#facc15", 0.2)],
    arrows: [arrow(at(-18, -6), at(-12, -14), "pass"), arrow(at(-6, -5), at(-9, -9), "run"), arrow(at(-6, 5), at(-7, 0), "run")],
    cast: {
      r1: { side: "away", at: at(-18, -6) }, r2: { side: "away", at: at(-12, -14) }, r3: { side: "away", at: at(4, -14) }, r4: { side: "away", at: at(18, -7) },
      r5: { side: "away", at: at(18, 7) }, r6: { side: "away", at: at(4, 14) }, r7: { side: "away", at: at(-12, 14) }, r8: { side: "away", at: at(1, 1) },
      b1: { side: "home", at: at(-6, -5) }, b2: { side: "home", at: at(-6, 5) }, b3: { side: "home", at: at(6, -5) }, b4: { side: "home", at: at(6, 5) },
    },
    ball: "r1",
    steps: [
      { note: "Bollen till övre kanten: alla fyra flyttar mot bollen.", ball: "r2", move: { b1: at(-8, -8), b2: at(-6, -1), b3: at(0, -6), b4: at(1, 1) } },
      { note: "Vidare runt. De fyra följer med, avstånden är desamma och mitten stängd.", ball: "r3", move: { b1: at(-3, -9), b2: at(-3, -2), b3: at(4, -7), b4: at(4, 0), r8: at(-1, 3) } },
      { note: "Röd tvingas spela utanpå igen: ingen väg in i mittzonen.", ball: "r4", move: { b1: at(3, -7), b2: at(2, 0), b3: at(9, -5), b4: at(8, 2) } },
    ],
  });
}

// 12. Defensive block in a 7 v 7 game.
{
  const c = MID, L = 55, W = 36;
  const left = c[0] - L / 2, right = c[0] + L / 2;
  exercises.push({
    title: "Försvarsblock i matchspel 7 mot 7", part: "finish", minutes: 15, players: 14, area: "55 × 36 m", phase: "defending",
    ages: ["10-12", "13-15", "16+"], forms: ["7v7", "9v9", "11v11"],
    organisation: "Matchspel 7 mot 7 med målvakter. Matchspel med fokus på blockets höjd och på att täcka bakom spelaren som kliver fram. Bestäm innan var första försvarslinjen står, här vid konerna en bit in på egen planhalva. " +
      "Stoppa spelet ibland och låt spelarna stå kvar: står blocket rätt?",
    coaching: "Blocket startar vid konerna: där börjar vi pressa.\nNär en spelare kliver fram täcker grannen bakom.\nBacklinjen följer med upp när bollen spelas bakåt.\nIngen kliver ensam: ropa när du går.\nKompakt i längd och bredd, ingen lucka mellan linjerna.",
    view: "empty", crop: cropAround(c, 66),
    setup: [area(c, L, W, "#ffffff", 0.06), ...corners(c, L, W), goal([left, c[1]], "right", 1.6), goal([right, c[1]], "left", 1.6),
      ...cones([at(-4, -W / 2), at(-4, W / 2)], "#facc15")],
    arrows: [arrow(at(-6, -1), at(4, -2), "run"), arrow(at(-12, -4), at(-7, -2), "run")],
    cast: {
      bk: { side: "home", at: [left + 1.5, c[1]], keeper: true }, b1: { side: "home", at: at(-14, -8) }, b2: { side: "home", at: at(-14, 8) },
      b3: { side: "home", at: at(-7, -11) }, b4: { side: "home", at: at(-6, -1) }, b5: { side: "home", at: at(-7, 10) }, b6: { side: "home", at: at(-3, 3) },
      rk: { side: "away", at: [right - 1.5, c[1]], keeper: true }, r1: { side: "away", at: at(14, -10) }, r2: { side: "away", at: at(8, -2) },
      r3: { side: "away", at: at(14, 9) }, r4: { side: "away", at: at(-1, -12) }, r5: { side: "away", at: at(-2, 12) }, r6: { side: "away", at: at(-10, 1) },
    },
    ball: "r2",
    steps: [
      { note: "Röds mittback driver in över konerna: blockets signal.", ms: 1200, move: { r2: at(3, -2) } },
      { note: "Mittfältaren kliver och pressar. Grannen och backarna täcker bakom honom.", move: { b4: at(1, -2), b6: at(-4, 1), b1: at(-11, -5), b2: at(-12, 5), b3: at(-6, -9), b5: at(-7, 7) }, effects: { b4: ["arrow", "ring"] } },
      { note: "Röd spelar bakåt: hela blocket följer med upp.", ball: "r1", move: { r2: at(5, -3), b1: at(-8, -6), b2: at(-9, 4), b3: at(-1, -10), b4: at(3, -4), b5: at(-3, 7), b6: at(0, 0) } },
    ],
  });
}

// 13. Transition 4 v 4 with keepers.
{
  const c = MID, L = 34, W = 26;
  const left = c[0] - L / 2, right = c[0] + L / 2;
  exercises.push({
    title: "Omställning 4 mot 4 med målvakt", part: "main", minutes: 15, players: 10, area: "35 × 25 m", phase: "counter",
    ages: ["10-12", "13-15", "16+"], forms: ["5v5", "7v7", "9v9", "11v11"],
    organisation: "Spel 4 mot 4 med målvakter på en yta på 35 × 25 meter. Direkt efter bollvinst ska laget snabbt hitta den första aktionen framåt. " +
      "Mål inom fem sekunder efter bollvinst räknas dubbelt. Tränaren står vid sidan och spelar in en ny boll när bollen går ut, så det blir många omställningar.",
    coaching: "Första tanken efter bollvinst: kan vi spela framåt direkt?\nDen som vinner bollen tittar upp innan första touchen.\nMinst en löper på djupet direkt, en går brett.\nLaget som tappar bollen: närmaste pressar direkt, de andra springer hem.",
    view: "empty", crop: cropAround(c, 46),
    setup: [area(c, L, W, "#ffffff", 0.06), ...corners(c, L, W), goal([left, c[1]], "right", 1.4), goal([right, c[1]], "left", 1.4)],
    arrows: [arrow(at(-5, 3), at(8, 4), "pass"), arrow(at(-1, -5), at(12, -7), "run")],
    cast: {
      bk: { side: "home", at: [left + 1, c[1]], keeper: true }, b1: { side: "home", at: at(-10, -5) }, b2: { side: "home", at: at(-5, 3) },
      b3: { side: "home", at: at(-1, -5) }, b4: { side: "home", at: at(3, 7) },
      rk: { side: "away", at: [right - 1, c[1]], keeper: true }, r1: { side: "away", at: at(-8, 1) }, r2: { side: "away", at: at(-3, -8) },
      r3: { side: "away", at: at(-4, 9) }, r4: { side: "away", at: at(6, -2) },
    },
    ball: "r1",
    steps: [
      { note: "Röd anfaller. Blå 2 bryter passningen och vinner bollen.", ball: "b2", move: { r1: at(-8, 2), b2: at(-6, 2) }, effects: { b2: ["ring"] } },
      { note: "Upp med huvudet: 3 och 4 löper direkt framåt, 3 på djupet.", ms: 1000, move: { b3: at(9, -6), b4: at(8, 5), r4: at(4, -1) } },
      { note: "Första passningen framåt in i ytan till 4.", ball: "b4", move: { b4: at(10, 4) } },
      { note: "Avslut inom fem sekunder: dubbelt mål.", ball: [right - 0.5, c[1] + 0.6], ms: 700 },
    ],
  });
}

// 14. Counter from a press, 6 v 6 with keepers.
{
  const c = MID, L = 60, W = 40;
  const left = c[0] - L / 2, right = c[0] + L / 2;
  exercises.push({
    title: "Kontring från press 6 mot 6", part: "main", minutes: 20, players: 14, area: "60 × 40 m", phase: "counter",
    ages: ["13-15", "16+"], forms: ["9v9", "11v11"],
    organisation: "Spel 6 mot 6 med målvakter på en plan på 60 × 40 meter. Röd anfaller och blå pressar på egen planhalva. Bollvinst på egen planhalva ska leda till en snabb kontring med stöd i bredd och djup. " +
      "Mål inom åtta sekunder efter bollvinst ger tre poäng, annat mål ett poäng. Byt roller efter fyra minuter.",
    coaching: "Vinn bollen och spela direkt till den som är längst fram och spelbar.\nTvå löper i bredd, en på djupet: ge bollföraren tre val.\nBollföraren springer med bollen mot mitten och drar på sig försvarare.\nAvsluta inom åtta sekunder, annars lugna ner och behåll bollen.",
    view: "empty", crop: cropAround(c, 72),
    setup: [area(c, L, W, "#ffffff", 0.06), ...corners(c, L, W), ...cones([at(0, -W / 2), at(0, W / 2)], "#facc15"),
      goal([left, c[1]], "right", 2), goal([right, c[1]], "left", 2)],
    arrows: [arrow(at(-12, 2), at(1, 0), "pass"), arrow(at(-4, -12), at(16, -12), "run"), arrow(at(-2, 12), at(16, 10), "run")],
    cast: {
      bk: { side: "home", at: [left + 1.5, c[1]], keeper: true }, b1: { side: "home", at: at(-20, -6) }, b2: { side: "home", at: at(-20, 6) },
      b3: { side: "home", at: at(-12, 2) }, b4: { side: "home", at: at(-4, -12) }, b5: { side: "home", at: at(-2, 12) }, b6: { side: "home", at: at(1, 0) },
      rk: { side: "away", at: [right - 1.5, c[1]], keeper: true }, r1: { side: "away", at: at(6, -6) }, r2: { side: "away", at: at(7, 7) },
      r3: { side: "away", at: at(-8, 6) }, r4: { side: "away", at: at(-15, -10) }, r5: { side: "away", at: at(-16, 12) }, r6: { side: "away", at: at(-6, -4) },
    },
    ball: "r3",
    steps: [
      { note: "Blå pressar på egen halva och vinner bollen.", ball: "b3", move: { b3: at(-10, 4), r3: at(-11, 7) }, effects: { b3: ["ring"] } },
      { note: "Direkt framåt till den som är längst fram och spelbar.", ball: "b6", move: { b4: at(4, -13), b5: at(6, 12) } },
      { note: "Bollföraren driver mot mitten. Två löper brett, en på djupet.", ms: 1600, move: { b6: at(12, 0), b4: at(18, -10), b5: at(18, 9), r1: at(14, -3), r2: at(16, 4) } },
      { note: "Passning ut i ytan bakom försvararna.", ball: "b4", move: { b4: at(21, -7) } },
      { note: "Avslut inom åtta sekunder.", ball: [right - 0.5, c[1] - 0.8], ms: 700 },
    ],
  });
}

// 15. Quick finishes after a transition, 5 v 5 with keepers.
{
  const c = MID, L = 40, W = 30;
  const left = c[0] - L / 2, right = c[0] + L / 2;
  exercises.push({
    title: "Snabba avslut efter omställning 5 mot 5", part: "finish", minutes: 15, players: 12, area: "40 × 30 m", phase: "scoring",
    ages: ["10-12", "13-15", "16+"], forms: ["5v5", "7v7", "9v9"],
    organisation: "Matchspel 5 mot 5 med målvakter på en plan på 40 × 30 meter. Mål räknas bara om de görs inom tio sekunder efter bollvinst. " +
      "Tränaren räknar högt från bollvinsten och spelar in en ny boll från sidan direkt efter varje avslut, så det blir många lägen.",
    coaching: "Tänk mål direkt vid bollvinst: vad är snabbaste vägen?\nAvsluta så snart läget finns, hellre ett skott för mycket.\nFölj upp skottet: returerna ger mål.\nLaget som tappar: försök vinna tillbaka bollen inom tio sekunder.",
    view: "empty", crop: cropAround(c, 52),
    setup: [area(c, L, W, "#ffffff", 0.06), ...corners(c, L, W), goal([left, c[1]], "right", 1.6), goal([right, c[1]], "left", 1.6)],
    arrows: [arrow(at(4, -4), at(12, -2), "dribble"), arrow(at(13, -2), [right, c[1] - 1], "pass")],
    cast: {
      bk: { side: "home", at: [left + 1, c[1]], keeper: true }, b1: { side: "home", at: at(-10, -6) }, b2: { side: "home", at: at(-10, 6) },
      b3: { side: "home", at: at(4, -4) }, b4: { side: "home", at: at(5, 6) },
      rk: { side: "away", at: [right - 1, c[1]], keeper: true }, r1: { side: "away", at: at(10, -6) }, r2: { side: "away", at: at(10, 6) },
      r3: { side: "away", at: at(0, 1) }, r4: { side: "away", at: at(-5, 4) },
    },
    ball: "r3",
    steps: [
      { note: "Röd tappar bollen i mitten. Tränaren börjar räkna.", ball: "b3", move: { b3: at(2.5, -1.5), r3: at(-0.5, 0.5) }, effects: { b3: ["ring"] } },
      { note: "Snabbaste vägen: driv mot mål direkt.", ms: 1100, move: { b3: at(11, -2), r1: at(13, -4), b4: at(12, 5) } },
      { note: "Skott inom tio sekunder. 4 följer upp för returen.", ball: [right - 0.5, c[1] - 1], ms: 700, move: { b4: at(16, 2) } },
    ],
  });
}

// The migration: each starter's board and details, the board keeping its id.
const sql = (text: string) => `'${text.replace(/'/g, "''")}'`;
const dollar = (json: unknown) => `$json$${JSON.stringify(json)}$json$::jsonb`;
const statements = exercises.map(exercise => {
  const details = {
    part: exercise.part, minutes: exercise.minutes, players: exercise.players, area: exercise.area,
    organisation: exercise.organisation, coaching_points: exercise.coaching, phase: exercise.phase,
    age_classes: exercise.ages, game_forms: exercise.forms,
  };
  if (exercise.area.length > 40 || exercise.organisation.length > 2000 || exercise.coaching.length > 2000) throw new Error(`Too long: ${exercise.title}`);
  const document = { schemaVersion: 1, squad: [], boards: [board(exercise)] };
  return `update core.tactics_shared_items item
set details = ${dollar(details)},
  document = jsonb_set(${dollar(document)}, '{boards,0,id}', coalesce(item.document->'boards'->0->'id', to_jsonb(gen_random_uuid()::text))),
  updated_at = now()
where item.owner_id is null and item.kind = 'exercise' and item.title = ${sql(exercise.title)};`;
});

const header = `-- Tacticsboard's fifteen starters (seeded without boards in 20261214090000)
-- get their boards drawn: the set-up with cones, goals and areas, the
-- pattern as arrows, and a few frames playing it, each with a note. Their
-- details get the players, the area, the coaching points, the age classes
-- and the game forms. Written by ops/tacticsboard_build_starters.ts; the
-- version stays 1, since nobody has had anything but the empty boards.
-- What a coach already started from a starter is a copy and stays as it is.

-- The preview of a board brings its crop too, so that a card shows the part
-- of the pitch an exercise is drawn in (the summaries call this function).
create or replace function internal.tactics_board_preview(document jsonb, target_board_id text)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object('view', board->'view', 'teams', board->'teams', 'crop', board->'crop',
    'objects', coalesce(board->'frames'->0->'objects', '[]'::jsonb))
  from jsonb_array_elements(case when jsonb_typeof(document->'boards') = 'array' then document->'boards' else '[]'::jsonb end)
    with ordinality as item(board, place)
  where target_board_id is null or board->>'id' = target_board_id
  order by place
  limit 1
$$;
revoke all on function internal.tactics_board_preview(jsonb, text) from public, anon, authenticated;
`;

const out = process.argv[2] ?? "C:/Dev/TeamzoneApp/supabase/migrations/20270426090000_tactics_starter_boards.sql";
writeFileSync(out, `${header}\n${statements.join("\n\n")}\n`);
console.log(`Wrote ${exercises.length} starters to ${out}`);
