"use client";

// Properties of what is selected: one object's own fields, or what several
// have in common. Nothing selected shows the board's settings.
import { kindName, objectLabel, stack, updateBoard, type Stacking } from "../../../lib/tactics/document.ts";
import { oneGroup } from "../../../lib/tactics/grouping.ts";
import type { AreaPattern, BallFlight, Board, TacticsObject } from "../../../lib/tactics/model.ts";
import { effectsOf, standingFacing } from "../../../lib/tactics/timeline.ts";
import { facings, facingToRotation, normalAngle } from "../../../lib/tactics/facing.ts";
import { effects } from "./effects.ts";
import { activeObjects, useEditor } from "../store.ts";
import { BoardSettings } from "./BoardSettings.tsx";
import { CopyTo } from "./CopyTo.tsx";
import { Swatches } from "./Swatches.tsx";
import { TextLook } from "./TextLook.tsx";
import { PlayerLink } from "./PlayerLink.tsx";
import { SharedFields } from "./SharedFields.tsx";

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
          <div className="tb-field">Blickriktning
            <div className="tb-facings" role="group" aria-label="Blickriktning">
              {facings.map(way => (
                <button key={way.angle} type="button" aria-label={way.label} title={way.label}
                  aria-pressed={Math.round(normalAngle(standingFacing(item))) === way.angle}
                  onClick={() => {
                    // Turning a player shows which way players face on this board.
                    if (!board.showFacing) useEditor.getState().change(document => updateBoard(document, board.id, current => ({ ...current, showFacing: true })));
                    patch({ rotation: facingToRotation(way.angle, item.side) });
                  }}>{way.arrow}</button>
              ))}
            </div>
            <span className="tb-hint">Eller dra i den gula punkten framför spelaren.</span>
          </div>
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
          <label className="tb-field">Mönster
            <select value={item.pattern ?? "solid"} onChange={event => patch({ pattern: event.target.value as AreaPattern })}>
              <option value="solid">Fylld</option><option value="stripes">Randig</option>
            </select>
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
          <Swatches label="Textfärg" value={item.color} onChange={color => patch({ color })} />
          <TextLook texts={[item]} />
        </>
      );
    case "chain":
      return (
        <>
          <p className="tb-hint">Går genom {item.players.length} spelare och följer dem när de flyttas.</p>
          <label className="tb-field">Form
            <select value={item.closed ? "closed" : "open"} onChange={event => patch({ closed: event.target.value === "closed" })}>
              <option value="open">Öppen linje</option><option value="closed">Sluten yta mellan spelarna</option>
            </select>
          </label>
          <div className="tb-row">
            <label className="tb-field">Tjocklek
              <input type="range" min={0.15} max={0.8} step={0.05} value={item.width} onChange={event => patch({ width: Number(event.target.value) })} />
            </label>
            {item.closed && (
              <label className="tb-field">Fyllning
                <input type="range" min={0} max={1} step={0.05} value={item.fill} onChange={event => patch({ fill: Number(event.target.value) })} />
              </label>
            )}
          </div>
          {item.closed && (
            <label className="tb-field">Mönster
              <select value={item.pattern ?? "solid"} onChange={event => patch({ pattern: event.target.value as AreaPattern })}>
                <option value="solid">Fylld</option><option value="stripes">Randig</option>
              </select>
            </label>
          )}
          <label className="tb-check"><input type="checkbox" checked={item.dashed} onChange={event => patch({ dashed: event.target.checked })} />Streckad</label>
          <label className="tb-check"><input type="checkbox" checked={item.rings !== false} onChange={event => patch({ rings: event.target.checked })} />Ringar vid spelarna</label>
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

/** The order buttons: where, the label, what it does, and its key. */
const stackings: [Stacking, string, string, string][] = [
  ["top", "⤒", "Lägg överst", "Home"],
  ["up", "↑", "Ett steg upp", "Page Up"],
  ["down", "↓", "Ett steg ner", "Page Down"],
  ["bottom", "⤓", "Lägg underst", "End"],
];

/** A part of the panel under its own heading. */
function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return <section className="tb-section" aria-label={title}><h4>{title}</h4>{children}</section>;
}

export function Inspector({ board }: { board: Board }) {
  const objects = useEditor(activeObjects);
  const selection = useEditor(state => state.selection);
  const frameIndex = useEditor(state => state.frameIndex);
  const selected = objects.filter(item => selection.includes(item.id));
  const { patch, changeObjects, removeSelected, duplicateSelected, groupSelected, select } = useEditor.getState();
  if (selected.length === 0) return <BoardSettings board={board} />;
  const single = selected.length === 1 ? selected[0] : null;
  const allLocked = selected.every(item => item.locked);
  const grouped = oneGroup(objects, selection);
  const action = (icon: string, label: string, hint: string, onClick: () => void, extra: { pressed?: boolean; disabled?: boolean; danger?: boolean } = {}) => (
    <button type="button" title={hint} aria-pressed={extra.pressed} disabled={extra.disabled} data-danger={extra.danger || undefined} onClick={onClick}>
      <span aria-hidden="true">{icon}</span>{label}
    </button>
  );
  return (
    <div className="tb-inspector">
      <div className="tb-inspector-head">
        <div>
          <h3>{single ? objectLabel(single, board) : grouped ? `Grupp med ${selected.length} objekt` : `${selected.length} markerade`}</h3>
          {single && <p className="tb-hint">{kindName(single.type)}</p>}
        </div>
        <button type="button" className="tb-link" title="Avmarkera" onClick={() => select([])}>Klar</button>
      </div>
      <div className="tb-selection-actions" role="group" aria-label="Åtgärder">
        {action("⧉", "Kopiera", "Kopiera (Ctrl+D)", duplicateSelected)}
        {(grouped || selected.length > 1) && action("⧈", grouped ? "Dela upp" : "Gruppera", grouped ? "Dela upp gruppen (Ctrl+Shift+G)" : "Gruppera (Ctrl+G)", () => groupSelected(!grouped), { pressed: grouped })}
        {action(allLocked ? "🔒" : "🔓", allLocked ? "Lås upp" : "Lås", allLocked ? "Lås upp, så kan det ändras och flyttas" : "Lås, så flyttas det inte av misstag",
          () => patch(Object.fromEntries(selected.map(item => [item.id, { locked: !allLocked }]))), { pressed: allLocked })}
        {action("🗑", "Ta bort", "Ta bort (Delete)", removeSelected, { disabled: allLocked, danger: true })}
      </div>
      {allLocked && <p className="tb-hint">{single ? "Objektet" : "Objekten"} är låst. Lås upp för att ändra.</p>}
      {single && !single.locked && <Section title="Utseende"><Fields item={single} board={board} /></Section>}
      {single && !single.locked && board.frames.length > 1 && frameIndex > 0 && <Section title="Rörelse i framen"><Motion item={single} frameIndex={frameIndex} /></Section>}
      {!single && selected.filter(item => !item.locked).length > 1 && <Section title="Gemensamt"><SharedFields items={selected} board={board} /></Section>}
      <Section title="Ordning i lagret">
        <div className="tb-stacking" role="group" aria-label="Ordning">
          {stackings.map(([where, icon, hint, key]) => (
            <button key={where} type="button" className="wt-button secondary small" title={`${hint} (${key})`} aria-label={hint}
              onClick={() => changeObjects(current => stack(current, selection, where))}>{icon}</button>
          ))}
        </div>
      </Section>
      {single && (
        <label className="tb-field">Namn i listan
          <input value={single.label ?? ""} maxLength={40} placeholder={objectLabel({ ...single, label: undefined }, board)}
            onChange={event => patch({ [single.id]: { label: event.target.value || undefined } })} />
        </label>
      )}
      <CopyTo key={`${frameIndex}:${selection.join()}`} board={board} ids={selected.map(item => item.id)} />
    </div>
  );
}
