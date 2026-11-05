"use client";

import { Suspense, useState } from "react";
import { groupConnections } from "../lib/account";
import { useAccount } from "./account";
import { RequireAccount } from "./shell";
import { AccountDeletion } from "./account-deletion";
import { NewPasswordForm } from "./password";
import { TacticsboardSubscription } from "./tactics/TacticsboardSubscription.tsx";
import { useT } from "./language";

function PasswordSection() {
  const t = useT();
  const [open, setOpen] = useState(false);
  const [changed, setChanged] = useState(false);
  return (
    <section className="wt-panel" aria-labelledby="password-title">
      <h2 id="password-title">{t("Lösenord")}</h2>
      {changed && <p className="wt-note" role="status">{t("Lösenordet är bytt.")}</p>}
      {open ? (
        <NewPasswordForm submitLabel={t("Byt lösenord")} onDone={() => { setOpen(false); setChanged(true); }} />
      ) : (
        <button type="button" className="wt-button secondary" onClick={() => { setOpen(true); setChanged(false); }}>{t("Byt lösenord")}</button>
      )}
    </section>
  );
}

function AccountDetails() {
  const t = useT();
  const { session, displayName, connections, links } = useAccount();
  const groups = groupConnections(connections ?? []);
  return (
    <div className="wt-account">
      <section className="wt-panel">
        <h2>{t("Ditt konto")}</h2>
        <dl className="wt-facts">
          {displayName && <><dt>{t("Namn")}</dt><dd>{displayName}</dd></>}
          <dt>{t("E-post")}</dt><dd>{session?.user.email}</dd>
        </dl>
        <p className="wt-small">{t("Samma konto fungerar i alla appar i Webtools.")}{displayName && links.appUrl && <> {t("Namnet ändrar du i")} <a href={links.appUrl}>{t("TeamZone-appen")}</a>.</>}</p>
      </section>
      <PasswordSection />
      <section className="wt-panel" aria-labelledby="subscriptions-title">
        <h2 id="subscriptions-title">{t("Abonnemang")}</h2>
        <Suspense fallback={<p className="wt-status">{t("Laddar…")}</p>}>
          <TacticsboardSubscription />
        </Suspense>
      </section>
      {(links.appUrl || groups.length > 0) && <section className="wt-panel" aria-labelledby="connections-title">
        <h2 id="connections-title">{t("Lag och klubbar")}</h2>
        {connections === null ? <p className="wt-status">{t("Laddar…")}</p> : groups.length === 0 ? (
          <>
            <p>{t("Du är inte med i något lag eller någon klubb. Det behövs inte för att använda Webtools.")}</p>
            {links.appUrl && <p className="wt-small">{t("Har din klubb TeamZone och du har fått en lagkod eller en inbjudan, använder du den i")} <a href={links.appUrl}>{t("TeamZone-appen")}</a>. {t("Då kan apparna här också använda laget, till exempel truppen i Tacticsboard.")}</p>}
          </>
        ) : (
          <>
            <p className="wt-small">{t("Apparna kan använda de här lagen och klubbarna, till exempel truppen i en laguppställning.")}</p>
            <ul className="wt-connections">
              {groups.map(group => (
                <li key={group.clubId}>
                  <strong>{group.club}</strong>
                  <ul>{group.items.map(item => <li key={item.name}>{t(item.name)} <span>{item.roles.map(role => t(role)).join(" · ")}</span></li>)}</ul>
                </li>
              ))}
            </ul>
          </>
        )}
      </section>}
      <AccountDeletion />
    </div>
  );
}

export function AccountPage() {
  return <RequireAccount returnTo="/konto"><AccountDetails /></RequireAccount>;
}
