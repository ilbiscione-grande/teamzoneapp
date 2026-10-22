"use client";

// The tools: select, place players and equipment, draw passes, runs and
// areas. A placing tool stays in hand for several taps; a drawing tool goes
// back to select after one stroke.
import { useEditor, type Tool } from "../store.ts";

type Item = { tool: Tool; label: string; icon: string };

const groups: { title: string; items: Item[] }[] = [
  { title: "Markera", items: [{ tool: "select", label: "Markera och flytta", icon: "↖" }] },
  {
    title: "Placera",
    items: [
      { tool: "player-home", label: "Spelare, hemmalag", icon: "●" },
      { tool: "player-away", label: "Spelare, bortalag", icon: "●" },
      { tool: "ball", label: "Boll", icon: "⚽" },
      { tool: "cone", label: "Kon", icon: "▲" },
      { tool: "pole", label: "Pinne", icon: "┃" },
      { tool: "mannequin", label: "Docka", icon: "⬬" },
      { tool: "goal", label: "Mål", icon: "⊐" },
      { tool: "text", label: "Text", icon: "T" },
    ],
  },
  {
    title: "Rita",
    items: [
      { tool: "arrow", label: "Passning", icon: "→" },
      { tool: "run", label: "Löpning", icon: "⇢" },
      { tool: "line", label: "Linje", icon: "／" },
      { tool: "freehand", label: "Frihand", icon: "〰" },
      { tool: "rect", label: "Yta", icon: "▭" },
      { tool: "ellipse", label: "Zon", icon: "◯" },
    ],
  },
];

export function Toolbar({ homeColor, awayColor }: { homeColor: string; awayColor: string }) {
  const tool = useEditor(state => state.tool);
  const setTool = useEditor(state => state.setTool);
  return (
    <nav className="tb-tools" aria-label="Verktyg">
      {groups.map(group => (
        <div key={group.title} className="tb-tool-group" role="group" aria-label={group.title}>
          {group.items.map(item => (
            <button key={item.tool} type="button" title={item.label} aria-label={item.label} aria-pressed={tool === item.tool}
              onClick={() => setTool(tool === item.tool ? "select" : item.tool)}
              style={item.tool === "player-home" ? { color: homeColor } : item.tool === "player-away" ? { color: awayColor } : undefined}>
              <span aria-hidden="true">{item.icon}</span>
            </button>
          ))}
        </div>
      ))}
    </nav>
  );
}
