"use client";

// The project's own look (Branding): a club's logo, read from a picture
// the user picks, made at most 256 px and kept in the document, and where
// it shows on every board: faint in the centre circle or by the corner flag.
import { useRef, useState } from "react";
import type { Branding } from "../../../lib/tactics/model.ts";
import { useEditor } from "../store.ts";

const places: Record<Branding["place"], string> = { centre: "I mittcirkeln", corner: "Vid hörnflaggan", none: "Visas inte" };

/**
 * A picture as a PNG data URL no larger than `max` px either way. Read as a
 * data URL: the page's rules allow pictures from data URLs, not blob URLs.
 */
async function shrink(file: File, max = 256): Promise<string> {
  const source = await new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
  const image = await new Promise<HTMLImageElement>((resolve, reject) => {
    const element = new Image();
    element.onload = () => resolve(element);
    element.onerror = reject;
    element.src = source;
  });
  const scale = Math.min(1, max / Math.max(image.width, image.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(image.width * scale));
  canvas.height = Math.max(1, Math.round(image.height * scale));
  canvas.getContext("2d")?.drawImage(image, 0, 0, canvas.width, canvas.height);
  return canvas.toDataURL("image/png");
}

export function BrandingFields() {
  const branding = useEditor(state => state.document?.branding);
  const input = useRef<HTMLInputElement>(null);
  const [error, setError] = useState("");
  const set = (next: Branding | undefined) => useEditor.getState().change(document => {
    const { branding: _old, ...rest } = document;
    return next ? { ...rest, branding: next } : rest;
  });

  const pick = async (file: File) => {
    setError("");
    if (!file.type.startsWith("image/")) { setError("Välj en bild, till exempel PNG eller JPG."); return; }
    try {
      set({ logo: await shrink(file), place: branding?.place && branding.place !== "none" ? branding.place : "centre" });
    } catch {
      setError("Bilden kunde inte läsas.");
    }
  };

  return (
    <div className="tb-branding">
      <span className="tb-field">Klubbens logga</span>
      <input ref={input} type="file" accept="image/*" hidden onChange={event => { const file = event.target.files?.[0]; event.target.value = ""; if (file) void pick(file); }} />
      {branding?.logo ? (
        <div className="tb-branding-row">
          <img src={branding.logo} alt="Loggan" className="tb-branding-logo" />
          <select className="tb-panel-select" value={branding.place} aria-label="Var loggan visas"
            onChange={event => set({ ...branding, place: event.target.value as Branding["place"] })}>
            {Object.entries(places).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
          <button type="button" className="tb-link" onClick={() => set(undefined)}>Ta bort</button>
        </div>
      ) : (
        <button type="button" className="wt-button secondary small" onClick={() => input.current?.click()}>Lägg till logga…</button>
      )}
      {error && <p className="wt-error" role="alert">{error}</p>}
    </div>
  );
}
