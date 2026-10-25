import { Suspense } from "react";
import { RequireAccount } from "../../../components/shell";
import { SharedLibrary } from "../../../components/tactics/SharedLibrary.tsx";

export const metadata = { title: "TeamZones bibliotek · Tacticsboard" };

export default function SharedLibraryPage() {
  return (
    <div className="wt-wrap wt-section bk-page">
      <p className="wt-kicker dark">Tacticsboard</p>
      <h1 className="wt-page-title">TeamZones bibliotek</h1>
      <Suspense fallback={<p className="wt-status">Laddar…</p>}>
        <RequireAccount returnTo="/tacticsboard/bibliotek">
          <SharedLibrary />
        </RequireAccount>
      </Suspense>
    </div>
  );
}
