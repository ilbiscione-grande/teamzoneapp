"use client";

// The quick menu over what is chosen on the pitch: its colour, copy, group,
// lock, order and remove, and the rest of its properties, without going to
// the side panel. Sized for a finger. Above the selection, or under it when
// there is no room above.
import { useLayoutEffect, useRef, useState } from "react";
import { stack, type Stacking } from "../../lib/tactics/document.ts";
import { oneGroup } from "../../lib/tactics/grouping.ts";
import { swatches } from "./panels/Swatches.tsx";
import { activeObjects, useEditor } from "./store.ts";
import type { ScreenBox } from "./stage/use-selection-box.ts";

const GAP = 10;

export function QuickMenu({ box, frame, onProperties }: { box: ScreenBox; frame: { width: number; height: number }; onProperties: () => void }) {
  const objects = useEditor(activeObjects);
  const selection = useEditor(state => state.selection);
  const menu = useRef<HTMLDivElement>(null);
  const [colours, setColours] = useState(false);
  const [place, setPlace] = useState<{ left: number; top: number } | null>(null);
  useLayoutEffect(() => {
    const element = menu.current;
    if (!element) return;
    const { width, height } = element.getBoundingClientRect();
    const middle = (box.left + box.right) / 2;
    const left = Math.max(6, Math.min(frame.width - width - 6, middle - width / 2));
    const above = box.top - height - GAP;
    const top = above >= 6 ? above : Math.min(frame.height - height - 6, box.bottom + GAP);
    setPlace(current => (current && current.left === left && current.top === top ? current : { left, top }));
  }, [box, frame.width, frame.height, colours, selection]);

  const chosen = objects.filter(item => selection.includes(item.id));
  if (chosen.length === 0) return null;
  const { patch, changeObjects, removeSelected, duplicateSelected, groupSelected } = useEditor.getState();
  const allLocked = chosen.every(item => item.locked);
  const grouped = oneGroup(objects, selection);
  // Players have their team's colour; the rest their own.
  const coloured = chosen.filter(item => "color" in item && item.type !== "player" && !item.locked);
  const colour = coloured[0] && "color" in coloured[0] ? coloured[0].color : null;
  const order = (where: Stacking) => changeObjects(current => stack(current, selection, where));
  const button = (label: string, icon: React.ReactNode, onClick: () => void, extra: { pressed?: boolean; disabled?: boolean; danger?: boolean } = {}) => (
    <button type="button" title={label} aria-label={label} aria-pressed={extra.pressed} disabled={extra.disabled}
      data-danger={extra.danger || undefined} onClick={onClick}>{icon}</button>
  );
  return (
    <div ref={menu} className="tb-quick" role="toolbar" aria-label="Snabbmeny"
      style={place ? { left: place.left, top: place.top } : { left: 0, top: 0, visibility: "hidden" }}
      onPointerDown={event => event.stopPropagation()}>
      <div className="tb-quick-row">
        {coloured.length > 0 && button("Färg", <span className="tb-quick-colour" style={{ background: colour ?? "#ffffff" }} />, () => setColours(!colours), { pressed: colours })}
        {button("Kopiera (Ctrl+D)", "⧉", duplicateSelected)}
        {(grouped || chosen.length > 1) && button(grouped ? "Dela upp gruppen (Ctrl+Shift+G)" : "Gruppera (Ctrl+G)", "⧈",() => groupSelected(!grouped), { pressed: grouped })}
        {button(allLocked ? "Lås upp" : "Lås", allLocked ? "🔒" : "🔓", () => patch(Object.fromEntries(chosen.map(item => [item.id, { locked: !allLocked }]))), { pressed: allLocked })}
        {button("Lägg överst i sitt lager (Home)", "⤒", () => order("top"))}
        {button("Lägg underst i sitt lager (End)", "⤓", () => order("bottom"))}
        {button("Ta bort (Delete)", "🗑", removeSelected, { disabled: allLocked, danger: true })}
        {button("Alla egenskaper", "⋯", onProperties)}
      </div>
      {colours && coloured.length > 0 && (
        <div className="tb-quick-colours" role="radiogroup" aria-label="Färg">
          {swatches.map(value => (
            <button key={value} type="button" role="radio" aria-checked={colour === value} aria-label={value} style={{ background: value }}
              onClick={() => patch(Object.fromEntries(coloured.map(item => [item.id, { color: value }])))} />
          ))}
        </div>
      )}
    </div>
  );
}
