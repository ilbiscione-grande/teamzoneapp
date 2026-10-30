"use client";

// 3D as one picture, for the video and the PDF. On screen the browser tilts
// the ground's canvas, which nothing can record; here the flat ground is
// drawn tilted onto a canvas row by row (tilted about a line across, each
// row of the ground is one row of the picture, only narrower or wider), the
// sky behind it and the upright figures and stands over it.
import Konva from "konva";
import type { Point } from "../../../lib/tactics/model.ts";
import { groundRow } from "../../../lib/tactics/projection.ts";

/** The same sky as the board's in 3D (tactics.css). */
const SKY: [number, string][] = [[0, "#0b1424"], [0.38, "#1e3a5f"], [1, "#0b1220"]];

/** The canvases to put together; their sizes are read when drawn, so a zoom while recording is followed. */
export type TiltedSources = {
  /** The flat ground's layers, bottom first, at `ratio` canvas pixels per board pixel, `offset` board pixels past the frame's top left. */
  ground: { canvas: HTMLCanvasElement; ratio: number }[];
  offset: Point;
  /** What stands up, over it: the frame's size at any sharpness. */
  figures: { canvas: HTMLCanvasElement }[];
  /** The frame in board pixels. */
  width: number;
  height: number;
};

/** The canvases of a Konva stage's layers, bottom first, with their sharpness. */
export const layerCanvases = (stage: Konva.Stage | null) =>
  stage?.getLayers().map(layer => ({ canvas: layer.getNativeCanvasElement(), ratio: layer.getCanvas().getPixelRatio() })) ?? [];

/** Draws the tilted board over the whole of the context's canvas. */
export function drawTilted(context: CanvasRenderingContext2D, { ground, offset, figures, width, height }: TiltedSources) {
  const { width: outWidth, height: outHeight } = context.canvas;
  const k = outHeight / height;
  const sky = context.createLinearGradient(0, 0, 0, outHeight);
  for (const [stop, colour] of SKY) sky.addColorStop(stop, colour);
  context.fillStyle = sky;
  context.fillRect(0, 0, outWidth, outHeight);
  context.imageSmoothingEnabled = true;
  for (let row = 0; row < outHeight; row++) {
    const at = groundRow((row + 0.5) / k, width, height);
    if (!at) continue;
    for (const { canvas, ratio } of ground) {
      const source = Math.floor((at.y + offset.y) * ratio);
      if (source < 0 || source >= canvas.height) continue;
      const left = -offset.x, right = canvas.width / ratio - offset.x;
      const x0 = width / 2 + (left - width / 2) * at.scale, x1 = width / 2 + (right - width / 2) * at.scale;
      context.drawImage(canvas, 0, source, canvas.width, 1, x0 * k, row, (x1 - x0) * k, 1);
    }
  }
  for (const { canvas } of figures) context.drawImage(canvas, 0, 0, outWidth, outHeight);
}

/** Where the board on screen keeps what the video needs in 3D: the figures' stage and how far the ground's canvas reaches past the frame. */
export const tiltHolder: { figures: Konva.Stage | null; offset: Point } = { figures: null, offset: { x: 0, y: 0 } };
