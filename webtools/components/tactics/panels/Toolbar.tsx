"use client";

// The tools: select, place players and equipment, draw passes, runs, dribbles and
// areas, and measure: sizes shown on areas and lines (on or off), and a
// ruler from one point to another. A placing tool stays in hand for several taps; a drawing tool goes
// back to select after one stroke. On a wide screen the palette can be
// wider, a short word under each icon, two or three to a row; the choice
// stays in this browser. A phone has them in groups (PhoneToolbar).
import { useEffect, useState } from "react";
import { useEditor, type Tool } from "../store.ts";
import { PhoneToolbar } from "./PhoneToolbar.tsx";

/** Whether the screen is a phone's: the tools then come in groups. */
function useNarrow() {
  const [narrow, setNarrow] = useState(false);
  useEffect(() => {
    const query = window.matchMedia("(max-width: 760px)");
    const update = () => setNarrow(query.matches);
    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);
  return narrow;
}

export type Item = { tool: Tool; label: string; short: string; icon: string };

export const groups: { title: string; items: Item[] }[] = [
  { title: "Markera", items: [{ tool: "select", label: "Markera och flytta", short: "Markera", icon: "↖" }] },
  {
    title: "Placera",
    items: [
      { tool: "player-home", label: "Spelare, hemmalag", short: "Hemma", icon: "●" },
      { tool: "player-away", label: "Spelare, bortalag", short: "Borta", icon: "●" },
      { tool: "ball", label: "Boll", short: "Boll", icon: "⚽" },
      { tool: "cone", label: "Kon", short: "Kon", icon: "▲" },
      { tool: "pole", label: "Pinne", short: "Pinne", icon: "┃" },
      { tool: "mannequin", label: "Docka", short: "Docka", icon: "⬬" },
      { tool: "goal", label: "Mål", short: "Mål", icon: "⊐" },
      { tool: "text", label: "Text", short: "Text", icon: "T" },
    ],
  },
  {
    title: "Rita",
    items: [
      { tool: "arrow", label: "Passning", short: "Pass", icon: "→" },
      { tool: "run", label: "Löpning", short: "Löpning", icon: "⇢" },
      { tool: "dribble", label: "Dribbling", short: "Dribbling", icon: "⤳" },
      { tool: "line", label: "Linje", short: "Linje", icon: "／" },
      { tool: "freehand", label: "Frihand", short: "Frihand", icon: "〰" },
      { tool: "rect", label: "Yta", short: "Yta", icon: "▭" },
      { tool: "ellipse", label: "Zon", short: "Zon", icon: "◯" },
    ],
  },
  { title: "Mät", items: [{ tool: "ruler", label: "Linjal: mät från en punkt till en annan", short: "Linjal", icon: "📏" }] },
];

type Size = "compact" | "labels";
const KEY = "teamzone:tactics:toolbar";

/** The palette's size: as chosen in this browser, else with words on a wide screen. */
function useToolbarSize(): [Size, (size: Size) => void] {
  const [size, setSize] = useState<Size>("compact");
  useEffect(() => {
    let saved: string | null = null;
    try { saved = localStorage.getItem(KEY); } catch { /* storage unavailable */ }
    setSize(saved === "labels" || saved === "compact" ? saved : window.innerWidth >= 1280 ? "labels" : "compact");
  }, []);
  const choose = (next: Size) => {
    setSize(next);
    try { localStorage.setItem(KEY, next); } catch { /* storage unavailable */ }
  };
  return [size, choose];
}

/** onHelp: the list of keys and tips. */
export function Toolbar({ homeColor, awayColor, onHelp }: { homeColor: string; awayColor: string; onHelp?: () => void }) {
  const tool = useEditor(state => state.tool);
  const setTool = useEditor(state => state.setTool);
  const measure = useEditor(state => state.measure);
  const [size, setSize] = useToolbarSize();
  const narrow = useNarrow();
  if (narrow) return <PhoneToolbar homeColor={homeColor} awayColor={awayColor} />;
  return (
    <nav className="tb-tools" data-size={size} aria-label="Verktyg">
      {groups.map(group => (
        <div key={group.title} className="tb-tool-group" role="group" aria-label={group.title}>
          {size === "labels" && <span className="tb-tool-heading">{group.title}</span>}
          {group.items.map(item => (
            <button key={item.tool} type="button" title={item.label} aria-label={item.label} aria-pressed={tool === item.tool}
              onClick={() => setTool(tool === item.tool ? "select" : item.tool)}
              style={item.tool === "player-home" ? { color: homeColor } : item.tool === "player-away" ? { color: awayColor } : undefined}>
              <span className="tb-tool-icon" aria-hidden="true">{item.icon}</span>
              <span className="tb-tool-label" aria-hidden="true">{item.short}</span>
            </button>
          ))}
          {group.title === "Mät" && (
            <button type="button" title="Visa mått på ytor och linjer" aria-label="Visa mått på ytor och linjer" aria-pressed={measure}
              onClick={() => useEditor.getState().setMeasure(!measure)}>
              <span className="tb-tool-icon" aria-hidden="true">m²</span>
              <span className="tb-tool-label" aria-hidden="true">Mått</span>
            </button>
          )}
        </div>
      ))}
      {onHelp && (
        <button type="button" className="tb-tools-help" onClick={onHelp} aria-label="Kortkommandon och tips" title="Kortkommandon och tips (?)">?</button>
      )}
      <button type="button" className="tb-tools-size" onClick={() => setSize(size === "labels" ? "compact" : "labels")}
        aria-label={size === "labels" ? "Smalare verktyg utan text" : "Bredare verktyg med text"}
        title={size === "labels" ? "Smalare verktyg utan text" : "Bredare verktyg med text"}>
        {size === "labels" ? "«" : "»"}
      </button>
    </nav>
  );
}
