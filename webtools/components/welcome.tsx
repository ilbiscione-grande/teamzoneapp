"use client";

import Link from "next/link";
import { useAccount } from "./account";
import { Bold, useT } from "./language";
import { LegalStep } from "./shell";

/** The start page's account line: who you are, or how to sign in. */
export function Welcome() {
  const { ready, available, session, legal, accepted, displayName, connections, links, error } = useAccount();
  const t = useT();
  if (!ready) return <div className="wt-welcome" aria-busy="true" />;
  if (!available) return null;
  if (!session) {
    return (
      <div className="wt-welcome">
        <p>{links.tacticsboardOnly
          ? t("Skapa ett konto och prova Tacticsboard gratis, eller logga in.")
          : t("Logga in med ditt TeamZone-konto för att använda apparna. Du behöver inte vara kopplad till något lag.")}</p>
        <div className="wt-actions">
          <Link className="wt-button" href="/logga-in">{t("Logga in")}</Link>
          <Link className="wt-button secondary" href="/logga-in?skapa=1">{t("Skapa konto")}</Link>
        </div>
      </div>
    );
  }
  if (error) return <p className="wt-welcome" role="alert">{error}</p>;
  if (legal && !accepted) return <LegalStep />;
  const name = displayName || session.user.email || "";
  const count = connections?.length ?? 0;
  return (
    <div className="wt-welcome">
      <p>
        <Bold text={t("Inloggad som {value}")} value={name} />
        {connections && (count > 0
          ? <> · {count === 1 ? t("en koppling till lag och klubbar i TeamZone") : t("{count} kopplingar till lag och klubbar i TeamZone", { count })}</>
          : !links.tacticsboardOnly && <> · {t("inte kopplad till något lag, och det behövs inte")}</>)}
      </p>
      <Link className="wt-link" href="/konto">{links.tacticsboardOnly ? t("Ditt konto") : t("Ditt konto och dina kopplingar")}</Link>
    </div>
  );
}
