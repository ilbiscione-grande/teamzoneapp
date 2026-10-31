"use client";

// Areas and text: a rectangle or ellipse marking a zone, and a text label
// that keeps reading upright on a turned pitch. A resized text box wraps its
// text; the letters keep their own size. With measuring on, an area shows
// its sides and the ground it covers.
import { Ellipse, Group, Label, Rect, Tag, Text } from "react-konva";
import type { ShapeObject, TextObject } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { shapeMeasure } from "../../../lib/tactics/measure.ts";
import { look } from "./look.tsx";
import { MeasureTag } from "./MeasureTag.tsx";
import { nodeRef, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";

const alpha = (hex: string, opacity: number) => {
  const value = hex.replace("#", "");
  const [r, g, b] = [0, 2, 4].map(i => parseInt(value.slice(i, i + 2), 16));
  return `rgba(${r},${g},${b},${opacity})`;
};

export function ShapeNode({ item, measure = false, upright = 0 }: { item: ShapeObject & Rendered; measure?: boolean; upright?: number }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  const style = {
    stroke: item.color, strokeWidth: 0.2, fill: alpha(item.color, item.fill * 0.6),
    dash: item.dashed ? [0.9, 0.6] : undefined,
  };
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} rotation={item.rotation} {...look(item)} {...drag}>
      {item.type === "rect"
        ? <Rect width={item.width} height={item.height} offsetX={item.width / 2} offsetY={item.height / 2} cornerRadius={0.4} {...style} />
        : <Ellipse radiusX={item.width / 2} radiusY={item.height / 2} {...style} />}
      {measure && <MeasureTag at={{ x: 0, y: 0 }} text={shapeMeasure(item)} upright={upright} turn={item.rotation} />}
    </Group>
  );
}

export function TextNode({ item, upright }: { item: TextObject & Rendered; upright: number }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} rotation={item.rotation + upright} {...look(item)} {...drag}>
      <Label>
        {item.background && <Tag fill="rgba(15,23,38,0.78)" cornerRadius={0.4} />}
        <Text text={item.text} fontSize={item.size} fontStyle="bold" fill={item.color} padding={item.background ? 0.45 : 0}
          width={item.width ?? undefined} height={item.height ?? undefined} wrap="word" />
      </Label>
    </Group>
  );
}
