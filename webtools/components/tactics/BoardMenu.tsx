"use client";

// "+ Tavla": an empty board, a copy of the board in hand (put right after it), one of the ready
// boards for the project's kind, or the boards of one of your templates.
// The menu opens under the button, outside the tab row that scrolls.
import { useEffect, useRef, useState } from "react";
import { newBoard } from "../../lib/tactics/document.ts";
import type { Board } from "../../lib/tactics/model.ts";
import { boardsFromTemplate, starterBoard, starterSets } from "../../lib/tactics/templates.ts";
import { activeBoard, useEditor, NONE } from "./store.ts";
import { useTemplates } from "./use-templates.ts";

export function BoardMenu() {
  const [open, setOpen] = useState(false);
  const [at, setAt] = useState({ left: 0, top: 0 });
  const button = useRef<HTMLButtonElement>(null);
  const menu = useRef<HTMLDivElement>(null);
  const meta = useEditor(state => state.meta);
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const current = useEditor(activeBoard);
  const { templates, error, boardsOf } = useTemplates(open);

  useEffect(() => {
    if (!open) return;
    const close = (event: Event) => {
      if (event instanceof KeyboardEvent ? event.key === "Escape" : !menu.current?.contains(event.target as Node) && !button.current?.contains(event.target as Node)) setOpen(false);
    };
    window.addEventListener("pointerdown", close);
    window.addEventListener("keydown", close);
    return () => { window.removeEventListener("pointerdown", close); window.removeEventListener("keydown", close); };
  }, [open]);

  const toggle = () => {
    const rect = button.current?.getBoundingClientRect();
    if (rect) setAt({ left: Math.max(8, Math.min(rect.left, window.innerWidth - 288)), top: rect.bottom + 4 });
    setOpen(!open);
  };
  const add = (added: Board[]) => {
    if (added.length === 0) return;
    // New boards look like the board in hand, unless they bring their own look.
    const styled = added.map(item => (item.pitch || !current?.pitch ? item : { ...item, pitch: current.pitch }));
    useEditor.getState().change(document => ({ ...document, boards: [...document.boards, ...styled] }));
    useEditor.getState().setBoard(added[0].id);
    setOpen(false);
  };
  const home = boards[0]?.teams.home.name, away = boards[0]?.teams.away.name;
  const fromTemplate = async (id: string) => {
    const found = await boardsOf(id);
    if (found) add(boardsFromTemplate(found, meta?.teamName ?? undefined));
  };

  return (
    <>
      <button ref={button} type="button" className="tb-board-add" onClick={toggle} aria-haspopup="menu" aria-expanded={open}>+ Tavla</button>
      {open && (
        <div ref={menu} className="tb-menu" role="menu" style={{ left: at.left, top: at.top }}>
          <button type="button" role="menuitem" onClick={() => add([newBoard(`Tavla ${boards.length + 1}`, home, away)])}>Tom tavla</button>
          {current && <button type="button" role="menuitem" onClick={() => { useEditor.getState().duplicateBoard(current.id); setOpen(false); }}>Kopia av {current.name || "tavlan"}</button>}
          <span className="tb-menu-heading">Färdiga tavlor</span>
          {starterSets[meta?.kind ?? "match"].map(item => (
            <button key={item.key} type="button" role="menuitem" onClick={() => add([starterBoard(item, home, away)])}>{item.name}</button>
          ))}
          <span className="tb-menu-heading">Dina mallar</span>
          {error && <span className="tb-menu-note">{error}</span>}
          {templates === null ? <span className="tb-menu-note">Laddar…</span> : templates.length === 0 ? (
            <span className="tb-menu-note">Inga mallar än. Spara en under Tavlan → Spara som mall.</span>
          ) : templates.map(template => (
            <button key={template.id} type="button" role="menuitem" onClick={() => void fromTemplate(template.id)}>
              {template.name}
              <small>{template.boards.length === 1 ? template.boards[0].name : `${template.boards.length} tavlor`}</small>
            </button>
          ))}
        </div>
      )}
    </>
  );
}
