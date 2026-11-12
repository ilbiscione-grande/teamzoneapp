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
import { ObjectSwatches } from "./AllFrames.tsx";
import { TextLook } from "./TextLook.tsx";
import { PlayerLink } from "./PlayerLink.tsx";
import { SharedFields } from "./SharedFields.tsx";
import { useT } from "../../language";

function Fields({ item, board }: { item: TacticsObject; board: Board }) {
  const t = useT();
  const patch = (changes: Partial<TacticsObject>) => useEditor.getState().patch({ [item.id]: changes });
  const paint = (color: string | null) => useEditor.getState().patchLook({ [item.id]: { color } });
  switch (item.type) {
    case "player":
      return (
        <>
          <label className="tb-field">{t("Lag")}
            <select value={item.side} onChange={event => patch({ side: event.target.value as "home" | "away" })}>
              <option value="home">{t(board.teams.home.name)}</option>
              <option value="away">{t(board.teams.away.name)}</option>
            </select>
          </label>
          <PlayerLink item={item} />
          <label className="tb-field">{t("Namn")}<input value={item.name ?? ""} maxLength={40} onChange={event => patch({ name: event.target.value || null })} /></label>
          <div className="tb-row">
            <label className="tb-field">{t("Nummer")}
              <input inputMode="numeric" value={item.number ?? ""} maxLength={3}
                onChange={event => { const n = event.target.value.trim(); patch({ number: n === "" ? null : Number(n) || 0 }); }} />
            </label>
            <label className="tb-field">{t("Position")}
              <input value={item.position ?? ""} maxLength={12} placeholder={t("t.ex. MV")} onChange={event => patch({ position: event.target.value || null })} />
            </label>
          </div>
          {item.personId && <p className="tb-hint">{t("Hämtat från laget när spelaren kopplades. Det du skriver här gäller på tavlan.")}</p>}
          <div className="tb-field">{t("Blickriktning")}
            <div className="tb-facings" role="group" aria-label={t("Blickriktning")}>
              {facings.map(way => (
                <button key={way.angle} type="button" aria-label={t(way.label)} title={t(way.label)}
                  aria-pressed={Math.round(normalAngle(standingFacing(item))) === way.angle}
                  onClick={() => {
                    // Turning a player shows which way players face on this board.
                    if (!board.showFacing) useEditor.getState().change(document => updateBoard(document, board.id, current => ({ ...current, showFacing: true })));
                    patch({ rotation: facingToRotation(way.angle, item.side) });
                  }}>{way.arrow}</button>
              ))}
            </div>
            <span className="tb-hint">{t("Eller dra i den gula punkten framför spelaren.")}</span>
          </div>
          <ObjectSwatches label={t("Egen färg (t.ex. målvakt)")} value={item.color} onChange={paint} />
          {item.color && <button type="button" className="tb-link" onClick={() => paint(null)}>{t("Lagets färg")}</button>}
        </>
      );
    case "ball":
      return item.attachedTo
        ? <button type="button" className="wt-button secondary small" onClick={() => patch({ attachedTo: null, offset: null })}>{t("Släpp från spelaren")}</button>
        : <p className="tb-hint">{t("Släpp bollen nära en spelare så fäster den där.")}</p>;
    case "line":
    case "freehand":
      return (
        <>
          <div className="tb-row">
            <label className="tb-field">{t("Pilspets")}
              <select value={item.arrow} onChange={event => patch({ arrow: event.target.value as typeof item.arrow })}>
                <option value="none">{t("Ingen")}</option><option value="end">{t("I slutet")}</option><option value="both">{t("Båda ändar")}</option>
              </select>
            </label>
            <label className="tb-field">{t("Tjocklek")}
              <input type="range" min={0.15} max={0.8} step={0.05} value={item.width} onChange={event => patch({ width: Number(event.target.value) })} />
            </label>
          </div>
          <label className="tb-field">{t("Linje")}
            <select value={item.wavy ? "wavy" : item.dashed ? "dashed" : "solid"}
              onChange={event => patch({ dashed: event.target.value === "dashed", wavy: event.target.value === "wavy" })}>
              <option value="solid">{t("Heldragen (passning)")}</option><option value="dashed">{t("Streckad (löpning)")}</option><option value="wavy">{t("Vågig (dribbling)")}</option>
            </select>
          </label>
          {item.type === "line" && !item.dashed && !item.wavy && item.arrow !== "none" && (
            <div className="tb-field">{t("Passningen går")}
              <div className="tb-aligns" style={{ gridTemplateColumns: "1fr 1fr" }} role="group" aria-label={t("Passningen går")}>
                <button type="button" aria-pressed={!item.aerial} onClick={() => patch({ aerial: false })}>{t("På marken")}</button>
                <button type="button" aria-pressed={!!item.aerial} onClick={() => patch({ aerial: true })}>{t("I luften")}</button>
              </div>
            </div>
          )}
          {item.type === "line" && item.from && <button type="button" className="tb-link" onClick={() => patch({ from: null })}>{t("Släpp från spelaren")}</button>}
          {item.type === "line" && item.control && <button type="button" className="tb-link" onClick={() => patch({ control: null })}>{t("Gör rak")}</button>}
          {item.type === "line" && <p className="tb-hint">{t("Dra i mittpunkten för att böja linjen.")}</p>}
          <ObjectSwatches label={t("Färg")} value={item.color} onChange={paint} />
        </>
      );
    case "rect":
    case "ellipse":
      return (
        <>
          <label className="tb-field">{t("Fyllning")}
            <input type="range" min={0} max={1} step={0.05} value={item.fill} onChange={event => patch({ fill: Number(event.target.value) })} />
          </label>
          <label className="tb-field">{t("Mönster")}
            <select value={item.pattern ?? "solid"} onChange={event => patch({ pattern: event.target.value as AreaPattern })}>
              <option value="solid">{t("Fylld")}</option><option value="stripes">{t("Randig")}</option>
            </select>
          </label>
          <label className="tb-check"><input type="checkbox" checked={item.dashed} onChange={event => patch({ dashed: event.target.checked })} />{t("Streckad kant")}</label>
          <ObjectSwatches label={t("Färg")} value={item.color} onChange={paint} />
        </>
      );
    case "text":
      return (
        <>
          <label className="tb-field">{t("Text")}<textarea rows={2} maxLength={500} value={item.text} onChange={event => patch({ text: event.target.value })} /></label>
          <label className="tb-field">{t("Textstorlek")}
            <input type="range" min={0.8} max={8} step={0.2} value={item.size} onChange={event => patch({ size: Number(event.target.value) })} />
          </label>
          {item.width != null && <button type="button" className="tb-link" onClick={() => patch({ width: null, height: null })}>{t("Anpassa rutan efter texten")}</button>}
          <ObjectSwatches label={t("Textfärg")} value={item.color} onChange={paint} />
          <TextLook texts={[item]} />
        </>
      );
    case "chain":
      return (
        <>
          <p className="tb-hint">{t("Går genom {count} spelare och följer dem när de flyttas.", { count: item.players.length })}</p>
          <label className="tb-field">{t("Form")}
            <select value={item.closed ? "closed" : "open"} onChange={event => patch({ closed: event.target.value === "closed" })}>
              <option value="open">{t("Öppen linje")}</option><option value="closed">{t("Sluten yta mellan spelarna")}</option>
            </select>
          </label>
          <div className="tb-row">
            <label className="tb-field">{t("Tjocklek")}
              <input type="range" min={0.15} max={0.8} step={0.05} value={item.width} onChange={event => patch({ width: Number(event.target.value) })} />
            </label>
            {item.closed && (
              <label className="tb-field">{t("Fyllning")}
                <input type="range" min={0} max={1} step={0.05} value={item.fill} onChange={event => patch({ fill: Number(event.target.value) })} />
              </label>
            )}
          </div>
          {item.closed && (
            <label className="tb-field">{t("Mönster")}
              <select value={item.pattern ?? "solid"} onChange={event => patch({ pattern: event.target.value as AreaPattern })}>
                <option value="solid">{t("Fylld")}</option><option value="stripes">{t("Randig")}</option>
              </select>
            </label>
          )}
          <label className="tb-check"><input type="checkbox" checked={item.dashed} onChange={event => patch({ dashed: event.target.checked })} />{t("Streckad")}</label>
          <label className="tb-check"><input type="checkbox" checked={item.rings !== false} onChange={event => patch({ rings: event.target.checked })} />{t("Ringar vid spelarna")}</label>
          <ObjectSwatches label={t("Färg")} value={item.color} onChange={paint} />
        </>
      );
    default:
      return (
        <>
          <label className="tb-field">{t("Storlek")}
            <input type="range" min={0.4} max={3} step={0.1} value={item.scale} onChange={event => patch({ scale: Number(event.target.value) })} />
          </label>
          <ObjectSwatches label={t("Färg")} value={item.color} onChange={paint} />
        </>
      );
  }
}

/** The object's effects in this frame (chosen under Frames), its path's bend, and how a passed ball travels. */
function Motion({ item, frameIndex }: { item: TacticsObject; frameIndex: number }) {
  const t = useT();
  const patch = (changes: Partial<TacticsObject>) => useEditor.getState().patch({ [item.id]: changes });
  return (
    <>
      {frameIndex > 0 && <p className="tb-hint">{t("Effekter i framen: {list}. Effekter väljer du under Frames.", { list: effectsOf(item).map(kind => t(effects[kind].label)).join(", ") || t("inga") })}</p>}
      {frameIndex > 0 && item.pathControl && <button type="button" className="tb-link" onClick={() => patch({ pathControl: null })}>{t("Rak väg hit")}</button>}
      {frameIndex > 0 && !item.pathControl && <p className="tb-hint">{t("Dra i punkten mitt på spåret för att böja vägen hit.")}</p>}
      {frameIndex > 0 && item.type === "ball" && (
        <BallFlightChoice flight={item.flight ?? "ground"} onChange={flight => patch({ flight } as Partial<TacticsObject>)} />
      )}
    </>
  );
}

/** How the ball travels into this frame: on the ground or in the air, and then how high, the way a pass arrow is chosen. */
function BallFlightChoice({ flight, onChange }: { flight: BallFlight; onChange: (flight: BallFlight) => void }) {
  const t = useT();
  const two = { gridTemplateColumns: "1fr 1fr" };
  return (
    <>
      <div className="tb-field">{t("Bollen går hit")}
        <div className="tb-aligns" style={two} role="group" aria-label={t("Bollen går hit")}>
          <button type="button" aria-pressed={flight === "ground"} onClick={() => onChange("ground")}>{t("På marken")}</button>
          <button type="button" aria-pressed={flight !== "ground"} onClick={() => { if (flight === "ground") onChange("chip"); }}>{t("I luften")}</button>
        </div>
      </div>
      {flight !== "ground" && (
        <div className="tb-field">{t("Höjd")}
          <div className="tb-aligns" style={two} role="group" aria-label={t("Höjd")}>
            <button type="button" aria-pressed={flight === "chip"} onClick={() => onChange("chip")}>{t("Chip (lyft)")}</button>
            <button type="button" aria-pressed={flight === "high"} onClick={() => onChange("high")}>{t("Långboll (hög)")}</button>
          </div>
        </div>
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
  const t = useT();
  const objects = useEditor(activeObjects);
  const selection = useEditor(state => state.selection);
  const frameIndex = useEditor(state => state.frameIndex);
  const allFrames = useEditor(state => state.allFrames);
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
          <h3>{single ? objectLabel(single, board, t) : grouped ? t("Grupp med {count} objekt", { count: selected.length }) : t("{count} markerade", { count: selected.length })}</h3>
          {single && <p className="tb-hint">{kindName(single.type, t)}</p>}
        </div>
        <button type="button" className="tb-link" title={t("Avmarkera")} onClick={() => select([])}>{t("Klar")}</button>
      </div>
      <div className="tb-selection-actions" role="group" aria-label={t("Åtgärder")}>
        {action("⧉", t("Kopiera"), t("Kopiera (Ctrl+D)"), duplicateSelected)}
        {(grouped || selected.length > 1) && action("⧈", grouped ? t("Dela upp") : t("Gruppera"), grouped ? t("Dela upp gruppen (Ctrl+Shift+G)") : t("Gruppera (Ctrl+G)"), () => groupSelected(!grouped), { pressed: grouped })}
        {action(allLocked ? "🔒" : "🔓", allLocked ? t("Lås upp") : t("Lås"), allLocked ? t("Lås upp, så kan det ändras och flyttas") : t("Lås, så flyttas det inte av misstag"),
          () => patch(Object.fromEntries(selected.map(item => [item.id, { locked: !allLocked }]))), { pressed: allLocked })}
        {action("🗑", t("Ta bort"), allFrames ? t("Ta bort ur alla frames (Delete)") : t("Ta bort (Delete)"), () => removeSelected(), { disabled: allLocked, danger: true })}
      </div>
      {allLocked && <p className="tb-hint">{single ? t("Objektet är låst. Lås upp för att ändra.") : t("Objekten är låsta. Lås upp för att ändra.")}</p>}
      {single && !single.locked && <Section title={t("Utseende")}><Fields item={single} board={board} /></Section>}
      {single && !single.locked && board.frames.length > 1 && frameIndex > 0 && <Section title={t("Rörelse i framen")}><Motion item={single} frameIndex={frameIndex} /></Section>}
      {!single && selected.filter(item => !item.locked).length > 1 && <Section title={t("Gemensamt")}><SharedFields items={selected} board={board} /></Section>}
      <Section title={t("Ordning i lagret")}>
        <div className="tb-stacking" role="group" aria-label={t("Ordning")}>
          {stackings.map(([where, icon, hint, key]) => (
            <button key={where} type="button" className="wt-button secondary small" title={`${t(hint)} (${key})`} aria-label={t(hint)}
              onClick={() => changeObjects(current => stack(current, selection, where))}>{icon}</button>
          ))}
        </div>
      </Section>
      {single && (
        <label className="tb-field">{t("Namn i listan")}
          <input value={single.label ?? ""} maxLength={40} placeholder={objectLabel({ ...single, label: undefined }, board, t)}
            onChange={event => patch({ [single.id]: { label: event.target.value || undefined } })} />
        </label>
      )}
      <CopyTo key={`${frameIndex}:${selection.join()}`} board={board} ids={selected.map(item => item.id)} />
    </div>
  );
}
