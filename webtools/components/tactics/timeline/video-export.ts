"use client";

// The board as a video: it plays from the start while a hidden canvas copies
// the pitch and the objects every screen frame and the browser records it.
// MP4 where the browser makes it (Safari, newer Chrome), else WebM. With a
// crop, only that part of the pitch is copied, at the crop's own shape.
import { contentHolder, stageHolder } from "../stage/stage-context.ts";
import { drawTilted, layerCanvases, tiltHolder } from "../stage/tilt-picture.ts";
import { create } from "zustand";
import { activeBoard, useEditor } from "../store.ts";

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
  // The crop is drawn flat; in 3D the whole picture is recorded.
  const ratio = layerCanvases(stage)[0]?.ratio ?? 1;
  const area = () => (figures ? null : cropOnCanvas(board.crop, ratio));
  const start = area();
  const { width, height } = start ? cropSize(start.width, start.height) : first;
  const canvas = document.createElement("canvas");
  // Video encoders want even sizes.
  canvas.width = width - (width % 2);
  canvas.height = height - (height % 2);
  const context = canvas.getContext("2d");
  if (!context) return null;
  const copy = () => {
    if (figures) {
      drawTilted(context, { ground: layerCanvases(stage), offset: tiltHolder.offset, figures: layerCanvases(figures), width: figures.width(), height: figures.height() });
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
  // A moment on the first frame before it moves.
  await new Promise(resolve => setTimeout(resolve, 400));
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
  // And a moment on the last.
  const end = performance.now();
  await new Promise<void>(resolve => {
    const hold = () => { copy(); if (performance.now() - end < 600) requestAnimationFrame(hold); else resolve(); };
    requestAnimationFrame(hold);
  });
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
