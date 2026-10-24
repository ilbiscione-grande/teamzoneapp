import assert from "node:assert/strict";
import { test } from "node:test";
import { ATTACH_DISTANCE, ballHolders, ballPosition, dropBall, settleBalls } from "../lib/tactics/ball.ts";
import { applyFormation, createObject, createPlayer, nextNumber, normalizeDocument, objectLabel, newBoard, restack, updateFrame } from "../lib/tactics/document.ts";
import { formationPositions, formations, parseFormation } from "../lib/tactics/formations.ts";
import { fitView, pitchToFrame, viewRect, zoomAround } from "../lib/tactics/geometry.ts";
import { emptyHistory, HISTORY_LIMIT, record, redo, undo } from "../lib/tactics/history.ts";
import type { BallObject, ProjectDocument, TacticsObject } from "../lib/tactics/model.ts";
import { boardsForTemplate, boardsFromTemplate, copyBoard, starterBoard, starterSets } from "../lib/tactics/templates.ts";

const near = (a: number, b: number) => assert.ok(Math.abs(a - b) < 1e-9, `${a} ≈ ${b}`);

test("a wide frame shows the pitch as it is, a tall one turns it a quarter", () => {
  const rect = viewRect("full");
  const wide = fitView(rect, 1130, 760);
  assert.equal(wide.rotation, 0);
  const corner = pitchToFrame({ x: rect.x, y: rect.y }, wide);
  const far = pitchToFrame({ x: rect.x + rect.width, y: rect.y + rect.height }, wide);
  assert.ok(corner.x >= -1e-9 && corner.y >= -1e-9 && far.x <= 1130 + 1e-9 && far.y <= 760 + 1e-9, "fits");
  const tall = fitView(rect, 390, 700);
  assert.equal(tall.rotation, -90);
  // Turned: the home goal (x = 0) at the foot, attacking upwards; the touchline y = 0 on the left.
  const goal = pitchToFrame({ x: 0, y: 34 }, tall);
  const other = pitchToFrame({ x: 105, y: 34 }, tall);
  assert.ok(goal.y > other.y);
  near(goal.x, other.x);
  assert.ok(pitchToFrame({ x: 52, y: 0 }, tall).x < pitchToFrame({ x: 52, y: 68 }, tall).x);
  const topLeft = pitchToFrame({ x: rect.x + rect.width, y: rect.y }, tall);
  const bottomRight = pitchToFrame({ x: rect.x, y: rect.y + rect.height }, tall);
  assert.ok(topLeft.x >= -1e-9 && topLeft.y >= -1e-9 && bottomRight.x <= 390 + 1e-9 && bottomRight.y <= 700 + 1e-9, "fits");
  // Half views show their half.
  assert.ok(viewRect("attack").x > 45 && viewRect("defend").x < 0 && viewRect("attack").width < 61);
});

test("zooming keeps the point under the fingers in place", () => {
  const view = zoomAround({ x: 0, y: 0, scale: 1 }, 2, { x: 100, y: 50 });
  assert.deepEqual(view, { scale: 2, x: -100, y: -50 });
  assert.equal(zoomAround({ x: 0, y: 0, scale: 1 }, 100, { x: 0, y: 0 }).scale, 4, "clamped");
});

const objects = (): TacticsObject[] => [
  createPlayer({ x: 50, y: 30 }, "home", []),
  { ...createPlayer({ x: 70, y: 30 }, "away", []), id: "away-1" },
];

test("the ball sticks where it is dropped by a player and follows them", () => {
  const items = objects();
  const player = items[0];
  const ball = createObject("ball", { x: 0, y: 0 }) as BallObject;
  // Dropped just right of the player: on the right edge.
  const stuck = dropBall(ball, { x: 52, y: 30 }, items);
  assert.equal(stuck.attachedTo, player.id);
  near(stuck.offset!.x, ATTACH_DISTANCE);
  near(stuck.offset!.y, 0);
  near(stuck.x, 50 + ATTACH_DISTANCE);
  // Too far from anyone: loose.
  assert.equal(dropBall(ball, { x: 60, y: 30 }, items).attachedTo, null);
  // Not attaching when told not to.
  assert.equal(dropBall(ball, { x: 52, y: 30 }, items, false).attachedTo, null);
  // The player moves; the ball keeps its place on the edge.
  const moved = items.map(item => item.id === player.id ? { ...item, x: 10, y: 10 } : item);
  const settled = settleBalls([...moved, stuck]);
  const followed = settled[2] as BallObject;
  near(followed.x, 10 + ATTACH_DISTANCE);
  near(ballPosition(followed, settled).y, 10);
  // The player goes; the ball comes loose where it was.
  const loose = settleBalls([items[1], followed])[1] as BallObject;
  assert.equal(loose.attachedTo, null);
});

test("formations place the goalkeeper and the lines on the own half", () => {
  const home = formationPositions(formations["4-3-3"], "home");
  assert.equal(home.length, 11);
  assert.ok(home.every(point => point.x <= 52.5));
  const away = formationPositions(formations["4-3-3"], "away");
  assert.ok(away.every(point => point.x >= 52.5));
  assert.deepEqual(parseFormation(" 4 - 4 - 2 "), [4, 4, 2]);
  assert.equal(parseFormation("4-4-4"), null, "eleven outfield players is too many");
  assert.equal(parseFormation("hej"), null);
  // Existing players move; missing ones come from the squad, then numbered.
  const squad = [{ personId: "p1", name: "Alva", number: 9, position: "ST" }];
  const placed = applyFormation(objects(), "home", [2, 1, 1], squad);
  const home5 = placed.filter(item => item.type === "player" && item.side === "home");
  assert.equal(home5.length, 5);
  assert.ok(home5.some(item => item.type === "player" && item.name === "Alva" && item.number === 9 && item.position === "ST"));
});

test("numbers, labels, order and frame updates", () => {
  const board = newBoard("Tavla");
  const items = objects();
  assert.equal(nextNumber(items, "home"), 2);
  assert.equal(objectLabel(items[0], board), "#1 Hemma");
  assert.equal(objectLabel({ ...items[0], label: "Kapten" } as TacticsObject, board), "Kapten");
  assert.equal(objectLabel({ ...items[0], name: "Alva", position: "MV" } as TacticsObject, board), "#1 Alva (MV)");
  const cone = createObject("cone", { x: 1, y: 1 });
  assert.deepEqual(restack([...items, cone], cone.id, -1).map(item => item.id), [items[0].id, cone.id, items[1].id]);
  const document: ProjectDocument = { schemaVersion: 1, squad: [], boards: [{ ...board, frames: [{ ...board.frames[0], objects: items }] }] };
  const next = updateFrame(document, board.id, 0, current => current.filter(item => item.id !== "away-1"));
  assert.equal(next.boards[0].frames[0].objects.length, 1);
  assert.equal(document.boards[0].frames[0].objects.length, 2, "the old document is untouched");
  // A document from the server is made whole.
  const normalized = normalizeDocument({ boards: [{ id: "b", name: "Gammal" }] });
  assert.equal(normalized.boards[0].frames.length, 1);
  assert.equal(normalized.boards[0].teams.home.name, "Hemma");
  assert.equal(normalizeDocument(null).boards.length, 1);
});

test("undo and redo step through whole documents", () => {
  const a = normalizeDocument(null), b = normalizeDocument(null), c = normalizeDocument(null);
  let history = record(record(emptyHistory(), a), b);
  const back = undo(history, c)!;
  assert.equal(back.document, b);
  history = back.history;
  const forward = redo(history, b)!;
  assert.equal(forward.document, c);
  assert.equal(undo(emptyHistory(), a), null);
  let long = emptyHistory();
  for (let i = 0; i < HISTORY_LIMIT + 5; i++) long = record(long, a);
  assert.equal(long.past.length, HISTORY_LIMIT);
});

test("a share link's QR code has its finder squares and draws as runs", async () => {
  const { qrModules, qrPath } = await import("../lib/tactics/qr.ts");
  const modules = qrModules("https://teamzoneapp-webtools--teamzoneapp-b02a2.europe-west4.hosted.app/delad/0a1518d7a70b4ef3aba659a2d17de366a7d836b8");
  const size = modules.length;
  assert.ok(size >= 21 && (size - 17) % 4 === 0, "a QR size");
  // The three finder patterns: dark corners with a light ring inside.
  for (const [r, c] of [[0, 0], [0, size - 7], [size - 7, 0]]) {
    assert.equal(modules[r][c], true);
    assert.equal(modules[r + 1][c + 1], false);
    assert.equal(modules[r + 3][c + 3], true);
  }
  const path = qrPath([[true, true, false, true]], 0);
  assert.equal(path, "M0 0h2v1h-2zM3 0h1v1h-1z");
});

test("templates: ready boards, saving without ties and using with new ids", () => {
  const lineup = starterBoard(starterSets.match.find(item => item.key === "lineup")!, "P2012");
  const players = lineup.frames[0].objects.filter(item => item.type === "player");
  assert.equal(players.length, 11);
  assert.equal(lineup.teams.home.name, "P2012");
  assert.ok(lineup.frames[0].objects.some(item => item.type === "ball"));
  const corner = starterBoard(starterSets.match.find(item => item.key === "corner-for")!);
  assert.equal(corner.view, "attack");
  assert.ok(Object.values(starterSets).every(set => set.every(item => !item.formation || formations[item.formation])));

  const tied = { ...lineup, frames: [{ ...lineup.frames[0], objects: lineup.frames[0].objects.map(item => item.type === "player" ? { ...item, personId: "p1", name: "Alva", position: "MV" } : item) }] };
  const saved = boardsForTemplate([tied], false);
  const savedPlayer = saved[0].frames[0].objects.find(item => item.type === "player");
  assert.deepEqual(savedPlayer && savedPlayer.type === "player" && [savedPlayer.personId, savedPlayer.name, savedPlayer.position], [null, null, "MV"]);
  const kept = boardsForTemplate([tied], true)[0].frames[0].objects.find(item => item.type === "player");
  assert.equal(kept && kept.type === "player" && kept.name, "Alva");

  const used = boardsFromTemplate(saved, "F2013");
  assert.notEqual(used[0].id, saved[0].id);
  assert.notEqual(used[0].frames[0].id, saved[0].frames[0].id);
  assert.equal(used[0].teams.home.name, "F2013");
  assert.equal(used[0].frames[0].objects.length, saved[0].frames[0].objects.length);
  const copy = copyBoard(lineup);
  assert.equal(copy.name, "Uppställning (kopia)");
  assert.notEqual(copy.id, lineup.id);
});

test("a player holding the ball: attached and at the player's feet", () => {
  const player = createPlayer({ x: 50, y: 30 }, "home", []);
  const ball = { ...createObject("ball", { x: 50 + ATTACH_DISTANCE, y: 30 }), attachedTo: player.id, offset: { x: ATTACH_DISTANCE, y: 0 } } as BallObject;
  assert.deepEqual([...ballHolders([player, ball])], [player.id]);
  assert.equal(ballHolders([player, { ...ball, x: 70 }]).size, 0, "on its way in a pass");
  assert.equal(ballHolders([player, { ...ball, attachedTo: null }]).size, 0);
});

test("a board saved in the library: no ties to players, its details beside it", async () => {
  const { boardsFromLibrary, exerciseItem, exerciseJson, lessonItem, libraryKindsFor, planItem } = await import("../lib/tactics/library.ts");
  const board = { ...newBoard("Rondo"), description: "Fem mot två i 10x10 m",
    exercise: { part: "warmup" as const, minutes: 12, players: 7, area: "10x10 m", coachingPoints: "Kroppsställning",
      phase: "regaining" as const, ageClasses: ["10-12" as const], gameForms: ["5v5" as const] } };
  const player = { ...createPlayer({ x: 10, y: 10 }, "home", []), personId: "p1", name: "Anna" };
  const withPlayer = { ...board, frames: [{ ...board.frames[0], objects: [player] }] };

  const exercise = exerciseItem(withPlayer, "Rondo 5 mot 2");
  assert.equal(exercise.kind, "exercise");
  assert.deepEqual(exercise.details, { part: "warmup", minutes: 12, players: 7, area: "10x10 m", organisation: "Fem mot två i 10x10 m",
    coaching_points: "Kroppsställning", phase: "regaining", age_classes: ["10-12"], game_forms: ["5v5"] });
  const saved = exercise.document.boards[0].frames[0].objects[0] as typeof player;
  assert.deepEqual([saved.personId, saved.name, exercise.document.boards[0].exercise], [null, null, undefined]);

  // A pass keeps each board's details in order; back on boards they return.
  const second = { ...newBoard("Press"), exercise: { ...board.exercise, part: "main" as const, minutes: 20 } };
  const pass = planItem([withPlayer, second], "Press", "Återerövring", "Vinna bollen högt");
  assert.deepEqual(pass.details, { theme: "Återerövring", goal: "Vinna bollen högt", exercises: [exerciseJson(withPlayer), exerciseJson(second)] });
  const back = boardsFromLibrary({ kind: "plan", details: pass.details } as never, pass.document.boards);
  assert.deepEqual(back.map(item => [item.exercise?.part, item.exercise?.minutes]), [["warmup", 12], ["main", 20]]);
  assert.equal(lessonItem([board], "Spelidén").kind, "lesson");

  // A board without details is a main-part exercise of 15 minutes; minutes stay within bounds.
  assert.deepEqual([exerciseJson(newBoard("X")).part, exerciseJson(newBoard("X")).minutes], ["main", 15]);
  assert.equal(exerciseJson({ ...board, exercise: { ...board.exercise, minutes: 999 } }).minutes, 240);
  // TBL-17: a match's boards are not saved in the library.
  assert.deepEqual(libraryKindsFor.match, []);
  assert.deepEqual(libraryKindsFor.training, ["exercise", "plan"]);
});
