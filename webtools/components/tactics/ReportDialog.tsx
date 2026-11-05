"use client";

// Reporting an item of the library (plan item 16): a reason from the list
// and, if wished, a few words. Support reads it; three reports hide the item
// until support has decided.
import { useEffect, useState } from "react";
import { reportReady, reportReasons, reportText, type ReportReason } from "../../lib/tactics/reports.ts";
import { Bold, useT } from "../language";
import "./share.css";

/** send: true when the report reached the server. */
export function ReportDialog({ title, send, onClose }: { title: string; send: (text: string) => Promise<boolean>; onClose: () => void }) {
  const t = useT();
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
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label={t("Anmäl {name}", { name: title })} onClick={event => { if (event.target === event.currentTarget) onClose(); }}>
      <form className="tb-modal-card" onSubmit={submit}>
        <div className="tb-modal-head">
          <h2>{t("Anmäl")}</h2>
          <button type="button" className="tb-modal-close" aria-label={t("Stäng")} onClick={onClose}>×</button>
        </div>
        {done ? (
          <>
            <p>{t("Tack. Supporten tittar på {name}. Får den flera anmälningar döljs den tills supporten har bestämt.", { name: title })}</p>
            <div className="tb-actions"><button type="button" className="wt-button small" onClick={onClose}>{t("Stäng")}</button></div>
          </>
        ) : (
          <>
            <p><Bold text={t("Vad är fel med {value}?")} value={title} /></p>
            <div className="tb-field" role="radiogroup" aria-label={t("Skäl")}>
              {reportReasons.map(([value, label]) => (
                <label key={value} className="tb-check">
                  <input type="radio" name="reason" checked={reason === value} onChange={() => setReason(value)} />{t(label)}
                </label>
              ))}
            </div>
            <label className="tb-field">{reason === "other" ? t("Beskriv vad som är fel") : t("Mer om det (frivilligt)")}
              <textarea value={words} maxLength={400} rows={3} onChange={event => setWords(event.target.value)} />
            </label>
            <p className="tb-hint">{t("Den som delat det får inte veta vem som anmält.")}</p>
            <div className="tb-actions">
              <button type="button" className="wt-button secondary small" onClick={onClose}>{t("Avbryt")}</button>
              <button type="submit" className="wt-button small" disabled={busy || !reportReady(reason, words)}>{busy ? t("Skickar…") : t("Skicka anmälan")}</button>
            </div>
          </>
        )}
      </form>
    </div>
  );
}
