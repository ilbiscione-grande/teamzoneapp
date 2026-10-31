"use client";

// The tools on a phone: one large button per group (select, place, draw,
// measure) showing the group's tool in hand or last taken; a tap opens the
// group's tools above the row, with a word under each, and a choice closes it.
import { useEffect, useRef, useState } from "react";
import { useEditor, type Tool } from "../store.ts";
import { groups, type Item } from "./Toolbar.tsx";

export function PhoneToolbar({ homeColor, awayColor }: { homeColor: string; awayColor: string }) {
  const tool = useEditor(state => state.tool);
  const measure = useEditor(state => state.measure);
  const [open, setOpen] = useState<string | null>(null);
  // Each group's last tool, shown on its button.
  const [last, setLast] = useState<Record<string, Tool>>({});
  useEffect(() => {
    const group = groups.find(item => item.items.some(entry => entry.tool === tool));
    if (group) setLast(current => (current[group.title] === tool ? current : { ...current, [group.title]: tool }));
  }, [tool]);
  // A tap outside the tools closes an open group.
  const nav = useRef<HTMLElement>(null);
  useEffect(() => {
    if (!open) return;
    const close = (event: PointerEvent) => { if (!nav.current?.contains(event.target as Node)) setOpen(null); };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, [open]);
  const colour = (item: Item) => (item.tool === "player-home" ? { color: homeColor } : item.tool === "player-away" ? { color: awayColor } : undefined);
  const choose = (next: Tool) => {
    useEditor.getState().setTool(next);
    setOpen(null);
  };
  const shown = groups.find(group => group.title === open);
  return (
    <nav ref={nav} className="tb-tools tb-phone-tools" aria-label="Verktyg">
      {shown && (
        <div className="tb-phone-group" role="group" aria-label={shown.title}>
          {shown.items.map(item => (
            <button key={item.tool} type="button" aria-pressed={tool === item.tool} onClick={() => choose(item.tool)}>
              <span className="tb-tool-icon" aria-hidden="true" style={colour(item)}>{item.icon}</span>
              <span>{item.short}</span>
            </button>
          ))}
          {shown.title === "Mät" && (
            <button type="button" aria-pressed={measure} onClick={() => { useEditor.getState().setMeasure(!measure); setOpen(null); }}>
              <span className="tb-tool-icon" aria-hidden="true">m²</span>
              <span>Mått</span>
            </button>
          )}
        </div>
      )}
      {groups.map(group => {
        const single = group.items.length === 1 && group.title !== "Mät";
        const item = group.items.find(entry => entry.tool === (last[group.title] ?? group.items[0].tool)) ?? group.items[0];
        const active = group.items.some(entry => entry.tool === tool);
        return (
          <button key={group.title} type="button" className="tb-phone-button" aria-pressed={active} aria-expanded={single ? undefined : open === group.title}
            aria-label={single ? item.label : `${group.title}: ${item.label}`}
            onClick={() => (single ? choose(item.tool) : setOpen(open === group.title ? null : group.title))}>
            <span className="tb-tool-icon" aria-hidden="true" style={colour(item)}>{item.icon}</span>
            <span className="tb-phone-label">{group.title}{!single && <span aria-hidden="true"> ▴</span>}</span>
          </button>
        );
      })}
    </nav>
  );
}
