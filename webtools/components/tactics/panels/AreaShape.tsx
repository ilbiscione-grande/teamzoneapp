"use client";

// An area's shape in its properties: a zone of one's own made round, square
// or three-cornered at a tap, keeping its size, in the frame in hand, so it
// flows from one shape into another as the frames play; a rectangle or
// ellipse made into such a zone, in every frame it is in, to be reshaped so.
// An area new in its frame can be formed out of one gone since the frame
// before (MorphFrom), turning from that one's shape into its own.
import { areasGone } from "../../../lib/tactics/area-morph.ts";
import { objectLabel, updateBoard } from "../../../lib/tactics/document.ts";
import type { Board, ShapeObject, ZoneObject } from "../../../lib/tactics/model.ts";
import { reshapeZone, zoneOfShape, type ZoneShape } from "../../../lib/tactics/zone.ts";
import { useT } from "../../language";
import { useEditor } from "../store.ts";

const SHAPES: { shape: ZoneShape; label: string; sign: string }[] = [
  { shape: "circle", label: "Cirkel", sign: "◯" },
  { shape: "square", label: "Fyrkant", sign: "▢" },
  { shape: "triangle", label: "Triangel", sign: "△" },
];

/** Every frame's copy of a rectangle or ellipse made into a zone, so the frames keep one kind of object to blend between. */
const toZone = (board: Board, id: string): Board => ({
  ...board,
  frames: board.frames.map(frame => ({
    ...frame,
    objects: frame.objects.map(item => (item.id === id && (item.type === "rect" || item.type === "ellipse") ? zoneOfShape(item) : item)),
  })),
});

/**
 * Which area of the frame before this new one is formed out of: one gone from
 * this frame and not taken by another; none, it fades in. Shown only where
 * there is something to choose.
 */
export function MorphFrom({ item, board }: { item: ZoneObject | ShapeObject; board: Board }) {
  const t = useT();
  const frameIndex = useEditor(state => state.frameIndex);
  const before = board.frames[frameIndex - 1], now = board.frames[frameIndex];
  if (!before || !now || before.objects.some(other => other.id === item.id)) return null;
  const taken = new Set(now.objects.map(other => (other.id !== item.id && "morphFrom" in other ? other.morphFrom : null)).filter(Boolean));
  const choices = areasGone(before, now).filter(area => !taken.has(area.id) || area.id === item.morphFrom);
  if (choices.length === 0 && !item.morphFrom) return null;
  const names = choices.map(area => objectLabel(area, board, t));
  const named = (index: number) => (names.filter(name => name === names[index]).length > 1 ? `${names[index]} ${names.slice(0, index + 1).filter(name => name === names[index]).length}` : names[index]);
  return (
    <label className="tb-field">{t("Formas om från")}
      <select value={choices.some(area => area.id === item.morphFrom) ? item.morphFrom! : ""}
        onChange={event => useEditor.getState().patch({ [item.id]: { morphFrom: event.target.value || null } })}>
        <option value="">{t("Ingen, tonas in")}</option>
        {choices.map((area, index) => <option key={area.id} value={area.id}>{named(index)}</option>)}
      </select>
      <span className="tb-hint">{t("Zonen glider fram ur en zon från förra framen, med dess form och plats som start.")}</span>
    </label>
  );
}

export function AreaShape({ item, board }: { item: ZoneObject | ShapeObject; board: Board }) {
  const t = useT();
  if (item.type !== "zone") {
    return (
      <div className="tb-field">
        <button type="button" className="wt-button secondary small" onClick={() => useEditor.getState().change(document => updateBoard(document, board.id, current => toZone(current, item.id)))}>
          {t("Gör om till egen zon")}
        </button>
        <p className="tb-hint">{t("Som egen zon kan den byta form mellan frames, till exempel från cirkel till triangel.")}</p>
      </div>
    );
  }
  return (
    <div className="tb-field">{t("Gör zonen till")}
      <div className="tb-aligns" style={{ gridTemplateColumns: "1fr 1fr 1fr" }} role="group" aria-label={t("Gör zonen till")}>
        {SHAPES.map(({ shape, label, sign }) => (
          <button key={shape} type="button" title={t(label)} onClick={() => useEditor.getState().patch({ [item.id]: reshapeZone(item, shape) })}>
            {sign} {t(label)}
          </button>
        ))}
      </div>
    </div>
  );
}
