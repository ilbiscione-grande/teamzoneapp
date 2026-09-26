"use client";

import { useEffect, useState } from "react";
import { loadOwnTeamEvents, type OwnTeamEvent } from "../lib/own-team-events";
import { usePersonalAccount } from "./personal-account";

export function OwnTeamEvents() {
  const { client, session } = usePersonalAccount();
  const [result, setResult] = useState<{ account: string; hasTeams: boolean; items: OwnTeamEvent[] } | null>(null);
  const [error, setError] = useState(false);
  const [loading, setLoading] = useState(false);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    if (!client || !session) return;
    let disposed = false;
    const account = session.user.id;
    setResult(null); setError(false); setLoading(true);
    const start = new Date();
    const end = new Date(start.getTime() + 90 * 86400000);
    loadOwnTeamEvents((name, params) => client.schema("api").rpc(name, params), start.toISOString(), end.toISOString())
      .then(data => { if (!disposed) setResult({ ...data, account }); })
      .catch(() => { if (!disposed) setError(true); })
      .finally(() => { if (!disposed) setLoading(false); });
    return () => { disposed = true; };
  }, [client, session, revision]);
  // Hide previous-account data in the very render that changes the session.
  if (!session) return null;
  const visible = result?.account === session.user.id ? result : null;
  return <section className="panel home-section" id="mina-laghandelser">
    <div className="section-heading"><div><p className="eyebrow">För dig i laget</p><h2>Möten och aktiviteter</h2></div><button disabled={loading} onClick={() => setRevision(v => v + 1)}>Uppdatera</button></div>
    <p>Kommande 90 dagar i dina egna lag. Här visas bara händelser du har behörighet att se.</p>
    {loading && <p role="status">Hämtar lagets händelser…</p>}
    {error && <p role="alert">Lagets händelser kunde inte hämtas. Försök uppdatera igen.</p>}
    {visible && (visible.items.length ? <div className="event-list">{visible.items.map(item => <article key={item.event_id}>
      <time dateTime={item.starts_at}>{new Intl.DateTimeFormat("sv-SE", { dateStyle: "medium", ...(item.all_day ? {} : { timeStyle: "short" as const }) }).format(new Date(item.starts_at))}</time>
      <div><strong>{item.title}</strong><span>{item.event_type === "meeting" ? "Möte" : "Aktivitet"} · {item.team_name}{item.location_name ? ` · ${item.location_name}` : ""}</span></div>
    </article>)}</div> : <div className="empty-note">{visible.hasTeams ? "Inga kommande möten eller aktiviteter i dina lag." : "Du behöver en lagkoppling i TeamZone för att se lagets möten och aktiviteter. Att följa laget ger inte tillgång."}</div>)}
  </section>;
}
