"use client";

// Starting and running a live lesson: guests or login only, the code, link
// and QR code to join with, who is in, and ending it; afterwards its
// summary, and the earlier lessons on the project.
import { useEffect, useState } from "react";
import { liveLink, type LiveSession } from "../../../lib/tactics/live.ts";
import { useAccount } from "../../account";
import { BigQr, QrCode } from "../QrCode.tsx";
import { useEditor } from "../store.ts";
import { saveNow } from "../use-autosave.ts";
import { useLive } from "./live-store.ts";
import { broadcastOnce } from "./use-live-host.ts";
import { endLesson } from "./use-live-idle.ts";
import { LiveHistory } from "./LiveHistory.tsx";
import { useT } from "../../language";

export function LiveDialog({ onClose }: { onClose: () => void }) {
  const t = useT();
  const { client } = useAccount();
  const meta = useEditor(state => state.meta);
  const session = useLive(state => state.session);
  const participants = useLive(state => state.participants);
  const channelError = useLive(state => state.channelError);
  const [guests, setGuests] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [bigQr, setBigQr] = useState(false);
  const [copied, setCopied] = useState(false);
  // A lesson's summary in sight: the one just ended, or one picked from the earlier lessons.
  const [summaryId, setSummaryId] = useState<string | null>(null);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const run = async (work: () => Promise<string | null>) => {
    setBusy(true); setError("");
    const failure = await work();
    setBusy(false);
    if (failure) setError(failure);
  };
  const start = () => run(async () => {
    if (!client || !meta) return null;
    // Participants read the board as last saved, then follow it live.
    if (useEditor.getState().saveState !== "saved") await saveNow(client);
    const { data, error: startError } = await client.schema("api").rpc("start_tactics_live", { target_project_id: meta.id, guests_allowed: guests });
    if (startError) return t("Lektionen kunde inte startas. Har projektet sparats?");
    useLive.getState().set({ session: data as LiveSession });
    return null;
  });
  const setAllowGuests = (allow: boolean) => run(async () => {
    if (!client || !session) return null;
    if (!allow && !window.confirm(t("Kräva inloggning? Gäster som är med nu kopplas bort."))) return null;
    if (!allow) await broadcastOnce(client, session.id, "guests-off");
    const { data, error: setError } = await client.schema("api").rpc("set_tactics_live_guests", { target_session_id: session.id, guests_allowed: allow });
    if (setError) return t("Inställningen kunde inte sparas.");
    useLive.getState().set({ session: data as LiveSession });
    return null;
  });
  const end = () => run(async () => {
    if (!client || !session || !window.confirm(t("Avsluta lektionen? Länken slutar fungera för alla."))) return null;
    const ended = session.id;
    await endLesson(client, ended);
    setSummaryId(ended);
    return null;
  });

  const link = session ? liveLink(window.location.origin, session.code) : "";
  const copy = async () => {
    try { await navigator.clipboard.writeText(link); setCopied(true); setTimeout(() => setCopied(false), 2000); } catch { /* copied by hand */ }
  };

  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label={t("Livelektion")} onClick={event => { if (event.target === event.currentTarget) onClose(); }}>
      <div className="tb-modal-card">
        {bigQr && session && <BigQr text={link} title={t("Kod {code}", { code: session.code })} onClose={() => setBigQr(false)} />}
        <div className="tb-modal-head">
          <h2>{t("Livelektion")}</h2>
          <button type="button" className="tb-modal-close" aria-label={t("Stäng")} onClick={onClose}>×</button>
        </div>
        {!session ? (
          <>
            {!summaryId && <>
              <p className="tb-hint">{t("Deltagarna följer tavlan som du visar den: tavla, frame, uppspelning och tidslinje, och din pekare över planen. De kan inte ändra något. Lektionen avslutas av sig själv efter 30 minuter utan aktivitet.")}</p>
              <label className="tb-check"><input type="checkbox" checked={guests} onChange={event => setGuests(event.target.checked)} />{t("Tillåt gäster utan konto (de skriver bara sitt namn)")}</label>
              <div className="tb-actions"><button type="button" className="wt-button small" disabled={busy} onClick={() => void start()}>{t("Starta livelektion")}</button></div>
            </>}
            {client && meta && <LiveHistory client={client} projectId={meta.id} open={summaryId} onOpen={setSummaryId} />}
          </>
        ) : (
          <>
            <div className="tb-live-join">
              <QrCode text={link} label={t("QR-kod för lektionen {code}", { code: session.code })} size={150} />
              <div>
                <span className="tb-hint">{t("Gå in på {host}/live och skriv koden", { host: window.location.host })}</span>
                <strong className="tb-live-code">{session.code}</strong>
                <div className="tb-actions">
                  <button type="button" className="wt-button small" onClick={() => void copy()}>{copied ? t("Kopierad") : t("Kopiera länken")}</button>
                  <button type="button" className="wt-button secondary small" onClick={() => setBigQr(true)}>{t("Visa stort")}</button>
                </div>
              </div>
            </div>
            <label className="tb-check"><input type="checkbox" checked={session.allow_guests} disabled={busy} onChange={event => void setAllowGuests(event.target.checked)} />{t("Tillåt gäster utan konto")}</label>
            <h3>{t("Med nu ({count})", { count: participants.length })}</h3>
            {participants.length === 0 ? <p className="tb-hint">{t("Ingen än. Deltagarna syns här när de har gått med.")}</p> : (
              <ul className="tb-live-people">
                {participants.map(person => <li key={person.key}>{person.name}{person.guest && <small> {t("gäst")}</small>}</li>)}
              </ul>
            )}
            <div className="tb-actions"><button type="button" className="wt-button secondary small" disabled={busy} onClick={() => void end()}>{t("Avsluta lektionen")}</button></div>
          </>
        )}
        {error && <p className="wt-error" role="alert">{error}</p>}
        {session && channelError && <p className="wt-error" role="alert">{t("Kanalen till deltagarna kunde inte öppnas ({error}).", { error: channelError })}</p>}
      </div>
    </div>
  );
}
