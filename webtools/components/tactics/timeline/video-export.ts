"use client";

// The board as a video: it plays from the start while a hidden canvas copies
// the pitch and the objects every screen frame and the browser records it.
// MP4 where the browser makes it (Safari, newer Chrome), else WebM. With a
// crop, only that part of the pitch is copied, at the crop's own shape; in
// 3D, the part of the tilted picture where the crop shows, players standing in it.
// It stands still for a moment first, so a page showing it has time to load,
// and has a small watermark in the corner.
import { contentHolder, stageHolder } from "../stage/stage-context.ts";
import { drawTilted, layerCanvases, tiltHolder } from "../stage/tilt-picture.ts";
import { create } from "zustand";
import { activeBoard, useEditor } from "../store.ts";
import { drawWatermark } from "./watermark.ts";

/** How long the first frame stands still, and the last. */
const HOLD_FIRST = 500;
const HOLD_LAST = 600;

const TYPES = ["video/mp4;codecs=avc1", "video/mp4", "video/webm;codecs=vp9", "video/webm;codecs=vp8", "video/webm"];

export const canRecord = () =>
  typeof window !== "undefined" && "MediaRecorder" in window && typeof HTMLCanvasElement.prototype.captureStream === "function";

function pickType(): string | undefined {
  return TYPES.find(type => MediaRecorder.isTypeSupported(type));
}

/** How far a recording has come, 0 to 1, while one runs: the play button waits for it. */
export const useRecording = create<{ share: number | null }>(() => ({ share: null }));

/** Plays the board from the start and gives back the recording; null when this browser cannot. */
export async function recordBoard(): Promise<{ blob: Blob; extension: string } | null> {
  useRecording.setState({ share: 0 });
  try { return await record(); } finally { useRecording.setState({ share: null }); }
}

/** The crop's place on the layers' canvases now (the view may zoom while it plays); null without one. */
function cropOnCanvas(crop: { x: number; y: number; width: number; height: number } | null | undefined, ratio: number) {
  const content = contentHolder.current;
  if (!crop || !content) return null;
  const transform = content.getAbsoluteTransform();
  const corners = [[crop.x, crop.y], [crop.x + crop.width, crop.y], [crop.x, crop.y + crop.height], [crop.x + crop.width, crop.y + crop.height]]
    .map(([x, y]) => transform.point({ x, y }));
  const xs = corners.map(point => point.x * ratio), ys = corners.map(point => point.y * ratio);
  return { x: Math.min(...xs), y: Math.min(...ys), width: Math.max(...xs) - Math.min(...xs), height: Math.max(...ys) - Math.min(...ys) };
}

/** Players and goals stand this high, in metres: the top of the crop's part in 3D reaches up to them. */
const STANDING_HEIGHT = 2.6;

/** Where the crop shows in the tilted picture, in its canvas's pixels (ratio a frame pixel), within the frame; null without one. */
function cropTilted(crop: { x: number; y: number; width: number; height: number } | null | undefined, ratio: number, width: number, height: number) {
  const project = tiltHolder.project;
  if (!crop || !project) return null;
  const corners = [[crop.x, crop.y], [crop.x + crop.width, crop.y], [crop.x, crop.y + crop.height], [crop.x + crop.width, crop.y + crop.height]];
  const points = corners.flatMap(([x, y]) => [project({ x, y }), project({ x, y }, STANDING_HEIGHT)]);
  const left = Math.max(0, Math.min(...points.map(point => point.x))), right = Math.min(width, Math.max(...points.map(point => point.x)));
  const top = Math.max(0, Math.min(...points.map(point => point.y))), bottom = Math.min(height, Math.max(...points.map(point => point.y)));
  if (right - left < 8 || bottom - top < 8) return null;
  return { x: left * ratio, y: top * ratio, width: (right - left) * ratio, height: (bottom - top) * ratio };
}

/** A crop's video size: its shape, the longer side 1280 to 1920 pixels. */
function cropSize(width: number, height: number) {
  const long = Math.max(width, height);
  const k = Math.min(1920, Math.max(1280, long)) / long;
  return { width: Math.round(width * k), height: Math.round(height * k) };
}

async function record(): Promise<{ blob: Blob; extension: string } | null> {
  const stage = stageHolder.current;
  const board = activeBoard(useEditor.getState());
  if (!stage || !board || board.frames.length < 2 || !canRecord()) return null;
  // Read again for every copy: layers come and go while it plays (a spotlight, say).
  const layers = () => layerCanvases(stage).map(({ canvas }) => canvas);
  // In 3D the picture is put together from the tilted ground and the figures, at the figures' sharpness.
  const figures = useEditor.getState().tilt ? tiltHolder.figures : null;
  const first = figures ? layerCanvases(figures)[0]?.canvas : layers()[0];
  if (!first) return null;
  const ratio = layerCanvases(stage)[0]?.ratio ?? 1;
  // In 3D the tilted picture is put together whole, at the figures' sharpness, and the crop's part copied from it.
  const whole = figures ? document.createElement("canvas") : null;
  const figureRatio = figures ? first.width / Math.max(1, figures.width()) : 1;
  const area = () => figures
    ? cropTilted(board.crop, figureRatio, figures.width(), figures.height())
    : cropOnCanvas(board.crop, ratio);
  const start = area();
  const { width, height } = start ? cropSize(start.width, start.height) : first;
  const canvas = document.createElement("canvas");
  // Video encoders want even sizes.
  canvas.width = width - (width % 2);
  canvas.height = height - (height % 2);
  const context = canvas.getContext("2d");
  if (!context) return null;
  const picture = () => {
    if (figures && whole) {
      const part = area();
      const target = part ? whole : canvas;
      if (part) {
        const sharp = layerCanvases(figures)[0]?.canvas;
        // Set only when it changes: setting a canvas's size empties and remakes it.
        const w = sharp?.width ?? canvas.width, h = sharp?.height ?? canvas.height;
        if (whole.width !== w) whole.width = w;
        if (whole.height !== h) whole.height = h;
      }
      const into = target.getContext("2d");
      if (!into) return;
      drawTilted(into, { ground: layerCanvases(stage), offset: tiltHolder.offset, figures: layerCanvases(figures), width: figures.width(), height: figures.height() });
      if (part) context.drawImage(whole, part.x, part.y, part.width, part.height, 0, 0, canvas.width, canvas.height);
      return;
    }
    context.fillStyle = "#24603a";
    context.fillRect(0, 0, canvas.width, canvas.height);
    const part = area();
    for (const layer of layers()) {
      if (part) context.drawImage(layer, part.x, part.y, part.width, part.height, 0, 0, canvas.width, canvas.height);
      else context.drawImage(layer, 0, 0);
    }
  };
  const copy = () => {
    picture();
    drawWatermark(context, canvas.width, canvas.height);
  };
  /** Keeps drawing while the board stands still: a canvas that is not drawn on gives the video no frames. */
  const hold = (ms: number) => new Promise<void>(resolve => {
    const start = performance.now();
    const tick = () => { copy(); if (performance.now() - start < ms) requestAnimationFrame(tick); else resolve(); };
    requestAnimationFrame(tick);
  });
  copy();
  const type = pickType();
  const recorder = new MediaRecorder(canvas.captureStream(30), { ...(type ? { mimeType: type } : {}), videoBitsPerSecond: 6_000_000 });
  const chunks: Blob[] = [];
  recorder.ondataavailable = event => { if (event.data.size > 0) chunks.push(event.data); };
  const done = new Promise<void>(resolve => { recorder.onstop = () => resolve(); });

  // From the first frame, once, at the chosen speed.
  const editor = useEditor.getState();
  const loop = editor.loop;
  useEditor.setState({ frameIndex: 0, playhead: 0, loop: false, selection: [] });
  recorder.start(250);
  await hold(HOLD_FIRST);
  useEditor.getState().play();
  await new Promise<void>(resolve => {
    const tick = () => {
      copy();
      const state = useEditor.getState();
      useRecording.setState({ share: Math.min(1, state.playhead / Math.max(1, board.frames.length - 1)) });
      if (state.playing) requestAnimationFrame(tick);
      else resolve();
    };
    requestAnimationFrame(tick);
  });
  await hold(HOLD_LAST);
  recorder.stop();
  await done;
  useEditor.setState({ loop });
  const mime = recorder.mimeType || type || "video/webm";
  return { blob: new Blob(chunks, { type: mime }), extension: mime.includes("mp4") ? "mp4" : "webm" };
}

export function download(blob: Blob, name: string) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}
