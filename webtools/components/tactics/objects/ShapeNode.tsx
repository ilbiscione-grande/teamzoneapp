"use client";

// Areas and text: a rectangle or ellipse marking a zone, and a text label
// that keeps reading upright on a turned pitch.
import { Ellipse, Group, Label, Rect, Tag, Text } from "react-konva";
import type { ShapeObject, TextObject } from "../../../lib/tactics/model.ts";
import { nodeRef, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";

const alpha = (hex: string, opacity: number) => {
  const value = hex.replace("#", "");
  const [r, g, b] = [0, 2, 4].map(i => parseInt(value.slice(i, i + 2), 16));
  return `rgba(${r},${g},${b},${opacity})`;
};

export function ShapeNode({ item }: { item: ShapeObject }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  const style = {
    stroke: item.color, strokeWidth: 0.2, fill: alpha(item.color, item.fill * 0.6),
    dash: item.dashed ? [0.9, 0.6] : undefined,
  };
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} rotation={item.rotation} {...drag}>
      {item.type === "rect"
        ? <Rect width={item.width} height={item.height} offsetX={item.width / 2} offsetY={item.height / 2} cornerRadius={0.4} {...style} />
        : <Ellipse radiusX={item.width / 2} radiusY={item.height / 2} {...style} />}
    </Group>
  );
}

export function TextNode({ item, upright }: { item: TextObject; upright: number }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} rotation={item.rotation + upright} {...drag}>
      <Label>
        {item.background && <Tag fill="rgba(15,23,38,0.78)" cornerRadius={0.4} />}
        <Text text={item.text} fontSize={item.size} fontStyle="bold" fill={item.color} padding={item.background ? 0.45 : 0} />
      </Label>
    </Group>
  );
}
