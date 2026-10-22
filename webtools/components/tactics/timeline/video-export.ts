"use client";

// The board as a video: it plays from the start while a hidden canvas copies
// the pitch and the objects every screen frame and the browser records it.
// MP4 where the browser makes it (Safari, newer Chrome), else WebM.
import { stageHolder } from "../stage/stage-context.ts";
import { activeBoard, useEditor } from "../store.ts";

const TYPES = ["video/mp4;codecs=avc1", "video/mp4", "video/webm;codecs=vp9", "video/webm;codecs=vp8", "video/webm"];

export const canRecord = () =>
  typeof window !== "undefined" && "MediaRecorder" in window && typeof HTMLCanvasElement.prototype.captureStream === "function";

function pickType(): string | undefined {
  return TYPES.find(type => MediaRecorder.isTypeSupported(type));
}

/** Plays the board from the start and gives back the recording; null when this browser cannot. */
export async function recordBoard(onProgress?: (share: number) => void): Promise<{ blob: Blob; extension: string } | null> {
  const stage = stageHolder.current;
  const board = activeBoard(useEditor.getState());
  if (!stage || !board || board.frames.length < 2 || !canRecord()) return null;
  const layers = stage.getLayers().map(layer => layer.getNativeCanvasElement());
  const width = layers[0].width, height = layers[0].height;
  const canvas = document.createElement("canvas");
  // Video encoders want even sizes.
  canvas.width = width - (width % 2);
  canvas.height = height - (height % 2);
  const context = canvas.getContext("2d");
  if (!context) return null;
  const copy = () => {
    context.fillStyle = "#24603a";
    context.fillRect(0, 0, canvas.width, canvas.height);
    for (const layer of layers) context.drawImage(layer, 0, 0);
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
      onProgress?.(Math.min(1, state.playhead / Math.max(1, board.frames.length - 1)));
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
