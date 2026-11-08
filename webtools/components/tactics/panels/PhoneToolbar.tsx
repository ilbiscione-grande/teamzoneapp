"use client";

// The tools on a phone, in a column on the board: one button per group (select, place, draw,
// measure) showing the group's tool in hand or last taken; a tap opens the
// group's tools to its left, with a word under each, and a choice closes it.
// Pick several (PickMany) shows on the pitch once something is chosen.
import { Fragment, useEffect, useRef, useState } from "react";
import { useEditor, type Tool } from "../store.ts";
import { groups, measureGroup, type Item } from "./Toolbar.tsx";
import { useT } from "../../language";

export function PhoneToolbar({ homeColor, awayColor }: { homeColor: string; awayColor: string }) {
  const t = useT();
  const tool = useEditor(state => state.tool);
  const measure = useEditor(state => state.measure);
  const pickMany = useEditor(state => state.pickMany);
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
    <nav ref={nav} className="tb-tools tb-phone-tools" aria-label={t("Verktyg")}>
      {shown && (
        <div className="tb-phone-group" role="group" aria-label={shown.title}>
          {shown.items.map(item => (
            <button key={item.tool} type="button" aria-pressed={tool === item.tool} onClick={() => choose(item.tool)}>
              <span className="tb-tool-icon" aria-hidden="true" style={colour(item)}>{item.icon}</span>
              <span>{t(item.short)}</span>
            </button>
          ))}
          {shown.title === measureGroup && (
            <button type="button" aria-pressed={measure} onClick={() => { useEditor.getState().setMeasure(!measure); setOpen(null); }}>
              <span className="tb-tool-icon" aria-hidden="true">m²</span>
              <span>{t("Mått")}</span>
            </button>
          )}
        </div>
      )}
      {groups.map(group => {
        const single = group.items.length === 1 && group.title !== measureGroup;
        const item = group.items.find(entry => entry.tool === (last[group.title] ?? group.items[0].tool)) ?? group.items[0];
        const active = group.items.some(entry => entry.tool === tool);
        return (
          <Fragment key={group.title}>
            <button type="button" className="tb-phone-button" aria-pressed={active} aria-expanded={single ? undefined : open === group.title}
              aria-label={single ? t(item.label) : `${t(group.title)}: ${t(item.label)}`}
              onClick={() => { if (pickMany) useEditor.getState().setPickMany(false); if (single) choose(item.tool); else setOpen(open === group.title ? null : group.title); }}>
              <span className="tb-tool-icon" aria-hidden="true" style={colour(item)}>{item.icon}</span>
              <span className="tb-phone-label">{t(group.title)}{!single && <span aria-hidden="true"> ▴</span>}</span>
            </button>
          </Fragment>
        );
      })}
    </nav>
  );
}

/**
 * On the pitch's top corner once something is chosen: pick several, one
 * tap at a time, in the order tapped (a line between players); on, it
 * says how many are picked and is turned off from the same place.
 */
export function PickMany() {
  const t = useT();
  const pickMany = useEditor(state => state.pickMany);
  const picked = useEditor(state => state.selection.length);
  const tool = useEditor(state => state.tool);
  if (tool !== "select" || (!pickMany && picked === 0)) return null;
  return (
    <button type="button" className="tb-pick-many" aria-pressed={pickMany} title={t("Välj flera: varje tryck lägger till eller tar bort")}
      onClick={() => useEditor.getState().setPickMany(!pickMany)}>
      {pickMany ? <>{t(picked === 1 ? "{count} vald" : "{count} valda", { count: picked })} · {t("Klar")}</> : <><span aria-hidden="true">⊕</span> {t("Välj flera")}</>}
    </button>
  );
}
