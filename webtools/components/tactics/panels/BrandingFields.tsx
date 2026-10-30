"use client";

// The project's own look (Branding): a club's logo, read from a picture
// the user picks or the club's badge in TeamZone, made at most 256 px and
// kept in the document (so a shared link shows it too), and where it shows
// on every board: faint in the centre circle or by the corner flag.
import { useEffect, useRef, useState } from "react";
import type { TacticsClub } from "../../../lib/tactics/library.ts";
import type { Branding } from "../../../lib/tactics/model.ts";
import { useAccount } from "../../account";
import { useEditor } from "../store.ts";

const places: Record<Branding["place"], string> = { centre: "I mittcirkeln", corner: "Vid hörnflaggan", none: "Visas inte" };

/**
 * A picture as a PNG data URL no larger than `max` px either way. Read as a
 * data URL: the page's rules allow pictures from data URLs, not blob URLs.
 */
async function shrink(file: Blob, max = 256): Promise<string> {
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

/** The clubs you lead, whose badge can be fetched; none when signed out (the demo). */
function useClubs() {
  const { client, session } = useAccount();
  const [clubs, setClubs] = useState<TacticsClub[]>([]);
  useEffect(() => {
    if (!client || !session) { setClubs([]); return; }
    void client.schema("api").rpc("list_my_tactics_clubs").then(({ data }) => setClubs((data as TacticsClub[] | null) ?? []));
  }, [client, session]);
  return { client, clubs };
}

export function BrandingFields() {
  const branding = useEditor(state => state.document?.branding);
  const input = useRef<HTMLInputElement>(null);
  const [error, setError] = useState("");
  const { client, clubs } = useClubs();
  const [clubId, setClubId] = useState("");
  const [fetching, setFetching] = useState(false);
  const club = clubs.find(item => item.club_id === clubId) ?? clubs[0];
  const set = (next: Branding | undefined) => useEditor.getState().change(document => {
    const { branding: _old, ...rest } = document;
    return next ? { ...rest, branding: next } : rest;
  });

  const place = branding?.place && branding.place !== "none" ? branding.place : "centre";
  const pick = async (file: File) => {
    setError("");
    if (!file.type.startsWith("image/")) { setError("Välj en bild, till exempel PNG eller JPG."); return; }
    try {
      set({ logo: await shrink(file), place });
    } catch {
      setError("Bilden kunde inte läsas.");
    }
  };
  /** The badge on the club's profile: where it is stored, read with your own sign-in. */
  const fetchBadge = async () => {
    if (!client || !club) return;
    setError("");
    setFetching(true);
    try {
      const { data, error: denied } = await client.schema("api").rpc("authorize_club_badge", { target_club_id: club.club_id });
      const badge = data as { bucket_id: string; object_key: string } | null;
      if (denied) throw denied;
      if (!badge) { setError(`${club.club_name} har inget klubbmärke i TeamZone än.`); return; }
      const { data: file, error: missing } = await client.storage.from(badge.bucket_id).download(badge.object_key);
      if (missing || !file) throw missing ?? new Error("no badge");
      set({ logo: await shrink(file), place });
    } catch {
      setError("Klubbmärket kunde inte hämtas.");
    } finally {
      setFetching(false);
    }
  };
  const fromTeamZone = club && (
    <div className="tb-branding-row">
      {clubs.length > 1 && (
        <select className="tb-panel-select" value={club.club_id} aria-label="Klubb" onChange={event => setClubId(event.target.value)}>
          {clubs.map(item => <option key={item.club_id} value={item.club_id}>{item.club_name}</option>)}
        </select>
      )}
      <button type="button" className="wt-button secondary small" disabled={fetching} onClick={() => void fetchBadge()}
        title={`Klubbmärket från ${club.club_name} i TeamZone`}>
        {fetching ? "Hämtar…" : clubs.length > 1 ? "Hämta klubbmärket" : `Klubbmärket från ${club.club_name}`}
      </button>
    </div>
  );

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
        <>
          {fromTeamZone}
          <button type="button" className="wt-button secondary small" onClick={() => input.current?.click()}>{club ? "Annan bild…" : "Lägg till logga…"}</button>
        </>
      )}
      {error && <p className="wt-error" role="alert">{error}</p>}
    </div>
  );
}
