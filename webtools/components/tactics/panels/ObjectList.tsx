"use client";

// Everything on the board, the top-most first: choose, show or hide, lock,
// or remove; drag a row up or down to draw it above or below the others.
// The chosen objects stand out and are kept in sight; a locked one says so
// plainly. Choosing keeps the list in sight (Shift, Ctrl or Cmd adds to the
// selection); a double click opens the object's properties.
import { Fragment, useEffect, useRef, useState } from "react";
import { kindName, LAYERS, layered, layerOf, moveNextTo, objectLabel } from "../../../lib/tactics/document.ts";
import type { Board, TacticsObject } from "../../../lib/tactics/model.ts";
import { activeObjects, useEditor } from "../store.ts";

const icon = (item: TacticsObject, board: Board) => {
  if (item.type === "player") return <span className="tb-dot" style={{ background: item.color ?? board.teams[item.side].color }} />;
  return <span className="tb-kind" aria-hidden="true">{kindName(item.type).slice(0, 1)}</span>;
};

/** Where a dragged row would go: before (above) or after (below) a row. */
type Drop = { id: string; after: boolean };

export function ObjectList({ board, onOpen }: { board: Board; onOpen: () => void }) {
  const objects = useEditor(activeObjects);
  const selection = useEditor(state => state.selection);
  const { select, patch, changeObjects } = useEditor.getState();
  const [dragged, setDragged] = useState<string | null>(null);
  const [drop, setDrop] = useState<Drop | null>(null);
  const list = useRef<HTMLUListElement>(null);
  // The chosen object, chosen on the pitch too, scrolled into sight.
  useEffect(() => {
    list.current?.querySelector("li[data-selected='true']")?.scrollIntoView({ block: "nearest" });
  }, [selection]);
  // Drawn last is on top, so listed first: the balls, then the players, then the rest.
  const listed = [...layered(objects)].reverse();
  const layerOfDragged = dragged ? layerOf(objects.find(item => item.id === dragged) ?? { type: "" }) : null;
  if (listed.length === 0) {
    return <p className="tb-empty">Tavlan är tom. Välj ett verktyg och tryck på planen, eller lägg ut en formation.</p>;
  }
  const end = () => { setDragged(null); setDrop(null); };
  const place = (target: Drop) => {
    if (!dragged || dragged === target.id) return end();
    // Listed top-most first: below a row is under it in the drawing order.
    changeObjects(current => moveNextTo(current, dragged, target.id, !target.after));
    end();
  };
  return (
    <>
      <p className="tb-hint">Bollar ligger alltid överst, sedan spelarna och underst allt annat. Dra en rad upp eller ner för att ändra ordningen i sin grupp.</p>
      <ul ref={list} className="tb-objects" aria-label="Objekt på tavlan" onDragLeave={event => {
        if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setDrop(null);
      }}>
        {listed.map((item, index) => {
          const layer = layerOf(item);
          const heading = index === 0 || layerOf(listed[index - 1]) !== layer;
          const selected = selection.includes(item.id);
          const marker = drop?.id === item.id && dragged !== item.id ? (drop.after ? "after" : "before") : undefined;
          return (
            <Fragment key={item.id}>
            {heading && <li className="tb-layer" aria-hidden="true">{LAYERS[layer]}</li>}
            <li data-selected={selected} data-hidden={item.hidden} data-locked={item.locked} data-drop={marker}
              data-dragging={dragged === item.id} draggable
              onDragStart={event => { setDragged(item.id); event.dataTransfer.effectAllowed = "move"; event.dataTransfer.setData("text/plain", item.id); }}
              onDragEnd={end}
              onDragOver={event => {
                // Only within its own layer.
                if (!dragged || layerOfDragged !== layer) return;
                event.preventDefault();
                const box = event.currentTarget.getBoundingClientRect();
                const after = event.clientY > box.top + box.height / 2;
                if (drop?.id !== item.id || drop.after !== after) setDrop({ id: item.id, after });
              }}
              onDrop={event => { event.preventDefault(); if (drop) place(drop); }}>
              <span className="tb-grip" aria-hidden="true">⋮⋮</span>
              <button type="button" className="tb-object-name" aria-current={selected || undefined}
                onClick={event => select([item.id], event.shiftKey || event.metaKey || event.ctrlKey)}
                onDoubleClick={() => { select([item.id]); onOpen(); }}>
                {icon(item, board)}
                <span className="tb-object-label">{objectLabel(item, board)}</span>
                {item.locked && <span className="tb-locked-tag">🔒 Låst</span>}
              </button>
              <span className="tb-object-actions">
                <button type="button" title={item.hidden ? "Visa" : "Dölj"} aria-label={item.hidden ? "Visa" : "Dölj"} aria-pressed={item.hidden}
                  onClick={() => patch({ [item.id]: { hidden: !item.hidden } })}>{item.hidden ? "◌" : "◉"}</button>
                <button type="button" className="tb-lock" data-on={item.locked} title={item.locked ? "Lås upp" : "Lås"}
                  aria-label={item.locked ? "Lås upp" : "Lås"} aria-pressed={item.locked}
                  onClick={() => patch({ [item.id]: { locked: !item.locked } })}>{item.locked ? "🔒" : "🔓"}</button>
                <button type="button" title="Ta bort" aria-label="Ta bort" disabled={item.locked}
                  onClick={() => changeObjects(current => current.filter(other => other.id !== item.id))}>✕</button>
              </span>
            </li>
            </Fragment>
          );
        })}
      </ul>
    </>
  );
}
