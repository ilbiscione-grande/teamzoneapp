// Builds "Como under Fàbregas" as a Tacticsboard project file: four boards,
// each a sequence of frames given as changes from the frame before.
import { writeFileSync } from "node:fs";
import { newBoard, newDocument, newFrame, newId } from "file:///C:/Dev/TeamzoneApp/webtools/lib/tactics/document.ts";
import type { Board, Effect, Frame, TacticsObject } from "file:///C:/Dev/TeamzoneApp/webtools/lib/tactics/model.ts";
import { exportProject } from "file:///C:/Dev/TeamzoneApp/webtools/lib/tactics/transfer.ts";

type Key = string; // h1–h11 Como, a1–a11 the opponent
type Spot = [number, number];
type Step = {
  note: string;
  ms?: number;
  move?: Record<Key, Spot>;
  bend?: Record<Key, Spot>;
  ball?: Key;
  effects?: Record<Key | "ball", Effect[]>;
};

// Names only where the sources name the player in the role.
const names: Record<Key, string> = {
  h1: "Butez", h2: "Van der Brempt", h3: "Valle", h6: "Perrone", h8: "Da Cunha",
  h10: "Paz", h7: "Diao", h11: "J. Rodríguez", h9: "Douvikas",
};

function offsetFor(key: Key) {
  // The ball at the feet, on the side the holder plays towards.
  return key.startsWith("h") ? { x: 1.9, y: 0.7 } : { x: -1.9, y: 0.7 };
}

function board(name: string, description: string, start: Record<Key, Spot>, holder: Key, steps: Step[]): Board {
  const ids = new Map<Key, string>(Object.keys(start).map(key => [key, newId()]));
  const ballId = newId();
  let positions = { ...start };
  let holding = holder;
  const frameOf = (step: Step | null): Frame => {
    const objects: TacticsObject[] = Object.entries(positions).map(([key, [x, y]]) => ({
      id: ids.get(key)!, x, y, rotation: 0, locked: false, hidden: false, type: "player",
      side: key.startsWith("h") ? "home" : "away", number: Number(key.slice(1)), name: names[key] ?? null,
      position: null, personId: null, color: key === "h1" ? "#facc15" : key === "a1" ? "#22c55e" : null,
      pathControl: step?.bend?.[key] ? { x: step.bend[key][0], y: step.bend[key][1] } : null,
      effects: step?.effects?.[key] ?? [],
    }) as TacticsObject);
    const [hx, hy] = positions[holding];
    const offset = offsetFor(holding);
    objects.push({
      id: ballId, x: hx + offset.x, y: hy + offset.y, rotation: 0, locked: false, hidden: false, type: "ball",
      attachedTo: ids.get(holding)!, offset, pathControl: null, effects: step?.effects?.ball ?? [],
    } as TacticsObject);
    return { ...newFrame(objects), durationMs: step?.ms ?? 1500, note: "" };
  };
  const frames: Frame[] = [frameOf(null)];
  for (const step of steps) {
    positions = { ...positions, ...(step.move ?? {}) };
    if (step.ball) holding = step.ball;
    frames.push({ ...frameOf(step), note: step.note });
  }
  return {
    ...newBoard(name, "Como", "Motståndare"), description, showNames: true,
    teams: { home: { name: "Como", color: "#1d4ed8", numberColor: "#ffffff" }, away: { name: "Motståndare", color: "#dc2626", numberColor: "#ffffff" } },
    frames,
  };
}

// Como in possession, 4-2-3-1, against a 4-4-2 mid-block; Como attack to the right.
const como: Record<Key, Spot> = {
  h1: [5, 34], h5: [16, 22], h4: [16, 46], h3: [24, 8], h2: [24, 60], h6: [25, 30], h8: [27, 40],
  h10: [42, 38], h11: [46, 6], h7: [46, 62], h9: [59, 34],
};
const midBlock: Record<Key, Spot> = {
  a1: [99, 34], a9: [36, 28], a10: [36, 41], a11: [47, 11], a6: [47, 28], a8: [47, 40], a7: [47, 57],
  a2: [61, 11], a5: [61, 27], a4: [61, 41], a3: [61, 57],
};
// After the drop: the six between the centre backs, full backs high, wingers inside.
// The opponent stands in its block in every board where Como has the ball.
Object.assign(como, midBlock);
const threeAtBack: Record<Key, Spot> = {
  ...como, h6: [14, 34], h5: [16, 14], h4: [16, 54], h3: [42, 5], h2: [42, 63], h11: [50, 20], h7: [50, 48],
};

const boards: Board[] = [];

boards.push(board("1. Uppspel med tillfällig trebackslinje",
  "Como bygger upp i 4-2-3-1. En av de två sexorna (här Perrone) faller ner mellan mittbackarna och gör en tillfällig trebackslinje. " +
  "Då kan båda ytterbackarna gå högt och brett, yttrarna går in i ytorna och Da Cunha blir ensam sexa. Mot två forwards har Como tre mot två längst bak: " +
  "den yttre mittbacken är fri och kan bära bollen tills någon kliver. Como låg fyra i Serie A på djupledspassningar 2024/25. " +
  "Risk som analyserna lyfter: tappar man bollen här står mittbackarna brett och mitten är öppen.",
  como, "h5", [
    {
      note: "Perrone faller ner mellan mittbackarna, som går isär. Ytterbackarna går högt och brett, yttrarna in i ytorna.",
      ms: 1600, move: { h6: [14, 34], h5: [16, 14], h4: [16, 54], h3: [42, 5], h2: [42, 63], h11: [50, 20], h7: [50, 48], a9: [33, 26], a10: [33, 42] },
      effects: { h6: ["arrow"], h3: ["arrow"], h2: ["arrow"], h11: ["arrow"], h7: ["arrow"] },
    },
    {
      note: "Tre mot två längst bak: vänstra mittbacken (5) är fri och bär bollen in i ytan. Deras ytter (11) måste kliva.",
      ms: 1600, move: { h5: [28, 14], a11: [34, 13] }, effects: { h5: ["arrow", "ring"], a11: ["arrow"] },
    },
    {
      note: "När yttern kliver är Rodríguez fri i ytan mellan deras mittfält och backlinje.",
      ms: 1100, ball: "h11", move: { h11: [52, 21] }, effects: { ball: ["trail"], h11: ["ring"] },
    },
    {
      note: "Rodríguez vänder upp och spelar djupledspassningen. Douvikas löper mellan mittback och ytterback.",
      ms: 1500, ball: "h9", move: { h9: [74, 22], h10: [62, 34] }, bend: { h9: [66, 30] },
      effects: { h9: ["arrow"], ball: ["trail"] },
    },
  ]));

boards.push(board("2. Falsk nia och Paz mellan linjerna",
  "Douvikas faller ner från backlinjen till mittfältet som en falsk nia. Då blir det två mot en mot deras sexa, och deras mittback måste välja: följa med eller släppa honom. " +
  "Valle (3) går in och binder mittbacken på sin sida. Nico Paz rör sig i högra ytan, kombinerar med en vägg och tar sig in mellan linjerna. " +
  "Därifrån växlar Como spelet till yttern på andra kanten, som får ett mot ett.",
  { ...threeAtBack, h3: [42, 5] }, "h4", [
    {
      note: "Douvikas faller ner mellan linjerna. Valle går in och binder deras mittback, Rodríguez går ut på kanten.",
      ms: 1400, move: { h9: [52, 31], h3: [56, 18], h11: [52, 5] }, bend: { h3: [52, 8] },
      effects: { h9: ["arrow"], h3: ["arrow"], h11: ["arrow"] },
    },
    {
      note: "Mittbacken (4) spelar förbi deras mittfält direkt in i Douvikas.",
      ms: 1100, ball: "h9", effects: { ball: ["trail"], h9: ["ring"] },
    },
    {
      note: "Douvikas lägger av till Paz i högra ytan, som tar emot vänd framåt.",
      ms: 1100, ball: "h10", move: { h10: [53, 45] }, effects: { ball: ["trail"], h10: ["ring"] },
    },
    {
      note: "Paz växlar spelet till Rodríguez på bortre kanten. Deras backlinje har dragits mot bollen.",
      ms: 1500, ball: "h11", move: { h11: [60, 6], a2: [63, 14], a5: [62, 30] }, effects: { ball: ["trail"], h11: ["zoom"] },
    },
    {
      note: "Rodríguez går ett mot ett mot ytterbacken, Douvikas och Paz fyller boxen.",
      ms: 1600, move: { h11: [78, 14], a2: [74, 15], h9: [86, 30], h10: [78, 38] },
      bend: { h11: [70, 6] }, effects: { h11: ["arrow", "zoom"], h9: ["arrow"], h10: ["arrow"] },
    },
  ]));

boards.push(board("3. Yttern går in – ytterbacken tar ytan",
  "Comos yttrar går in i mitten i det högre uppspelet. Följer motståndarnas ytterback med blir det tomt utanför honom, och där kommer Comos ytterback (Van der Brempt) i fart. " +
  "Ofta är 8–9 spelare centralt och 1–2 breda: korta avstånd, många passningsalternativ och nära till återerövring om bollen går förlorad. " +
  "Slutet är ofta ett inspel bakåt till en spelare som kommer i ytan utanför straffområdet. Följer inte ytterbacken med inåt får yttern bollen fritt mellan linjerna i stället.",
  { ...threeAtBack, h7: [52, 62], h2: [38, 60], h8: [29, 35] }, "h8", [
    {
      note: "Diao går in i ytan. Deras ytterback följer med – det blir tomt utanför.",
      ms: 1300, move: { h7: [57, 46], a3: [60, 49] }, effects: { h7: ["arrow"], a3: ["arrow"] },
    },
    {
      note: "Van der Brempt springer in i ytan och Da Cunha spelar bakom.",
      ms: 1400, ball: "h2", move: { h2: [70, 62] }, bend: { h2: [56, 64] }, effects: { h2: ["arrow", "ring"], ball: ["trail"] },
    },
    {
      note: "Van der Brempt bär in mot linjen. Douvikas attackerar första stolpen, Paz kommer i ytan utanför straffområdet.",
      ms: 1500, move: { h2: [86, 58], h9: [92, 30], h10: [83, 38], a4: [90, 36], a3: [82, 55] },
      effects: { h2: ["arrow"], h9: ["arrow"], h10: ["arrow"] },
    },
    {
      note: "Inspel bakåt till Paz, som skjuter från straffområdeslinjen.",
      ms: 1000, ball: "h10", effects: { ball: ["trail"], h10: ["ring", "zoom"] },
    },
  ]));

// Out of possession: the opponent builds from the back (attacking to the left), Como in a 4-4-2.
const press: Record<Key, Spot> = {
  a1: [100, 34], a5: [89, 22], a4: [89, 46], a2: [80, 6], a3: [80, 62], a6: [72, 29], a8: [72, 40],
  a7: [60, 8], a11: [60, 60], a10: [58, 34], a9: [48, 34],
  h9: [66, 30], h10: [66, 40], h11: [52, 12], h6: [50, 28], h8: [50, 40], h7: [52, 56],
  h3: [36, 10], h5: [34, 26], h4: [34, 42], h2: [36, 58], h1: [8, 34],
};

boards.push(board("4. Pressen i 4-4-2 – tvinga ut bollen",
  "Utan boll blir Como ett 4-4-2: Paz går upp bredvid nian, mittfältet blir fyra och smalt. Nian pressar mittbacken med en vinklad löpning som stänger passningen till andra mittbacken och styr bollen mot kanten. " +
  "När bollen går ut är det signalen: närmsta yttern pressar längs linjen, ytterbacken kliver på deras ytter, en av sexorna hoppar upp på deras sexa och bortre yttern går in i mitten. " +
  "Como låg högt i Serie A på pressintensitet men lågt på bollbrytningar – de går hellre på personen än står och läser.",
  press, "a5", [
    {
      note: "Douvikas pressar mittbacken i en båge som stänger passningen till andra mittbacken. Paz tar deras sexa.",
      ms: 1400, move: { h9: [82, 25], h10: [74, 32] }, bend: { h9: [82, 34] }, effects: { h9: ["arrow"], h10: ["arrow"] },
    },
    {
      note: "Bollen går ut till ytterbacken – det är signalen att pressa.",
      ms: 1100, ball: "a2", effects: { ball: ["trail"] },
    },
    {
      note: "Rodríguez pressar längs linjen, Valle kliver på deras ytter, Perrone hoppar upp på deras åtta och Diao går in i mitten.",
      ms: 1400,
      move: { h11: [75, 8], h3: [58, 9], h6: [68, 38], h7: [56, 40], h9: [82, 18], h8: [54, 33], h5: [40, 24], h4: [40, 40], h2: [44, 54] },
      bend: { h11: [66, 15] },
      effects: { h11: ["arrow"], h3: ["arrow"], h6: ["arrow"], h7: ["arrow"], a2: ["ring"] },
    },
    {
      note: "Ytterbacken är instängd mot linjen utan passningsväg. Rodríguez vinner bollen.",
      ms: 900, ball: "h11", move: { a2: [78, 7] }, effects: { h11: ["ring"] },
    },
    {
      note: "Direkt framåt: Paz löper in i straffområdet och får bollen.",
      ms: 1300, ball: "h10", move: { h10: [88, 26], h9: [92, 36] }, bend: { h10: [82, 24] },
      effects: { h10: ["arrow", "zoom"], ball: ["trail"] },
    },
  ]));

const document = { ...newDocument(), boards };
writeFileSync(process.argv[2], exportProject("Como under Fàbregas", "education", document));
console.log(boards.map(item => `${item.name}: ${item.frames.length} frames`).join("\n"));
