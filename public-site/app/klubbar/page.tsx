"use client";

import Link from "next/link";
import { useState } from "react";
import { PortalFooter, PortalHeader, PortalHero, portalClass } from "../../components/portal";
import { FollowButton } from "../../components/follow-button";

type Club = { kind: "club" | "team"; id: string; slug: string; name: string; locality?: string; official: boolean; visibility: "listed" | "published"; club_slug?: string; club_name?: string; age_class?: string };

export default function ClubCatalog() {
  const [query, setQuery] = useState("");
  const [items, setItems] = useState<Club[]>([]);
  const [message, setMessage] = useState("Skriv minst tre tecken för att söka.");
  const [busy, setBusy] = useState(false);
  const [hasMore, setHasMore] = useState(false);

  async function search(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (query.trim().length < 3) {
      setItems([]);
      setHasMore(false);
      setMessage("Skriv minst tre tecken för att söka.");
      return;
    }
    setBusy(true);
    setItems([]);
    setHasMore(false);
    setMessage("Söker…");
    try {
      const response = await fetch(`/api/public/v1/directory/search?q=${encodeURIComponent(query.trim())}`, { cache: "no-store" });
      if (!response.ok) throw new Error("search_failed");
      const data = await response.json() as { items?: Club[]; has_more?: boolean };
      setItems(data.items ?? []);
      setHasMore(data.has_more === true);
      setMessage((data.items ?? []).length === 0 ? "Inga klubbar eller lag matchade sökningen." : "");
    } catch {
      setItems([]);
      setMessage("Sökningen kunde inte genomföras. Försök igen senare.");
    } finally {
      setBusy(false);
    }
  }

  return <main className={portalClass}>
    <PortalHeader active="search" />
    <PortalHero kicker="Klubbar och lag" title="Hitta en klubb eller ett lag">
      <p className="pz-lead">Sök på klubbnamn, lagnamn, ort eller åldersklass. Du kan kombinera flera ord, till exempel Thomas Vetlanda.</p>
      <form onSubmit={search} role="search" className="pz-search">
        <label htmlFor="club-query" className="pz-visually-hidden">Klubb, lag, ort eller åldersklass</label>
        <input id="club-query" value={query} disabled={busy} onChange={(event) => setQuery(event.target.value)} minLength={3} maxLength={80} placeholder="Exempel: Vetlanda, Thomas lag, J18" aria-describedby="search-help" />
        <button type="submit" className="cs-button" disabled={busy}>{busy ? "Söker…" : "Sök"}</button>
      </form>
      <p id="search-help" className="pz-note">Skriv minst tre tecken. Början av ett ord räcker. Både officiellt verifierade och inofficiella klubbar kan finnas i katalogen. Märkningen visar skillnaden.</p>
    </PortalHero>
    <section className="cs-section alt pz-results">
      <div className="cs-wrap">
        {message && <p role="status" className="cs-empty">{message}</p>}
        {items.length > 0 && <div className="pz-result-grid">
          {items.map((club) => <article className="pz-result" key={`${club.kind}:${club.id}`}>
            <span className="cs-crest cs-crest-sm cs-crest-initials" aria-hidden="true">{club.name.split(/\s+/).filter(Boolean).slice(0, 2).map(word => word[0]?.toUpperCase()).join("")}</span>
            <div className="pz-result-body">
              <p className="cs-kicker">{club.kind === "team" ? "Lag" : "Klubb"}</p>
              <h2>{club.visibility === "published" ? <Link href={club.kind === "team" ? `/${club.club_slug}/${club.slug}` : `/${club.slug}`}>{club.name}</Link> : club.name}</h2>
              {club.kind === "team" && <p>{club.club_name}{club.age_class ? ` · ${club.age_class}` : ""}</p>}
              <p className={club.official ? "pz-official" : undefined}>{club.official ? "Officiellt verifierad klubb" : "Inofficiell klubb"}{club.locality ? ` · ${club.locality}` : ""}</p>
              {club.visibility === "listed" && <p>Enbart katalogpost – ingen publik klubbsida ännu.</p>}
            </div>
            {club.visibility === "published" && <FollowButton channel={club} />}
          </article>)}
        </div>}
        {hasMore && <p role="status" className="pz-note dark">Det finns fler träffar. Lägg till exempelvis ort eller åldersklass för att begränsa sökningen.</p>}
      </div>
    </section>
    <PortalFooter />
  </main>;

}
