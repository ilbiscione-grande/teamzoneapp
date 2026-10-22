"use client";

// One object on the pitch, drawn by its kind.
import type { Board, TacticsObject } from "../../../lib/tactics/model.ts";
import { BallNode } from "./BallNode.tsx";
import { EquipmentNode } from "./EquipmentNode.tsx";
import { FreehandNode, LineNode } from "./LineNode.tsx";
import { PlayerNode } from "./PlayerNode.tsx";
import { ShapeNode, TextNode } from "./ShapeNode.tsx";

export function ObjectNode({ item, board, selected, upright }: { item: TacticsObject; board: Board; selected: boolean; upright: number }) {
  switch (item.type) {
    case "player": return <PlayerNode item={item} board={board} selected={selected} upright={upright} />;
    case "ball": return <BallNode item={item} selected={selected} />;
    case "line": return <LineNode item={item} selected={selected} />;
    case "freehand": return <FreehandNode item={item} selected={selected} />;
    case "rect":
    case "ellipse": return <ShapeNode item={item} />;
    case "text": return <TextNode item={item} upright={upright} />;
    default: return <EquipmentNode item={item} />;
  }
}
