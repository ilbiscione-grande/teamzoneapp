"use client";

// A measure on the pitch (lib/tactics/measure.ts): a small dark tag with the
// size in it, reading upright on a turned pitch and never in the way of a tap.
import { Label, Tag, Text } from "react-konva";
import type { Point } from "../../../lib/tactics/model.ts";

const SIZE = 1.5, PAD = 0.35;

/** Centred on the point; turn: the turn of the group it is drawn in, undone. */
export function MeasureTag({ at, text, upright, turn = 0 }: { at: Point; text: string; upright: number; turn?: number }) {
  // About the text's width, to centre it without measuring.
  const width = text.length * SIZE * 0.56 + PAD * 2;
  return (
    <Label x={at.x} y={at.y} rotation={upright - turn} offsetX={width / 2} offsetY={(SIZE + PAD * 2) / 2} listening={false}>
      <Tag fill="rgba(15,23,38,0.85)" cornerRadius={0.35} pointerDirection="none" />
      <Text text={text} fontSize={SIZE} fontStyle="bold" fill="#ffffff" padding={PAD} />
    </Label>
  );
}
