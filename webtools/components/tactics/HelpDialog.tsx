"use client";

// The keys and handy ways of working, in one list: opened with ? or the
// button under the tools.
import { useEffect, useState } from "react";
import { resetTips } from "./ToolHint.tsx";

const sections: { title: string; rows: [string, string][] }[] = [
  {
    title: "Markera och flytta",
    rows: [
      ["Klick", "Markera ett objekt (hela gruppen om det är grupperat)"],
      ["Shift + klick", "Lägg till eller ta bort ur markeringen"],
      ["Dra över gräset", "Markera allt inom rutan"],
      ["Ctrl + pil", "Flytta det markerade en bit (med Shift längre)"],
      ["Dra till papperskorgen", "Ta bort det du drar"],
      ["Esc", "Tillbaka till Markera, inget markerat"],
    ],
  },
  {
    title: "Ändra",
    rows: [
      ["Ctrl + Z", "Ångra"],
      ["Ctrl + Y", "Gör om (även Ctrl + Shift + Z)"],
      ["Ctrl + D", "Kopiera det markerade"],
      ["Ctrl + G", "Gruppera det markerade"],
      ["Ctrl + Shift + G", "Dela upp gruppen"],
      ["Delete", "Ta bort det markerade"],
    ],
  },
  {
    title: "Ordning inom sitt lager",
    rows: [
      ["Page Up / Page Down", "Ett steg upp eller ner"],
      ["Home / End", "Överst eller underst"],
    ],
  },
  {
    title: "Animering",
    rows: [
      ["Mellanslag", "Spela eller pausa"],
      ["← / →", "Föregående eller nästa frame"],
    ],
  },
  {
    title: "Med fingret",
    rows: [
      ["Nyp", "Zooma in och ut"],
      ["Tryck på ett objekt", "Snabbmenyn visas ovanför det"],
      ["Dubbeltryck på mittpunkten", "Gör en böjd linje rak"],
    ],
  },
];

export function HelpDialog({ onClose }: { onClose: () => void }) {
  const [reset, setReset] = useState(false);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label="Kortkommandon och tips" onClick={event => { if (event.target === event.currentTarget) onClose(); }}>
      <div className="tb-modal-card tb-help">
        <div className="tb-modal-head">
          <h2>Kortkommandon och tips</h2>
          <button type="button" className="tb-modal-close" aria-label="Stäng" onClick={onClose}>×</button>
        </div>
        {sections.map(section => (
          <section key={section.title}>
            <h3>{section.title}</h3>
            <dl>
              {section.rows.map(([key, what]) => (
                <div key={key}><dt><kbd>{key}</kbd></dt><dd>{what}</dd></div>
              ))}
            </dl>
          </section>
        ))}
        <p className="tb-hint">På Mac används ⌘ i stället för Ctrl.</p>
        <div className="tb-actions">
          <button type="button" className="wt-button secondary small" disabled={reset} onClick={() => { resetTips(); setReset(true); }}>
            {reset ? "Tipsen visas igen" : "Visa verktygstipsen igen"}
          </button>
          <button type="button" className="wt-button small" onClick={onClose}>Stäng</button>
        </div>
      </div>
    </div>
  );
}
