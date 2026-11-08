"use client";

// Areas and text: a rectangle or ellipse marking a zone (filled or striped, glowing at its edge), and a text label
// that turns with the pitch, as the rest of the drawing does (a phone shows it turned). A resized text box wraps its
// text; the letters keep their own size. With measuring on, an area shows
// its sides and the ground it covers.
import Konva from "konva";
import { Ellipse, Group, Label, Rect, Tag, Text } from "react-konva";
import { TEXT_LINE_HEIGHT, textBackground, textFontStyle, type ShapeObject, type TextObject } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { shapeMeasure } from "../../../lib/tactics/measure.ts";
import type { Context } from "konva/lib/Context";
import { AreaFill } from "./AreaFill.tsx";
import { look } from "./look.tsx";
import { MeasureTag } from "./MeasureTag.tsx";
import { nodeRef, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";

export function ShapeNode({ item, measure = false, upright = 0 }: { item: ShapeObject & Rendered; measure?: boolean; upright?: number }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  const [width, height] = [item.width, item.height];
  const edge = { stroke: item.color, strokeWidth: 0.25, dash: item.dashed ? [0.9, 0.6] : undefined, perfectDrawEnabled: false };
  // A soft glow outside the edge, as television marks an area.
  const glow = { stroke: item.color, strokeWidth: 0.8, opacity: 0.25, listening: false, perfectDrawEnabled: false };
  const outline = (context: Context) => {
    context.beginPath();
    if (item.type === "rect") context.roundRect(-width / 2, -height / 2, width, height, 0.4);
    else context.ellipse(0, 0, width / 2, height / 2, 0, 0, Math.PI * 2);
    context.closePath();
  };
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} rotation={item.rotation} {...look(item)} {...drag}>
      <AreaFill box={{ x: -width / 2, y: -height / 2, width, height }} outline={outline} color={item.color} fill={item.fill} pattern={item.pattern} />
      {item.type === "rect"
        ? <><Rect width={width} height={height} offsetX={width / 2} offsetY={height / 2} cornerRadius={0.4} {...glow} />
          <Rect width={width} height={height} offsetX={width / 2} offsetY={height / 2} cornerRadius={0.4} fill="rgba(0,0,0,0)" {...edge} /></>
        : <><Ellipse radiusX={width / 2} radiusY={height / 2} {...glow} />
          <Ellipse radiusX={width / 2} radiusY={height / 2} fill="rgba(0,0,0,0)" {...edge} /></>}
      {measure && <MeasureTag at={{ x: 0, y: 0 }} text={shapeMeasure(item)} upright={upright} turn={item.rotation} />}
    </Group>
  );
}

/** A box resized to fit the text stays that high, but never cuts lines off: the text then takes the room it needs. */
function boxHeight(item: TextObject, font: { fontSize: number; fontStyle: string; lineHeight: number; padding: number }) {
  if (item.height == null) return undefined;
  const needed = new Konva.Text({ ...font, text: item.text, width: item.width ?? undefined, wrap: "word" });
  const height = needed.height();
  needed.destroy();
  return item.height > height ? item.height : undefined;
}

export function TextNode({ item }: { item: TextObject & Rendered }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  const font = { fontSize: item.size, fontStyle: textFontStyle(item), lineHeight: TEXT_LINE_HEIGHT, padding: item.background ? 0.45 : 0 };
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} rotation={item.rotation} {...look(item)} {...drag}>
      <Label>
        {item.background && <Tag fill={item.backgroundColor ?? textBackground.color} opacity={item.backgroundOpacity ?? textBackground.opacity} cornerRadius={0.4} />}
        <Text {...font} text={item.text} fill={item.color}
          width={item.width ?? undefined} height={boxHeight(item, font)} wrap="word" align={item.align ?? "left"} />
      </Label>
    </Group>
  );
}
