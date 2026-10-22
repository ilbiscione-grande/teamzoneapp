"use client";

// On a phone the top bar keeps room for the board tabs: presenting, the PDF
// and the live lesson move into a "more" menu under one button.
import { useEffect, useRef, useState } from "react";
import { useLive } from "./live/live-store.ts";

type Item = { label: string; run: () => void };

export function TopBarMore({ onPresent, onPdf, onLive }: { onPresent: () => void; onPdf: () => void; onLive: () => void }) {
  const [open, setOpen] = useState(false);
  const [at, setAt] = useState({ right: 8, top: 0 });
  const button = useRef<HTMLButtonElement>(null);
  const menu = useRef<HTMLDivElement>(null);
  const live = useLive(state => !!state.session);
  useEffect(() => {
    if (!open) return;
    const close = (event: Event) => {
      if (event instanceof KeyboardEvent ? event.key === "Escape" : !menu.current?.contains(event.target as Node) && !button.current?.contains(event.target as Node)) setOpen(false);
    };
    window.addEventListener("pointerdown", close);
    window.addEventListener("keydown", close);
    return () => { window.removeEventListener("pointerdown", close); window.removeEventListener("keydown", close); };
  }, [open]);

  const items: Item[] = [
    { label: "Visa i helskärm", run: onPresent },
    { label: "Skapa PDF", run: onPdf },
    { label: live ? "Livelektion pågår" : "Livelektion", run: onLive },
  ];
  const toggle = () => {
    const rect = button.current?.getBoundingClientRect();
    if (rect) setAt({ right: Math.max(8, window.innerWidth - rect.right), top: rect.bottom + 4 });
    setOpen(!open);
  };
  return (
    <span className="tb-narrow-only">
      <button ref={button} type="button" className="tb-icon" data-live={live} onClick={toggle} aria-haspopup="menu" aria-expanded={open} aria-label="Mer">⋯</button>
      {open && (
        <div ref={menu} className="tb-menu tb-more-menu" role="menu" style={{ right: at.right, top: at.top }}>
          {items.map(item => (
            <button key={item.label} type="button" role="menuitem" onClick={() => { setOpen(false); item.run(); }}>{item.label}</button>
          ))}
        </div>
      )}
    </span>
  );
}
