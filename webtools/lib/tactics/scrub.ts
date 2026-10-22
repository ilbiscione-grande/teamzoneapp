// Scrubbing the timeline: the playhead (in frames, 2.4 is 40 % of the way
// from frame 2 to frame 3) as time and back, so each move takes the room
// on the timeline that it takes when played.
import type { Frame } from "./model.ts";
import { moveTime } from "./timeline.ts";

/** The time in ms at which each frame is reached: 0 for the first. */
export function frameTimes(frames: Frame[]): number[] {
  const times = [0];
  for (let index = 1; index < frames.length; index++) times.push(times[index - 1] + moveTime(frames, index));
  return times;
}

export function timeOfPlayhead(frames: Frame[], playhead: number): number {
  const times = frameTimes(frames);
  const last = frames.length - 1;
  if (last < 1) return 0;
  const clamped = Math.min(last, Math.max(0, playhead));
  const index = Math.min(last - 1, Math.floor(clamped));
  return times[index] + (clamped - index) * moveTime(frames, index + 1);
}

export function playheadOfTime(frames: Frame[], time: number): number {
  const times = frameTimes(frames);
  const last = frames.length - 1;
  if (last < 1 || time <= 0) return 0;
  if (time >= times[last]) return last;
  let index = 0;
  while (times[index + 1] <= time) index++;
  return index + (time - times[index]) / moveTime(frames, index + 1);
}

/** Seconds as the timeline shows them: "1,5 s". */
export const secondsLabel = (ms: number) => `${(Math.round(ms / 100) / 10).toLocaleString("sv-SE", { minimumFractionDigits: 1 })} s`;
