"use client";

// One object on the pitch, drawn by its kind.
import type { Board } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { BallNode } from "./BallNode.tsx";
import { EquipmentNode } from "./EquipmentNode.tsx";
import { FreehandNode, LineNode } from "./LineNode.tsx";
import { PlayerNode } from "./PlayerNode.tsx";
import { ShapeNode, TextNode } from "./ShapeNode.tsx";

export function ObjectNode({ item, board, selected, upright, holding = false }: { item: Rendered; board: Board; selected: boolean; upright: number; holding?: boolean }) {
  switch (item.type) {
    case "player": return <PlayerNode item={item} board={board} selected={selected} upright={upright} holding={holding} />;
    case "ball": return <BallNode item={item} selected={selected} />;
    case "line": return <LineNode item={item} selected={selected} />;
    case "freehand": return <FreehandNode item={item} selected={selected} />;
    case "rect":
    case "ellipse": return <ShapeNode item={item} />;
    case "text": return <TextNode item={item} upright={upright} />;
    default: return <EquipmentNode item={item} />;
  }
}
