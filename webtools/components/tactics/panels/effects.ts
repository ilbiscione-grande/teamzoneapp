// The effects to choose from: what each is called, what it does, and which
// objects it suits. Drawing in is for lines only.
import type { Effect, TacticsObject } from "../../../lib/tactics/model.ts";

export const effects: Record<Effect, { label: string; icon: string; hint: string }> = {
  fade: { label: "Tona in", icon: "◐", hint: "Tonar fram. Nya objekt gör det av sig själva." },
  pop: { label: "Poppa fram", icon: "✦", hint: "Växer fram och studsar till." },
  draw: { label: "Rita fram", icon: "✎", hint: "Linjen ritas från start till mål." },
  pulse: { label: "Puls", icon: "◎", hint: "Pulserar för att dra blicken till sig." },
  highlight: { label: "Lys upp", icon: "✺", hint: "En gul glöd runt objektet." },
};

export const effectKinds = Object.keys(effects) as Effect[];

export function effectSuits(kind: Effect, item: TacticsObject): boolean {
  return kind !== "draw" || item.type === "line" || item.type === "freehand";
}
