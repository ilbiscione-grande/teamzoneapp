import { Suspense } from "react";
import { RequireAccount } from "../../../components/shell";
import { ReportReview } from "../../../components/tactics/review/ReportReview.tsx";

export const metadata = { title: "Anmälningar · Tacticsboard", robots: { index: false } };

// Support's review of the library's reports; not behind the subscription.
export default function ReportReviewPage() {
  return (
    <div className="wt-wrap wt-section bk-page">
      <p className="wt-kicker dark">Tacticsboard</p>
      <h1 className="wt-page-title">Anmälningar</h1>
      <Suspense fallback={<p className="wt-status">Laddar…</p>}>
        <RequireAccount returnTo="/tacticsboard/granska">
          <ReportReview />
        </RequireAccount>
      </Suspense>
    </div>
  );
}
