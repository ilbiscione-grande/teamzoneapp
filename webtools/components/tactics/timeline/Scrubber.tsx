"use client";

// The timeline to scrub: each frame a dot where it is reached in time, the
// playhead a handle to drag back and forth, stopping anywhere, between two
// frames too. A dot jumps to its frame; near a dot the handle snaps to it.
// The arrow keys step a tenth of a second, Page keys a frame.
import { useRef } from "react";
import type { Frame } from "../../../lib/tactics/model.ts";
import { frameTimes, playheadOfTime, secondsLabel, timeOfPlayhead } from "../../../lib/tactics/scrub.ts";
import { useEditor } from "../store.ts";

const SNAP_PX = 8;

export function Scrubber({ frames }: { frames: Frame[] }) {
  const track = useRef<HTMLDivElement>(null);
  const dragging = useRef(false);
  const playhead = useEditor(state => state.playhead);
  const { scrub, setFrame } = useEditor.getState();
  const times = frameTimes(frames);
  const total = times[times.length - 1] || 1;
  const now = timeOfPlayhead(frames, playhead);
  const percent = (time: number) => `${(time / total) * 100}%`;

  const scrubTo = (clientX: number) => {
    const rect = track.current?.getBoundingClientRect();
    if (!rect || rect.width <= 0) return;
    const x = Math.min(rect.width, Math.max(0, clientX - rect.left));
    const near = times.findIndex(time => Math.abs((time / total) * rect.width - x) <= SNAP_PX);
    scrub(near >= 0 ? near : playheadOfTime(frames, (x / rect.width) * total));
  };
  const step = (ms: number) => scrub(playheadOfTime(frames, now + ms));

  return (
    <div className="tb-scrub-row">
      <div ref={track} className="tb-scrub" role="slider" tabIndex={0} aria-label="Tidslinje"
        aria-valuemin={0} aria-valuemax={frames.length - 1} aria-valuenow={Math.round(playhead * 10) / 10}
        aria-valuetext={`${secondsLabel(now)} av ${secondsLabel(total)}`}
        onPointerDown={event => {
          if (event.button !== 0) return;
          dragging.current = true;
          try { event.currentTarget.setPointerCapture(event.pointerId); } catch { /* a pointer already gone */ }
          scrubTo(event.clientX);
        }}
        onPointerMove={event => { if (dragging.current) scrubTo(event.clientX); }}
        onPointerUp={() => { dragging.current = false; }}
        onPointerCancel={() => { dragging.current = false; }}
        onKeyDown={event => {
          const keys: Record<string, () => void> = {
            ArrowRight: () => step(100), ArrowLeft: () => step(-100),
            PageUp: () => setFrame(Math.floor(playhead) + 1), PageDown: () => setFrame(Math.ceil(playhead) - 1),
            Home: () => setFrame(0), End: () => setFrame(frames.length - 1),
          };
          if (!keys[event.key]) return;
          event.preventDefault();
          keys[event.key]();
        }}>
        <div className="tb-scrub-track"><span className="tb-scrub-fill" style={{ width: percent(now) }} /></div>
        {times.map((time, index) => (
          <button key={frames[index].id} type="button" className="tb-scrub-tick" tabIndex={-1} style={{ left: percent(time) }}
            data-passed={time <= now + 1} aria-label={`Frame ${index + 1}`}
            onPointerDown={event => { event.stopPropagation(); setFrame(index); }}>
            <span aria-hidden="true">{index + 1}</span>
          </button>
        ))}
        <span className="tb-scrub-thumb" style={{ left: percent(now) }} />
      </div>
      <span className="tb-scrub-time">{secondsLabel(now)} / {secondsLabel(total)}</span>
    </div>
  );
}
