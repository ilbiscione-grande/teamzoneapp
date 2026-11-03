// An item's reports, newest last: the reason, when, and how it was decided.
import type { ReportEntry } from "../../../lib/tactics/reports.ts";

const when = new Intl.DateTimeFormat("sv-SE", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
const resolutions = { hidden: "dold", dismissed: "behållen" } as const;

export function ReportList({ reports }: { reports: ReportEntry[] }) {
  return (
    <ul className="tb-review-reports">
      {reports.map((report, index) => (
        <li key={index} data-open={!report.resolved_at}>
          <span>{report.reason}</span>
          <small>{when.format(new Date(report.created_at))}{report.resolution && ` · ${resolutions[report.resolution]}`}</small>
        </li>
      ))}
    </ul>
  );
}
