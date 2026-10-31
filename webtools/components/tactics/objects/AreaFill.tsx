"use client";

// An area's inside (zones and the space between players): filled evenly, or
// hatched in diagonal stripes as on television, clipped to the area's outline.
// One shape the size of the area's box, so handles round the area fit it.
import type { Context } from "konva/lib/Context";
import { Shape } from "react-konva";
import type { AreaPattern } from "../../../lib/tactics/model.ts";
import { stripes } from "../../../lib/tactics/ribbon.ts";

export const alpha = (hex: string, opacity: number) => {
  const value = hex.replace("#", "");
  const [r, g, b] = [0, 2, 4].map(i => parseInt(value.slice(i, i + 2), 16));
  return `rgba(${r},${g},${b},${opacity})`;
};

/** Between the stripes, in metres. */
const GAP = 1.6;

type Props = {
  /** The box round the area. */
  box: { x: number; y: number; width: number; height: number };
  /** Traces the area's outline, to clip to. */
  outline: (context: Context) => void;
  color: string;
  fill: number;
  pattern?: AreaPattern;
};

export function AreaFill({ box, outline, color, fill, pattern }: Props) {
  if (fill <= 0) return null;
  const striped = pattern === "stripes";
  return (
    <Shape x={box.x} y={box.y} width={box.width} height={box.height} listening={false} perfectDrawEnabled={false}
      sceneFunc={context => {
        const canvas = context._context;
        canvas.save();
        // The outline is traced in the area's own place; this shape sits at the box's corner.
        canvas.translate(-box.x, -box.y);
        outline(context);
        canvas.clip();
        canvas.fillStyle = alpha(color, striped ? fill * 0.22 : fill * 0.6);
        canvas.fillRect(box.x, box.y, box.width, box.height);
        if (striped) {
          canvas.strokeStyle = alpha(color, Math.min(0.95, 0.3 + fill * 0.65));
          canvas.lineWidth = GAP * 0.38;
          canvas.beginPath();
          const [middleX, middleY] = [box.x + box.width / 2, box.y + box.height / 2];
          for (const [x1, y1, x2, y2] of stripes(box.width, box.height, GAP)) {
            canvas.moveTo(middleX + x1, middleY + y1);
            canvas.lineTo(middleX + x2, middleY + y2);
          }
          canvas.stroke();
        }
        canvas.restore();
      }} />
  );
}
