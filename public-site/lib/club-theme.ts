// Club colours for the public club and team pages. The page links a small
// same-origin stylesheet (inline styles are blocked by the CSP) whose
// variables are derived here so text stays readable whatever the club picks:
// the primary colour is darkened until it works as a dark surface, and the
// accent falls back to white where it would not stand out against it.

const hex = /^#?([0-9a-f]{6})$/i;

export function normalizeColor(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const match = hex.exec(value.trim());
  return match ? match[1].toLowerCase() : null;
}

export function clubThemeHref(primary: unknown, accent: unknown): string | null {
  const p = normalizeColor(primary);
  const a = normalizeColor(accent);
  if (!p && !a) return null;
  const query = new URLSearchParams();
  if (p) query.set("p", p);
  if (a) query.set("a", a);
  return `/api/public/v1/club-theme?${query.toString()}`;
}

type Rgb = [number, number, number];

function parse(value: string): Rgb {
  return [0, 2, 4].map((i) => Number.parseInt(value.slice(i, i + 2), 16)) as Rgb;
}
function css([r, g, b]: Rgb) { return `#${[r, g, b].map((v) => Math.round(v).toString(16).padStart(2, "0")).join("")}`; }
function mix(a: Rgb, b: Rgb, t: number): Rgb { return [0, 1, 2].map((i) => a[i] + (b[i] - a[i]) * t) as Rgb; }
function luminance(rgb: Rgb) {
  const [r, g, b] = rgb.map((v) => { const c = v / 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function contrast(a: Rgb, b: Rgb) { const [x, y] = [luminance(a), luminance(b)].sort((m, n) => n - m); return (x + 0.05) / (y + 0.05); }

const black: Rgb = [0, 0, 0];
const white: Rgb = [255, 255, 255];
const defaultInk: Rgb = parse("0b111c");
const defaultAccent: Rgb = parse("c6f04d");

export function clubThemeCss(primary: unknown, accent: unknown): string | null {
  const p = normalizeColor(primary);
  const a = normalizeColor(accent);
  if (!p && !a) return null;
  const base = p ? parse(p) : defaultInk;
  // A dark surface for header, hero and footer.
  let ink = base;
  for (let t = 0.05; luminance(ink) > 0.06 && t <= 0.95; t += 0.05) ink = mix(base, black, t);
  const accentRgb = a ? parse(a) : defaultAccent;
  const accentText = contrast(accentRgb, ink) >= 3 ? accentRgb : white;
  const accentInk = contrast(accentRgb, parse("0b111c")) >= contrast(accentRgb, white) ? parse("0b111c") : white;
  // Kickers and links on white use the club colour when it is dark enough.
  const brand = contrast(base, white) >= 4.5 ? base : contrast(ink, white) >= 4.5 ? ink : parse("1f8a4c");
  const deep = mix(ink, black, 0.45);
  const vars = {
    "--cs-ink": css(ink),
    "--cs-ink-2": css(mix(ink, white, 0.05)),
    "--cs-ink-3": css(mix(ink, white, 0.11)),
    "--cs-deep": css(deep),
    "--cs-accent": css(accentRgb),
    "--cs-accent-ink": css(accentInk),
    "--cs-accent-text": css(accentText),
    "--cs-brand": css(brand),
  };
  const body = Object.entries(vars).map(([key, value]) => `${key}:${value}`).join(";");
  return `.cs.cs-theme{${body}}\nbody:has(.cs-theme){background:${css(deep)}}\n`;
}
