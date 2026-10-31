"use client";

// One object on the pitch, drawn by its kind.
import type { Board } from "../../../lib/tactics/model.ts";
import { lookOf } from "../../../lib/tactics/pitch-style.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { BallNode } from "./BallNode.tsx";
import { ChainNode } from "./ChainNode.tsx";
import { EquipmentNode } from "./EquipmentNode.tsx";
import { FreehandNode, LineNode } from "./LineNode.tsx";
import { PlayerNode } from "./PlayerNode.tsx";
import { ShapeNode, TextNode } from "./ShapeNode.tsx";

/** objects: all shown, for a line through players to find them; measure: sizes shown (editing). */
export function ObjectNode({ item, board, selected, upright, holding = false, objects = [], measure = false }: {
  item: Rendered; board: Board; selected: boolean; upright: number; holding?: boolean; objects?: Rendered[]; measure?: boolean;
}) {
  switch (item.type) {
    case "player": return <PlayerNode item={item} board={board} selected={selected} upright={upright} holding={holding} />;
    case "ball": return <BallNode item={item} selected={selected} upright={upright} />;
    case "line": return <LineNode item={item} selected={selected} look={lookOf(board.pitch)} measure={measure} upright={upright} />;
    case "freehand": return <FreehandNode item={item} selected={selected} look={lookOf(board.pitch)} measure={measure} upright={upright} />;
    case "rect":
    case "ellipse": return <ShapeNode item={item} measure={measure} upright={upright} />;
    case "chain": return <ChainNode item={item} objects={objects} selected={selected} upright={upright} measure={measure} />;
    case "text": return <TextNode item={item} upright={upright} />;
    default: return <EquipmentNode item={item} />;
  }
}
