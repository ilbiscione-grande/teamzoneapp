"use client";

import { groupConnections } from "../lib/account";
import { useAccount } from "./account";
import { RequireAccount } from "./shell";

function AccountDetails() {
  const { session, displayName, connections, links } = useAccount();
  const groups = groupConnections(connections ?? []);
  return (
    <div className="wt-account">
      <section className="wt-panel">
        <h2>Ditt konto</h2>
        <dl className="wt-facts">
          {displayName && <><dt>Namn</dt><dd>{displayName}</dd></>}
          <dt>E-post</dt><dd>{session?.user.email}</dd>
        </dl>
        <p className="wt-small">Det här är ditt TeamZone-konto. Namn och lösenord ändrar du i <a href={links.appUrl}>TeamZone-appen</a>.</p>
      </section>
      <section className="wt-panel" aria-labelledby="subscriptions-title">
        <h2 id="subscriptions-title">Abonnemang</h2>
        <p>Du har inga abonnemang än. När apparna öppnar kan du köpa dem en och en, i paket eller få dem via din klubb i TeamZone.</p>
      </section>
      <section className="wt-panel" aria-labelledby="connections-title">
        <h2 id="connections-title">Lag och klubbar</h2>
        {connections === null ? <p className="wt-status">Laddar…</p> : groups.length === 0 ? (
          <>
            <p>Du är inte kopplad till något lag eller någon klubb. Det behövs inte för att använda Webtools.</p>
            <p className="wt-small">Har du fått en lagkod eller en inbjudan använder du den i <a href={links.appUrl}>TeamZone-appen</a>. Då kan apparna här också använda laget.</p>
          </>
        ) : (
          <>
            <p className="wt-small">Apparna kan använda de här lagen och klubbarna, till exempel truppen i en laguppställning.</p>
            <ul className="wt-connections">
              {groups.map(group => (
                <li key={group.clubId}>
                  <strong>{group.club}</strong>
                  <ul>{group.items.map(item => <li key={item.name}>{item.name} <span>{item.roles.join(" · ")}</span></li>)}</ul>
                </li>
              ))}
            </ul>
          </>
        )}
      </section>
    </div>
  );
}

export function AccountPage() {
  return <RequireAccount returnTo="/konto"><AccountDetails /></RequireAccount>;
}
