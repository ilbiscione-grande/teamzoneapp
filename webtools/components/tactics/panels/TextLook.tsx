"use client";

// How one or several texts look: their lines to the left, centred or to the
// right, and their background on or off, its colour and how much it covers.
// A value the texts differ in shows none until it is set.
import { textBackground, type TextAlign, type TextObject } from "../../../lib/tactics/model.ts";
import { useEditor } from "../store.ts";
import { Swatches } from "./Swatches.tsx";

const aligns: [TextAlign, string, string][] = [
  ["left", "Vänster", "Vänsterställd"],
  ["center", "Mitten", "Centrerad"],
  ["right", "Höger", "Högerställd"],
];

export function TextLook({ texts }: { texts: TextObject[] }) {
  const patch = (changes: Partial<TextObject>) => useEditor.getState().patch(Object.fromEntries(texts.map(item => [item.id, changes])));
  const same = <V,>(read: (item: TextObject) => V) => texts.every(item => read(item) === read(texts[0])) ? read(texts[0]) : undefined;
  const align = same(item => item.align ?? "left");
  const background = texts.every(item => item.background);
  const colour = same(item => item.backgroundColor ?? textBackground.color);
  const opacity = same(item => item.backgroundOpacity ?? textBackground.opacity);
  return (
    <>
      <div className="tb-field">Placering av texten
        <div className="tb-aligns" role="group" aria-label="Placering av texten">
          {aligns.map(([value, label, hint]) => (
            <button key={value} type="button" title={hint} aria-pressed={align === value} onClick={() => patch({ align: value })}>{label}</button>
          ))}
        </div>
      </div>
      <label className="tb-check"><input type="checkbox" checked={background} onChange={event => patch({ background: event.target.checked })} />Bakgrund</label>
      {background && (
        <>
          <Swatches label="Bakgrundsfärg" value={colour ?? null} onChange={value => patch({ backgroundColor: value })} />
          <label className="tb-field">Bakgrundens täckning {opacity === undefined ? "" : `${Math.round(opacity * 100)} %`}
            <input type="range" min={0.1} max={1} step={0.05} value={opacity ?? textBackground.opacity}
              onChange={event => patch({ backgroundOpacity: Number(event.target.value) })} />
          </label>
        </>
      )}
    </>
  );
}
