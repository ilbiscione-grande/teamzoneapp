"use client";

// Properties of what is selected: one object's own fields, or what several
// have in common. Nothing selected shows the board's settings.
import { kindName, newId, objectLabel } from "../../../lib/tactics/document.ts";
import type { BallFlight, Board, TacticsObject } from "../../../lib/tactics/model.ts";
import { effectsOf } from "../../../lib/tactics/timeline.ts";
import { effects } from "./effects.ts";
import { activeObjects, useEditor } from "../store.ts";
import { BoardSettings } from "./BoardSettings.tsx";
import { CopyTo } from "./CopyTo.tsx";
import { Swatches } from "./Swatches.tsx";
import { PlayerLink } from "./PlayerLink.tsx";

function Fields({ item, board }: { item: TacticsObject; board: Board }) {
  const patch = (changes: Partial<TacticsObject>) => useEditor.getState().patch({ [item.id]: changes });
  switch (item.type) {
    case "player":
      return (
        <>
          <label className="tb-field">Lag
            <select value={item.side} onChange={event => patch({ side: event.target.value as "home" | "away" })}>
              <option value="home">{board.teams.home.name}</option>
              <option value="away">{board.teams.away.name}</option>
            </select>
          </label>
          <PlayerLink item={item} />
          <label className="tb-field">Namn<input value={item.name ?? ""} maxLength={40} onChange={event => patch({ name: event.target.value || null })} /></label>
          <div className="tb-row">
            <label className="tb-field">Nummer
              <input inputMode="numeric" value={item.number ?? ""} maxLength={3}
                onChange={event => { const n = event.target.value.trim(); patch({ number: n === "" ? null : Number(n) || 0 }); }} />
            </label>
            <label className="tb-field">Position
              <input value={item.position ?? ""} maxLength={12} placeholder="t.ex. MV" onChange={event => patch({ position: event.target.value || null })} />
            </label>
          </div>
          {item.personId && <p className="tb-hint">Hämtat från laget när spelaren kopplades. Det du skriver här gäller på tavlan.</p>}
          <Swatches label="Egen färg (t.ex. målvakt)" value={item.color} onChange={color => patch({ color })} />
          {item.color && <button type="button" className="tb-link" onClick={() => patch({ color: null })}>Lagets färg</button>}
        </>
      );
    case "ball":
      return item.attachedTo
        ? <button type="button" className="wt-button secondary small" onClick={() => patch({ attachedTo: null, offset: null })}>Släpp från spelaren</button>
        : <p className="tb-hint">Släpp bollen nära en spelare så fäster den där.</p>;
    case "line":
    case "freehand":
      return (
        <>
          <div className="tb-row">
            <label className="tb-field">Pilspets
              <select value={item.arrow} onChange={event => patch({ arrow: event.target.value as typeof item.arrow })}>
                <option value="none">Ingen</option><option value="end">I slutet</option><option value="both">Båda ändar</option>
              </select>
            </label>
            <label className="tb-field">Tjocklek
              <input type="range" min={0.15} max={0.8} step={0.05} value={item.width} onChange={event => patch({ width: Number(event.target.value) })} />
            </label>
          </div>
          <label className="tb-field">Linje
            <select value={item.wavy ? "wavy" : item.dashed ? "dashed" : "solid"}
              onChange={event => patch({ dashed: event.target.value === "dashed", wavy: event.target.value === "wavy" })}>
              <option value="solid">Heldragen (passning)</option><option value="dashed">Streckad (löpning)</option><option value="wavy">Vågig (dribbling)</option>
            </select>
          </label>
          {item.type === "line" && item.control && <button type="button" className="tb-link" onClick={() => patch({ control: null })}>Gör rak</button>}
          {item.type === "line" && <p className="tb-hint">Dra i mittpunkten för att böja linjen.</p>}
          <Swatches label="Färg" value={item.color} onChange={color => patch({ color })} />
        </>
      );
    case "rect":
    case "ellipse":
      return (
        <>
          <label className="tb-field">Fyllning
            <input type="range" min={0} max={1} step={0.05} value={item.fill} onChange={event => patch({ fill: Number(event.target.value) })} />
          </label>
          <label className="tb-check"><input type="checkbox" checked={item.dashed} onChange={event => patch({ dashed: event.target.checked })} />Streckad kant</label>
          <Swatches label="Färg" value={item.color} onChange={color => patch({ color })} />
        </>
      );
    case "text":
      return (
        <>
          <label className="tb-field">Text<textarea rows={2} maxLength={200} value={item.text} onChange={event => patch({ text: event.target.value })} /></label>
          <label className="tb-field">Textstorlek
            <input type="range" min={0.8} max={8} step={0.2} value={item.size} onChange={event => patch({ size: Number(event.target.value) })} />
          </label>
          {item.width != null && <button type="button" className="tb-link" onClick={() => patch({ width: null, height: null })}>Anpassa rutan efter texten</button>}
          <label className="tb-check"><input type="checkbox" checked={item.background} onChange={event => patch({ background: event.target.checked })} />Bakgrund</label>
          <Swatches label="Färg" value={item.color} onChange={color => patch({ color })} />
        </>
      );
    default:
      return (
        <>
          <label className="tb-field">Storlek
            <input type="range" min={0.4} max={3} step={0.1} value={item.scale} onChange={event => patch({ scale: Number(event.target.value) })} />
          </label>
          <Swatches label="Färg" value={item.color} onChange={color => patch({ color })} />
        </>
      );
  }
}

/** The object's effects in this frame (chosen under Frames), its path's bend, and how a passed ball travels. */
function Motion({ item, frameIndex }: { item: TacticsObject; frameIndex: number }) {
  const patch = (changes: Partial<TacticsObject>) => useEditor.getState().patch({ [item.id]: changes });
  return (
    <>
      {frameIndex > 0 && <p className="tb-hint">Effekter i framen: {effectsOf(item).map(kind => effects[kind].label).join(", ") || "inga"}. Effekter väljer du under Frames.</p>}
      {frameIndex > 0 && item.pathControl && <button type="button" className="tb-link" onClick={() => patch({ pathControl: null })}>Rak väg hit</button>}
      {frameIndex > 0 && !item.pathControl && <p className="tb-hint">Dra i punkten mitt på spåret för att böja vägen hit.</p>}
      {frameIndex > 0 && item.type === "ball" && (
        <label className="tb-field">Passningen hit
          <select value={item.flight ?? "ground"} onChange={event => patch({ flight: event.target.value as BallFlight } as Partial<TacticsObject>)}>
            <option value="ground">Längs marken</option><option value="chip">Chip (lyft)</option><option value="high">Långboll (hög)</option>
          </select>
        </label>
      )}
    </>
  );
}

export function Inspector({ board }: { board: Board }) {
  const objects = useEditor(activeObjects);
  const selection = useEditor(state => state.selection);
  const frameIndex = useEditor(state => state.frameIndex);
  const selected = objects.filter(item => selection.includes(item.id));
  const { patch, changeObjects, removeSelected, select } = useEditor.getState();
  if (selected.length === 0) return <BoardSettings board={board} />;
  const single = selected.length === 1 ? selected[0] : null;
  const allLocked = selected.every(item => item.locked);
  const duplicate = () => {
    const copies = selected.map(item => ({ ...item, id: newId(), x: item.x + 3, y: item.y + 3, locked: false }) as TacticsObject);
    changeObjects(current => [...current, ...copies]);
    select(copies.map(copy => copy.id));
  };
  return (
    <div className="tb-inspector">
      <h3>{single ? objectLabel(single, board) : `${selected.length} markerade`}</h3>
      {single && <p className="tb-hint">{kindName(single.type)}</p>}
      {single && !single.locked && <Fields item={single} board={board} />}
      {single && !single.locked && board.frames.length > 1 && <Motion item={single} frameIndex={frameIndex} />}
      {single && (
        <label className="tb-field">Namn i listan
          <input value={single.label ?? ""} maxLength={40} placeholder={objectLabel({ ...single, label: undefined }, board)}
            onChange={event => patch({ [single.id]: { label: event.target.value || undefined } })} />
        </label>
      )}
      <div className="tb-actions">
        <button type="button" className="wt-button secondary small" onClick={() => patch(Object.fromEntries(selected.map(item => [item.id, { locked: !allLocked }])))}>
          {allLocked ? "Lås upp" : "Lås"}
        </button>
        <button type="button" className="wt-button secondary small" onClick={duplicate}>Kopiera</button>
        <button type="button" className="wt-button secondary small" disabled={allLocked} onClick={removeSelected}>Ta bort</button>
      </div>
      <CopyTo key={`${frameIndex}:${selection.join()}`} board={board} ids={selected.map(item => item.id)} />
    </div>
  );
}
