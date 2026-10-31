"use client";

// A short tip the first time a tool is taken: how it is used. Each tool's
// tip shows once in this browser, and all can be turned off.
import { useEffect, useState } from "react";
import { useEditor, type Tool } from "./store.ts";

const KEY = "teamzone:tactics:tips";

const PLACE = "Tryck på planen för att placera. Verktyget ligger kvar så att du kan placera flera, tills du väljer Markera eller trycker Esc.";
const tips: Partial<Record<Tool, string>> = {
  "player-home": PLACE,
  "player-away": PLACE,
  ball: "Tryck på planen för att lägga ut en boll. Läggs den nära en spelare fastnar den vid spelaren och följer med.",
  cone: PLACE, pole: PLACE, mannequin: PLACE, goal: PLACE,
  text: "Tryck där texten ska stå och skriv den sedan under Egenskaper.",
  arrow: "Dra från där passningen börjar till där den slutar. Dra sedan i mittpunkten för att böja den.",
  run: "Dra från där löpningen börjar till där den slutar. Dra sedan i mittpunkten för att böja den.",
  dribble: "Dra från där dribblingen börjar till där den slutar.",
  line: "Dra från en punkt till en annan.",
  freehand: "Rita fritt med fingret eller musen.",
  rect: "Dra från ett hörn till det motsatta. Måttet syns medan du drar om Mått är på.",
  ellipse: "Dra från ett hörn till det motsatta. Måttet syns medan du drar om Mått är på.",
  ruler: "Dra mellan två punkter för att se avståndet i meter.",
};

type Seen = { off?: boolean; tools: string[] };

function readSeen(): Seen {
  try {
    const value = JSON.parse(localStorage.getItem(KEY) ?? "null") as Seen | null;
    return value && Array.isArray(value.tools) ? value : { tools: [] };
  } catch { return { tools: [] }; }
}

function writeSeen(seen: Seen) {
  try { localStorage.setItem(KEY, JSON.stringify(seen)); } catch { /* storage unavailable */ }
}

export function ToolHint() {
  const tool = useEditor(state => state.tool);
  const [shown, setShown] = useState<Tool | null>(null);
  useEffect(() => {
    if (!tips[tool]) { setShown(null); return; }
    const seen = readSeen();
    if (seen.off || seen.tools.includes(tool)) { setShown(null); return; }
    writeSeen({ ...seen, tools: [...seen.tools, tool] });
    setShown(tool);
    const timer = setTimeout(() => setShown(current => (current === tool ? null : current)), 9000);
    return () => clearTimeout(timer);
  }, [tool]);
  if (!shown) return null;
  return (
    <div className="tb-tip" role="status">
      <span>{tips[shown]}</span>
      <span className="tb-tip-actions">
        <button type="button" className="tb-tip-off" onClick={() => { writeSeen({ ...readSeen(), off: true }); setShown(null); }}>Visa inga fler tips</button>
        <button type="button" className="tb-tip-close" aria-label="Stäng tipset" onClick={() => setShown(null)}>×</button>
      </span>
    </div>
  );
}

/** The tips shown again from the start (the list of keys offers it). */
export function resetTips() {
  writeSeen({ tools: [] });
}
