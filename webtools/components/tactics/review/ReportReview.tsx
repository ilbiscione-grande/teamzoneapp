"use client";

// Support's list of reported items in the library (plan item 16): the open
// ones first, or all ever reported; each with its first board, its reports
// and where it stands, and "Granska" to see it whole and decide.
import Link from "next/link";
import { useEffect, useState } from "react";
import { libraryKindLabels } from "../../../lib/tactics/library.ts";
import { openReports, reviewStatus, type ReportedItem } from "../../../lib/tactics/reports.ts";
import { ProjectThumb, type BoardPreview } from "../home/ProjectThumb.tsx";
import { ReportedItemDialog } from "./ReportedItemDialog.tsx";
import { ReportList } from "./ReportList.tsx";
import { useReportReview, useSupportAdmin } from "./use-report-review.ts";
import "../tactics.css";
import "../home/home.css";
import "./review.css";

export function ReportReview() {
  const support = useSupportAdmin();
  if (support === null) return <p className="wt-status">Laddar…</p>;
  if (!support) return <p className="wt-status">Sidan är bara för supporten.</p>;
  return <ReviewList />;
}

function ReviewList() {
  const { items, error, refresh, whole, decide } = useReportReview();
  const [onlyOpen, setOnlyOpen] = useState(true);
  const [open, setOpen] = useState<ReportedItem | null>(null);
  useEffect(() => { void refresh(onlyOpen); }, [onlyOpen, refresh]);

  return (
    <div className="tb-review">
      {open && <ReportedItemDialog item={open} load={whole} decide={decide} error={error}
        onClose={changed => { setOpen(null); if (changed) void refresh(onlyOpen); }} />}
      <div className="tb-home-actions">
        <Link className="wt-link" href="/tacticsboard/bibliotek">← Biblioteket</Link>
        <div className="tb-segments" role="group" aria-label="Visa">
          <button type="button" aria-pressed={onlyOpen} onClick={() => setOnlyOpen(true)}>Väntar på beslut</button>
          <button type="button" aria-pressed={!onlyOpen} onClick={() => setOnlyOpen(false)}>Alla anmälda</button>
        </div>
      </div>
      {error && !open && <p className="wt-error" role="alert">{error}</p>}
      {items === null ? <p className="wt-status">Laddar…</p> : items.length === 0 ? (
        <p className="tb-empty">{onlyOpen ? "Inga anmälningar väntar." : "Inget har anmälts än."}</p>
      ) : (
        <ul className="tb-review-list">
          {items.map(item => (
            <li key={item.id} className="wt-panel">
              <ProjectThumb preview={(item as ReportedItem & { preview?: BoardPreview | null }).preview} />
              <div>
                <strong>{item.title}</strong>
                <p className="tb-hint">{[libraryKindLabels[item.kind], `av ${item.author}`, item.club_name && `bara ${item.club_name}`].filter(Boolean).join(" · ")}</p>
                <p className="tb-review-status" data-hidden={item.hidden}>{reviewStatus(item)}</p>
                <ReportList reports={onlyOpen ? openReports(item) : item.reports} />
                <button type="button" className="wt-button small" onClick={() => setOpen(item)}>Granska</button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
