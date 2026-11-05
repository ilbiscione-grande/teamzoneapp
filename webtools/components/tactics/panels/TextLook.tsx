"use client";

// How one or several texts look: their lines to the left, centred or to the
// right, and their background on or off, its colour and how much it covers.
// A value the texts differ in shows none until it is set.
import { textBackground, type TextAlign, type TextObject } from "../../../lib/tactics/model.ts";
import { useEditor } from "../store.ts";
import { Swatches } from "./Swatches.tsx";
import { useT } from "../../language";

const aligns: [TextAlign, string, string][] = [
  ["left", "Vänster", "Vänsterställd"],
  ["center", "Mitten", "Centrerad"],
  ["right", "Höger", "Högerställd"],
];

export function TextLook({ texts }: { texts: TextObject[] }) {
  const t = useT();
  const patch = (changes: Partial<TextObject>) => useEditor.getState().patch(Object.fromEntries(texts.map(item => [item.id, changes])));
  const same = <V,>(read: (item: TextObject) => V) => texts.every(item => read(item) === read(texts[0])) ? read(texts[0]) : undefined;
  const align = same(item => item.align ?? "left");
  const background = texts.every(item => item.background);
  const colour = same(item => item.backgroundColor ?? textBackground.color);
  const opacity = same(item => item.backgroundOpacity ?? textBackground.opacity);
  return (
    <>
      <div className="tb-field">{t("Placering av texten")}
        <div className="tb-aligns" role="group" aria-label={t("Placering av texten")}>
          {aligns.map(([value, label, hint]) => (
            <button key={value} type="button" title={t(hint)} aria-pressed={align === value} onClick={() => patch({ align: value })}>{t(label)}</button>
          ))}
        </div>
      </div>
      <label className="tb-check"><input type="checkbox" checked={background} onChange={event => patch({ background: event.target.checked })} />{t("Bakgrund")}</label>
      {background && (
        <>
          <Swatches label={t("Bakgrundsfärg")} value={colour ?? null} onChange={value => patch({ backgroundColor: value })} />
          <label className="tb-field">{t("Bakgrundens täckning")} {opacity === undefined ? "" : `${Math.round(opacity * 100)} %`}
            <input type="range" min={0.1} max={1} step={0.05} value={opacity ?? textBackground.opacity}
              onChange={event => patch({ backgroundOpacity: Number(event.target.value) })} />
          </label>
        </>
      )}
    </>
  );
}
