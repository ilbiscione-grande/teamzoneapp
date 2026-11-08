"use client";

import { useLayoutEffect, useState, type RefObject } from "react";

/** Fit the calendar frame and legend into the space below its actual controls. */
export function useCalendarHeight(frame: RefObject<HTMLDivElement | null>, view: string) {
  const [height, setHeight] = useState<number>();
  useLayoutEffect(() => {
    const element = frame.current;
    if (!element || view === "list") return;
    const section = element.parentElement!;
    let request = 0;
    const measure = () => {
      const box = element.getBoundingClientRect();
      const tail = Math.max(0,section.getBoundingClientRect().bottom - box.bottom);
      const viewport = window.visualViewport;
      const bottom = viewport ? viewport.offsetTop + viewport.height : window.innerHeight;
      const next = Math.max(96,Math.floor(bottom - box.top - tail - 16));
      setHeight(previous => previous === next ? previous : next);
    };
    const schedule = () => { cancelAnimationFrame(request); request = requestAnimationFrame(measure); };
    const observer = new ResizeObserver(schedule);
    observer.observe(section);
    if (section.parentElement) observer.observe(section.parentElement);
    window.addEventListener("resize",schedule);
    window.visualViewport?.addEventListener("resize",schedule);
    measure();
    return () => {
      observer.disconnect(); cancelAnimationFrame(request);
      window.removeEventListener("resize",schedule);
      window.visualViewport?.removeEventListener("resize",schedule);
    };
  }, [frame,view]);
  return height;
}
