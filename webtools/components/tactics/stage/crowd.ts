"use client";

// The crowd in an arena's stands: a small picture of spectators repeated
// over the stands, made once, so a stand is one shape however large.

/** A tile of spectators: dots in many colours on a dark terrace, the same each time. */
export function crowdTile(): HTMLCanvasElement | null {
  if (typeof document === "undefined") return null;
  const canvas = document.createElement("canvas");
  canvas.width = 96;
  canvas.height = 96;
  const context = canvas.getContext("2d");
  if (!context) return null;
  context.fillStyle = "#1c2430";
  context.fillRect(0, 0, 96, 96);
  const colours = ["#e5e7eb", "#ef4444", "#3b82f6", "#facc15", "#22c55e", "#f97316", "#a855f7", "#94a3b8", "#0f172a"];
  let seed = 7;
  const next = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  for (let y = 4; y < 96; y += 8) {
    for (let x = 4; x < 96; x += 8) {
      context.fillStyle = colours[Math.floor(next() * colours.length)];
      context.beginPath();
      context.arc(x + (next() - 0.5) * 3, y + (next() - 0.5) * 2, 2.6, 0, Math.PI * 2);
      context.fill();
    }
  }
  return canvas;
}
