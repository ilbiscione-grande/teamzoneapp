"use client";

// Everything on the board, the top-most first: choose, show or hide, lock,
// move up or down, or remove. Players are grouped by team.
import { kindName, objectLabel, restack } from "../../../lib/tactics/document.ts";
import type { Board, TacticsObject } from "../../../lib/tactics/model.ts";
import { activeObjects, useEditor } from "../store.ts";

const icon = (item: TacticsObject, board: Board) => {
  if (item.type === "player") return <span className="tb-dot" style={{ background: item.color ?? board.teams[item.side].color }} />;
  return <span className="tb-kind" aria-hidden="true">{kindName(item.type).slice(0, 1)}</span>;
};

export function ObjectList({ board }: { board: Board }) {
  const objects = useEditor(activeObjects);
  const selection = useEditor(state => state.selection);
  const { select, patch, changeObjects } = useEditor.getState();
  // Drawn last is on top, so listed first.
  const listed = [...objects].reverse();
  if (listed.length === 0) {
    return <p className="tb-empty">Tavlan är tom. Välj ett verktyg och tryck på planen, eller lägg ut en formation.</p>;
  }
  return (
    <ul className="tb-objects" aria-label="Objekt på tavlan">
      {listed.map(item => {
        const selected = selection.includes(item.id);
        return (
          <li key={item.id} data-selected={selected} data-hidden={item.hidden}>
            <button type="button" className="tb-object-name" onClick={event => select([item.id], event.shiftKey || event.metaKey || event.ctrlKey)}>
              {icon(item, board)}
              <span>{objectLabel(item, board)}</span>
            </button>
            <span className="tb-object-actions">
              <button type="button" title={item.hidden ? "Visa" : "Dölj"} aria-label={item.hidden ? "Visa" : "Dölj"} aria-pressed={item.hidden}
                onClick={() => patch({ [item.id]: { hidden: !item.hidden } })}>{item.hidden ? "◌" : "◉"}</button>
              <button type="button" title={item.locked ? "Lås upp" : "Lås"} aria-label={item.locked ? "Lås upp" : "Lås"} aria-pressed={item.locked}
                onClick={() => patch({ [item.id]: { locked: !item.locked } })}>{item.locked ? "🔒" : "🔓"}</button>
              <button type="button" title="Flytta upp" aria-label="Flytta upp" onClick={() => changeObjects(current => restack(current, item.id, 1))}>↑</button>
              <button type="button" title="Flytta ned" aria-label="Flytta ned" onClick={() => changeObjects(current => restack(current, item.id, -1))}>↓</button>
              <button type="button" title="Ta bort" aria-label="Ta bort" disabled={item.locked}
                onClick={() => changeObjects(current => current.filter(other => other.id !== item.id))}>✕</button>
            </span>
          </li>
        );
      })}
    </ul>
  );
}
