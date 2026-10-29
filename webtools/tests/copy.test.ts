import assert from "node:assert/strict";
import { test } from "node:test";
import { dropBall } from "../lib/tactics/ball.ts";
import { copyObjects } from "../lib/tactics/copy.ts";
import { createObject, createPlayer, newBoard, newDocument, newFrame } from "../lib/tactics/document.ts";
import type { BallObject, ProjectDocument, TacticsObject } from "../lib/tactics/model.ts";

function project(frames: TacticsObject[][], other: TacticsObject[] = []): ProjectDocument {
  const document = newDocument("Inspark");
  const second = { ...newBoard("Avspark"), frames: [newFrame(other), newFrame([])] };
  return { ...document, boards: [{ ...document.boards[0], frames: frames.map(objects => newFrame(objects)) }, second] };
}

test("copied to another frame of the board, objects keep their ids; one already there is set as copied, keeping its own effects", () => {
  const player = createPlayer({ x: 10, y: 10 }, "home", []);
  const cone = { ...createObject("cone", { x: 5, y: 5 }), effects: ["pulse"] } as TacticsObject;
  const there = { ...player, x: 30, y: 30, effects: ["trail"], pathControl: { x: 20, y: 40 } } as TacticsObject;
  const document = project([[player, cone], [there]]);
  const board = document.boards[0];
  const result = copyObjects(document, { boardId: board.id, frameIndex: 0 }, [player.id, cone.id], { boardId: board.id, frameIndex: 1 });
  assert.deepEqual(result.ids, [player.id, cone.id]);
  assert.equal(result.replaced, 1);
  const objects = result.document.boards[0].frames[1].objects;
  assert.equal(objects.length, 2);
  const moved = objects.find(item => item.id === player.id)!;
  assert.deepEqual([moved.x, moved.y], [10, 10]);
  assert.deepEqual(moved.effects, ["trail"], "the frame's own effects stay");
  assert.deepEqual(moved.pathControl, { x: 20, y: 40 });
  assert.deepEqual(objects.find(item => item.id === cone.id)!.effects, [], "effects do not go along");
  assert.deepEqual(result.document.boards[0].frames[0].objects, [player, cone], "the source is unchanged");
});

test("copied to another board's first frame, objects get new ids and a ball stays with its player", () => {
  const player = createPlayer({ x: 10, y: 10 }, "home", []);
  const ball = dropBall(createObject("ball", { x: 11, y: 10 }) as BallObject, { x: 11, y: 10 }, [player]);
  assert.equal(ball.attachedTo, player.id);
  const loose = createPlayer({ x: 40, y: 40 }, "away", []);
  const document = project([[player, ball, loose]]);
  const to = { boardId: document.boards[1].id, frameIndex: 0 };
  const result = copyObjects(document, { boardId: document.boards[0].id, frameIndex: 0 }, [player.id, ball.id], to);
  const objects = result.document.boards[1].frames[0].objects;
  assert.equal(objects.length, 2);
  assert.ok(!objects.some(item => item.id === player.id || item.id === ball.id), "new ids");
  const [copiedPlayer, copiedBall] = objects as [TacticsObject, BallObject];
  assert.equal(copiedBall.attachedTo, copiedPlayer.id);
  // Without its player the ball comes loose.
  const alone = copyObjects(document, { boardId: document.boards[0].id, frameIndex: 0 }, [ball.id], to);
  assert.equal((alone.document.boards[1].frames[0].objects[0] as BallObject).attachedTo, null);
});

test("copying to the same frame, or from nowhere, changes nothing", () => {
  const cone = createObject("cone", { x: 5, y: 5 });
  const document = project([[cone], []]);
  const place = { boardId: document.boards[0].id, frameIndex: 0 };
  assert.equal(copyObjects(document, place, [cone.id], place).document, document);
  assert.equal(copyObjects(document, place, [cone.id], { ...place, frameIndex: 9 }).document, document);
});
