"use client";

// Several objects selected: what they have in common, changed for all of
// them at once. The colour for all that have one; when all are players,
// their team and facing; all lines, their style; all areas, their fill;
// all equipment, its size. A field the selected differ in shows no value
// until it is set. Their effects are chosen under Frames, as for one.
import { updateBoard } from "../../../lib/tactics/document.ts";
import { facings, facingToRotation, normalAngle } from "../../../lib/tactics/facing.ts";
import type { ArrowHead, Board, EquipmentObject, FreehandObject, LineObject, PlayerObject, ShapeObject, TacticsObject, TextObject } from "../../../lib/tactics/model.ts";
import { standingFacing } from "../../../lib/tactics/timeline.ts";
import { useEditor } from "../store.ts";
import { Swatches } from "./Swatches.tsx";

const EQUIPMENT = new Set(["cone", "pole", "mannequin", "goal"]);
/** "" when the selected differ, so a select shows its blank choice. */
const MIXED = "";

/** The value all share, or undefined when they differ. */
function shared<T, V>(items: T[], read: (item: T) => V): V | undefined {
  const first = read(items[0]);
  return items.every(item => read(item) === first) ? first : undefined;
}

export function SharedFields({ items, board }: { items: TacticsObject[]; board: Board }) {
  const open = items.filter(item => !item.locked);
  if (open.length < 2) return null;
  /** The same change to each, worked out per object. */
  const patchEach = <T extends TacticsObject>(list: T[], change: (item: T) => Partial<TacticsObject>) =>
    useEditor.getState().patch(Object.fromEntries(list.map(item => [item.id, change(item)])));
  const coloured = open.filter(item => item.type !== "ball") as Exclude<TacticsObject, { type: "ball" }>[];
  const players = open.every(item => item.type === "player") ? (open as PlayerObject[]) : null;
  const lines = open.every(item => item.type === "line" || item.type === "freehand") ? (open as (LineObject | FreehandObject)[]) : null;
  const areas = open.every(item => item.type === "rect" || item.type === "ellipse") ? (open as ShapeObject[]) : null;
  const equipment = open.every(item => EQUIPMENT.has(item.type)) ? (open as EquipmentObject[]) : null;
  const texts = open.every(item => item.type === "text") ? (open as TextObject[]) : null;

  return (
    <>
      {players && (
        <>
          <label className="tb-field">Lag
            <select value={shared(players, item => item.side) ?? MIXED} onChange={event => patchEach(players, () => ({ side: event.target.value as PlayerObject["side"] }))}>
              <option value={MIXED} disabled>Olika</option>
              <option value="home">{board.teams.home.name}</option>
              <option value="away">{board.teams.away.name}</option>
            </select>
          </label>
          <div className="tb-field">Blickriktning
            <div className="tb-facings" role="group" aria-label="Blickriktning">
              {facings.map(way => (
                <button key={way.angle} type="button" aria-label={way.label} title={way.label}
                  aria-pressed={players.every(item => Math.round(normalAngle(standingFacing(item))) === way.angle)}
                  onClick={() => {
                    if (!board.showFacing) useEditor.getState().change(document => updateBoard(document, board.id, current => ({ ...current, showFacing: true })));
                    patchEach(players, item => ({ rotation: facingToRotation(way.angle, item.side) }));
                  }}>{way.arrow}</button>
              ))}
            </div>
          </div>
        </>
      )}
      {lines && (
        <>
          <div className="tb-row">
            <label className="tb-field">Pilspets
              <select value={shared(lines, item => item.arrow) ?? MIXED} onChange={event => patchEach(lines, () => ({ arrow: event.target.value as ArrowHead }))}>
                <option value={MIXED} disabled>Olika</option>
                <option value="none">Ingen</option><option value="end">I slutet</option><option value="both">Båda ändar</option>
              </select>
            </label>
            <label className="tb-field">Tjocklek
              <input type="range" min={0.15} max={0.8} step={0.05} value={shared(lines, item => item.width) ?? lines[0].width}
                onChange={event => patchEach(lines, () => ({ width: Number(event.target.value) }))} />
            </label>
          </div>
          <label className="tb-field">Linje
            <select value={shared(lines, item => (item.wavy ? "wavy" : item.dashed ? "dashed" : "solid")) ?? MIXED}
              onChange={event => patchEach(lines, () => ({ dashed: event.target.value === "dashed", wavy: event.target.value === "wavy" }))}>
              <option value={MIXED} disabled>Olika</option>
              <option value="solid">Heldragen (passning)</option><option value="dashed">Streckad (löpning)</option><option value="wavy">Vågig (dribbling)</option>
            </select>
          </label>
        </>
      )}
      {areas && (
        <>
          <label className="tb-field">Fyllning
            <input type="range" min={0} max={1} step={0.05} value={shared(areas, item => item.fill) ?? areas[0].fill}
              onChange={event => patchEach(areas, () => ({ fill: Number(event.target.value) }))} />
          </label>
          <label className="tb-check">
            <input type="checkbox" checked={areas.every(item => item.dashed)} onChange={event => patchEach(areas, () => ({ dashed: event.target.checked }))} />Streckad kant
          </label>
        </>
      )}
      {equipment && (
        <label className="tb-field">Storlek
          <input type="range" min={0.4} max={3} step={0.1} value={shared(equipment, item => item.scale) ?? equipment[0].scale}
            onChange={event => patchEach(equipment, () => ({ scale: Number(event.target.value) }))} />
        </label>
      )}
      {texts && (
        <>
          <label className="tb-field">Textstorlek
            <input type="range" min={0.8} max={8} step={0.2} value={shared(texts, item => item.size) ?? texts[0].size}
              onChange={event => patchEach(texts, () => ({ size: Number(event.target.value) }))} />
          </label>
          <label className="tb-check">
            <input type="checkbox" checked={texts.every(item => item.background)} onChange={event => patchEach(texts, () => ({ background: event.target.checked }))} />Bakgrund
          </label>
        </>
      )}
      {coloured.length > 0 && (
        <>
          <Swatches label={players ? "Egen färg" : "Färg"} value={shared(coloured, item => item.color) ?? null} onChange={color => patchEach(coloured, () => ({ color }))} />
          {coloured.some(item => item.type === "player" && item.color) && (
            <button type="button" className="tb-link" onClick={() => patchEach(coloured.filter(item => item.type === "player"), () => ({ color: null }))}>Lagets färg</button>
          )}
          {!players && coloured.length < open.length && <p className="tb-hint">Färgen gäller allt markerat utom bollen.</p>}
        </>
      )}
      {board.frames.length > 1 && <p className="tb-hint">Effekter för alla markerade väljer du under Frames.</p>}
    </>
  );
}
