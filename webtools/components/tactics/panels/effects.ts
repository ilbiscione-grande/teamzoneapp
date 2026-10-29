// The effects to choose from: what each is called, what it does, and which
// objects it suits. Drawing in is for lines only; a trail, an arrow and a
// ring for what moves; zooming for anything. An
// object may have several in the same frame; they play together.
import type { Easing, Effect, TacticsObject, ZoomLevel } from "../../../lib/tactics/model.ts";

export const effects: Record<Effect, { label: string; icon: string; hint: string }> = {
  fade: { label: "Tona in", icon: "◐", hint: "Tonar fram. Nya objekt gör det av sig själva." },
  pop: { label: "Poppa fram", icon: "✦", hint: "Växer fram och studsar till." },
  draw: { label: "Rita fram", icon: "✎", hint: "Linjen ritas från start till mål." },
  pulse: { label: "Puls", icon: "◎", hint: "Pulserar för att dra blicken till sig." },
  highlight: { label: "Lys upp", icon: "✺", hint: "En gul glöd runt objektet." },
  trail: { label: "Spår", icon: "⋯", hint: "Lämnar ett streckat spår efter sig, så man ser var det kom ifrån." },
  arrow: { label: "Pil", icon: "➜", hint: "En streckad pil visar vägen först och försvinner bakom objektet när det rör sig." },
  ring: { label: "Markera", icon: "◯", hint: "En streckad ring i objektets färg runt det." },
  zoom: { label: "Zooma", icon: "⌕", hint: "Zoomar in på objektet och stannar där. Zoomar nästa frame inte, zoomar den ut igen." },
};

export const effectKinds = Object.keys(effects) as Effect[];

const MOVING = new Set(["player", "ball", "cone", "pole", "mannequin", "goal", "text"]);

export function effectSuits(kind: Effect, item: TacticsObject): boolean {
  if (kind === "draw") return item.type === "line" || item.type === "freehand";
  if (kind === "trail" || kind === "arrow" || kind === "ring") return MOVING.has(item.type);
  return true;
}

/** How a move speeds up and slows down, for the frame's choice. */
export const easingLabels: Record<Easing, string> = {
  smooth: "Mjuk start och inbromsning",
  linear: "Jämn fart hela vägen",
  in: "Mjuk start",
  out: "Mjuk inbromsning",
};

/** How close the zoom effect goes, for an object's choice. */
export const zoomLabels: Record<ZoomLevel, string> = { close: "Nära", medium: "Mellan", wide: "Lite" };
