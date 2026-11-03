"use client";

// Reporting an item of the library (plan item 16): a reason from the list
// and, if wished, a few words. Support reads it; three reports hide the item
// until support has decided.
import { useEffect, useState } from "react";
import { reportReady, reportReasons, reportText, type ReportReason } from "../../lib/tactics/reports.ts";
import "./share.css";

/** send: true when the report reached the server. */
export function ReportDialog({ title, send, onClose }: { title: string; send: (text: string) => Promise<boolean>; onClose: () => void }) {
  const [reason, setReason] = useState<ReportReason | "">("");
  const [words, setWords] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!reportReady(reason, words) || reason === "") return;
    setBusy(true);
    const sent = await send(reportText(reason, words));
    setBusy(false);
    if (sent) setDone(true);
  };

  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label={`Anmäl ${title}`} onClick={event => { if (event.target === event.currentTarget) onClose(); }}>
      <form className="tb-modal-card" onSubmit={submit}>
        <div className="tb-modal-head">
          <h2>Anmäl</h2>
          <button type="button" className="tb-modal-close" aria-label="Stäng" onClick={onClose}>×</button>
        </div>
        {done ? (
          <>
            <p>Tack. Supporten tittar på {title}. Får den flera anmälningar döljs den tills supporten har bestämt.</p>
            <div className="tb-actions"><button type="button" className="wt-button small" onClick={onClose}>Stäng</button></div>
          </>
        ) : (
          <>
            <p>Vad är fel med <strong>{title}</strong>?</p>
            <div className="tb-field" role="radiogroup" aria-label="Skäl">
              {reportReasons.map(([value, label]) => (
                <label key={value} className="tb-check">
                  <input type="radio" name="reason" checked={reason === value} onChange={() => setReason(value)} />{label}
                </label>
              ))}
            </div>
            <label className="tb-field">{reason === "other" ? "Beskriv vad som är fel" : "Mer om det (frivilligt)"}
              <textarea value={words} maxLength={400} rows={3} onChange={event => setWords(event.target.value)} />
            </label>
            <p className="tb-hint">Den som delat det får inte veta vem som anmält.</p>
            <div className="tb-actions">
              <button type="button" className="wt-button secondary small" onClick={onClose}>Avbryt</button>
              <button type="submit" className="wt-button small" disabled={busy || !reportReady(reason, words)}>{busy ? "Skickar…" : "Skicka anmälan"}</button>
            </div>
          </>
        )}
      </form>
    </div>
  );
}
