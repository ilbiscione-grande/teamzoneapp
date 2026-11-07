"use client";

// The frames to choose from and a new one. Many frames scroll sideways, by
// finger, wheel or the arrows that show then, and the frame in hand or being
// played is kept in view.
import { useCallback, useEffect, useRef, useState } from "react";
import type { Frame } from "../../../lib/tactics/model.ts";
import { useEditor } from "../store.ts";
import { useT } from "../../language";

export function FrameStrip({ frames, moving, onAdd }: { frames: Frame[]; moving: boolean; onAdd: () => void }) {
  const t = useT();
  const frameIndex = useEditor(state => state.frameIndex);
  const playing = useEditor(state => state.playing);
  const playhead = useEditor(state => state.playhead);
  const list = useRef<HTMLDivElement>(null);
  const [room, setRoom] = useState({ before: false, after: false });

  /** Which way there is more to scroll to; none when all the frames show. */
  const measure = useCallback(() => {
    const box = list.current;
    if (!box) return;
    const before = box.scrollLeft > 1;
    const after = box.scrollLeft + box.clientWidth < box.scrollWidth - 1;
    setRoom(current => (current.before === before && current.after === after ? current : { before, after }));
  }, []);
  useEffect(() => {
    const box = list.current;
    if (!box) return;
    const observer = new ResizeObserver(measure);
    observer.observe(box);
    return () => observer.disconnect();
  }, [measure]);

  const shown = moving ? Math.round(playhead) : frameIndex;
  useEffect(() => {
    const box = list.current;
    const chip = box?.children[shown] as HTMLElement | undefined;
    if (box && chip) {
      if (chip.offsetLeft < box.scrollLeft) box.scrollLeft = chip.offsetLeft;
      else if (chip.offsetLeft + chip.offsetWidth > box.scrollLeft + box.clientWidth) box.scrollLeft = chip.offsetLeft + chip.offsetWidth - box.clientWidth;
    }
    measure();
  }, [shown, frames.length, measure]);

  const scroll = (way: 1 | -1) => {
    const box = list.current;
    box?.scrollBy({ left: way * box.clientWidth * 0.8, behavior: "smooth" });
  };
  const arrows = room.before || room.after;

  return (
    <div className="tb-frames-wrap">
      {arrows && <button type="button" className="tb-frames-arrow" disabled={!room.before} aria-label={t("Visa tidigare frames")} title={t("Visa tidigare frames")} onClick={() => scroll(-1)}>‹</button>}
      <div ref={list} className="tb-frames" role="tablist" aria-label={t("Frames")} onScroll={measure}
        onWheel={event => { if (event.deltaY !== 0) event.currentTarget.scrollLeft += event.deltaY; }}>
        {frames.map((frame, index) => (
          <button key={frame.id} type="button" role="tab" aria-selected={!moving && index === frameIndex}
            data-current={moving && Math.round(playhead) === index} onClick={() => useEditor.getState().setFrame(index)}>{index + 1}</button>
        ))}
      </div>
      {arrows && <button type="button" className="tb-frames-arrow" disabled={!room.after} aria-label={t("Visa senare frames")} title={t("Visa senare frames")} onClick={() => scroll(1)}>›</button>}
      <button type="button" className="tb-frame-add" onClick={onAdd} disabled={playing} aria-label={t("Ny frame (kopia av denna)")} title={t("Ny frame: en kopia av den här att flytta vidare i")}>+</button>
    </div>
  );
}
