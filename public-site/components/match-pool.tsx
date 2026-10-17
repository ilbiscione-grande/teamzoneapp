"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { usePersonalAccount } from "./personal-account";
import { PortalHero } from "./portal";
import {
  defaultFilters, filterListings, formatLabel, formats, genderLabels, interestStateLabels, levelLabels, listingPayload,
  newKey, poolError, slotLabel, stockholmInstant, surfaceLabels, todayInStockholm, whenLabel,
  type Conversation, type Filters, type Gender, type Interest, type Level, type Listing, type ListingDraft, type Place,
  type PoolPage, type PoolTeam, type Surface,
} from "../lib/match-pool";

// POOL-01: matchpoolen for leaders. Listings from other teams with the
// club's verification shown on every card, own listings with the interests
// they got, sent interests, and a conversation per interest.

type Tab = "find" | "mine" | "sent";
const distances = [10, 25, 50, 100, 200, 500];

export function MatchPool() {
  const { client, session, ready, enabled, error: accountError } = usePersonalAccount();
  const [page, setPage] = useState<PoolPage | null>(null);
  const [error, setError] = useState("");
  const [notLeader, setNotLeader] = useState(false);
  const [origin, setOrigin] = useState<string>("");
  const [maxKm, setMaxKm] = useState(100);
  const [filters, setFilters] = useState<Filters>(defaultFilters);
  const [tab, setTab] = useState<Tab>("find");
  const [conversation, setConversation] = useState<string | null>(null);
  const [interestFor, setInterestFor] = useState<Listing | null>(null);
  const [creating, setCreating] = useState(false);
  const [editingBase, setEditingBase] = useState(false);
  const loaded = useRef(0);

  const load = useCallback(async () => {
    if (!client || !session) return;
    const version = ++loaded.current;
    setError("");
    const { data, error: rpcError } = await client.schema("api").rpc("get_match_pool", { origin_team_id: origin || null, max_km: maxKm });
    if (version !== loaded.current) return;
    if (rpcError) {
      if (rpcError.message.includes("not_leader")) setNotLeader(true);
      else setError(poolError(rpcError));
      return;
    }
    const next = data as PoolPage;
    setPage(next);
    if (!origin && next.teams.length > 0) setOrigin((next.teams.find(team => team.base) ?? next.teams[0]).team_id);
  }, [client, session, origin, maxKm]);

  useEffect(() => { void load(); }, [load]);

  const hero = <PortalHero kicker="Matchpoolen" title="Hitta träningsmatcher" mark="TZ">
    <p className="pz-lead">Lägg in en hemmatid eller sök en bortamatch, och se vilka lag i närheten som söker motstånd. Ser du en klubb utan verifiering? Då har TeamZone inte granskat den.</p>
  </PortalHero>;

  if (!ready) return <>{hero}<div className="cs-wrap pz-status"><p>Laddar…</p></div></>;
  if (!enabled || accountError) return <>{hero}<section className="cs-section"><div className="cs-wrap"><div className="cs-empty">{accountError || "Kontotjänsten är inte tillgänglig just nu."}</div></div></section></>;
  if (!session) return <>{hero}<section className="cs-section"><div className="cs-wrap mp-gate">
    <h2>Logga in som ledare</h2>
    <p>Matchpoolen är till för ledare i TeamZone. Logga in med samma konto som i appen.</p>
    <Link className="cs-button" href="/?returnTo=/matchpool">Logga in</Link>
  </div></section></>;
  if (notLeader) return <>{hero}<section className="cs-section"><div className="cs-wrap mp-gate">
    <h2>Bara för ledare</h2>
    <p>Matchpoolen är till för den som får hantera kalendern i ett lag i TeamZone. Är du ledare men ser det här? Be klubbens administratör ge dig behörighet i appen.</p>
    <a className="cs-button" href="https://app.teamzoneapp.se">Öppna appen</a>
  </div></section></>;
  if (!page) return <>{hero}<div className="cs-wrap pz-status">{error ? <p role="alert">{error} <button className="cs-button small" onClick={() => void load()}>Försök igen</button></p> : <p>Hämtar matchpoolen…</p>}</div></>;

  const originTeam = page.teams.find(team => team.team_id === origin) ?? null;
  const shown = filterListings(page.listings, filters);
  const mineUnread = page.mine.reduce((sum, listing) => sum + (listing.interests ?? []).filter(i => i.unread).length, 0);
  const sentUnread = page.sent.filter(i => i.unread).length;

  return <>
    {hero}
    <section className="cs-section alt mp-page">
      <div className="cs-wrap">
        <div className="mp-toolbar">
          <label className="field">Vårt lag
            <select value={origin} onChange={e => { setOrigin(e.target.value); setEditingBase(false); }}>
              {page.teams.map(team => <option key={team.team_id} value={team.team_id}>{team.team_name} · {team.club_name}</option>)}
            </select>
          </label>
          <div className="mp-base">
            <span className="mp-label">Utgångsort</span>
            {originTeam?.base && !editingBase
              ? <p><strong>{originTeam.base.place_label}</strong> <button className="pz-link" onClick={() => setEditingBase(true)}>Ändra</button></p>
              : <PlaceSearch client={client} accessToken={session.access_token} onPick={async place => {
                  if (!client || !originTeam) return;
                  const { error: saveError } = await client.schema("api").rpc("save_match_pool_base", { target_team_id: originTeam.team_id, place_label: place.place_label, latitude: place.latitude, longitude: place.longitude });
                  if (saveError) { setError(poolError(saveError)); return; }
                  setEditingBase(false); void load();
                }} hint={originTeam?.base ? undefined : "Välj var laget utgår ifrån, så visas avståndet till varje annons."} />}
          </div>
          <label className="field">Avstånd
            <select value={maxKm} onChange={e => setMaxKm(Number(e.target.value))} disabled={!originTeam?.base}>
              {distances.map(km => <option key={km} value={km}>Inom {km} km</option>)}
            </select>
          </label>
          <button className="cs-button" onClick={() => setCreating(true)}>Lägg in annons</button>
        </div>
        {error && <p role="alert" className="pz-error">{error}</p>}

        <div className="mp-tabs" role="tablist" aria-label="Matchpoolen">
          <button role="tab" aria-selected={tab === "find"} onClick={() => setTab("find")}>Hitta match <span>{page.listings.length}</span></button>
          <button role="tab" aria-selected={tab === "mine"} onClick={() => setTab("mine")}>Våra annonser <span>{page.mine.length}</span>{mineUnread > 0 && <em aria-label={`${mineUnread} olästa`}>{mineUnread}</em>}</button>
          <button role="tab" aria-selected={tab === "sent"} onClick={() => setTab("sent")}>Våra intressen <span>{page.sent.length}</span>{sentUnread > 0 && <em aria-label={`${sentUnread} olästa`}>{sentUnread}</em>}</button>
        </div>

        {tab === "find" && <>
          <div className="mp-filters">
            <select aria-label="Typ av annons" value={filters.kind} onChange={e => setFilters({ ...filters, kind: e.target.value as Filters["kind"] })}>
              <option value="all">Alla annonser</option><option value="home_slot">Har hemmatid</option><option value="away_wanted">Söker bortamatch</option>
            </select>
            <select aria-label="Spelform" value={filters.format} onChange={e => setFilters({ ...filters, format: e.target.value })}>
              <option value="">Alla spelformer</option>{formats.map(f => <option key={f} value={f}>{formatLabel(f)}</option>)}
            </select>
            <select aria-label="Kön" value={filters.gender} onChange={e => setFilters({ ...filters, gender: e.target.value })}>
              <option value="">Alla</option>{Object.entries(genderLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </select>
            <input aria-label="Sök åldersklass, lag eller ort" placeholder="Sök t.ex. P12 eller Botkyrka" value={filters.text} onChange={e => setFilters({ ...filters, text: e.target.value })} />
            <label className="pz-check"><input type="checkbox" checked={filters.verifiedOnly} onChange={e => setFilters({ ...filters, verifiedOnly: e.target.checked })} /><span>Bara verifierade klubbar</span></label>
          </div>
          {!originTeam?.base && <p className="mp-hint">Välj en utgångsort ovan för att se avstånd och bara annonser i närheten.</p>}
          {shown.length === 0
            ? <div className="cs-empty">{page.listings.length === 0 ? "Inga annonser i närheten just nu. Lägg in en egen, så hittar andra lag er." : "Inga annonser matchar filtret."}</div>
            : <div className="mp-list">{shown.map(listing => <ListingCard key={listing.id} listing={listing}
                action={listing.my_interest
                  ? <button className="cs-button small ghost dark" onClick={() => setConversation(listing.my_interest!.id)}>{interestStateLabels[listing.my_interest.state]} · öppna</button>
                  : <button className="cs-button small" onClick={() => setInterestFor(listing)}>Visa intresse</button>}
                onReport={async reason => {
                  if (!client) return;
                  const { error: reportError } = await client.schema("api").rpc("report_match_pool_listing", { target_listing_id: listing.id, reason });
                  if (reportError) setError(poolError(reportError));
                }} />)}</div>}
        </>}

        {tab === "mine" && (page.mine.length === 0
          ? <div className="cs-empty">Ni har inga annonser. <button className="pz-link" onClick={() => setCreating(true)}>Lägg in en</button>.</div>
          : <div className="mp-list">{page.mine.map(listing => <ListingCard key={listing.id} listing={listing} own
              action={listing.state === "open" && listing.current
                ? <button className="cs-button small ghost dark" onClick={async () => {
                    if (!client || !window.confirm("Ta bort annonsen? Lag som visat intresse får besked.")) return;
                    const { error: withdrawError } = await client.schema("api").rpc("withdraw_match_pool_listing", { target_listing_id: listing.id });
                    if (withdrawError) setError(poolError(withdrawError)); else void load();
                  }}>Ta bort annonsen</button>
                : <span className="mp-state">{listing.state === "matched" ? "Matchad" : listing.state === "hidden" ? "Dold efter rapporter" : "Avslutad"}</span>}>
              <div className="mp-interests">
                <h4>Intresserade lag ({listing.interests?.length ?? 0})</h4>
                {(listing.interests ?? []).length === 0 && <p className="mp-hint">Inga än. Lag som visar intresse syns här, och du får en notis i appen.</p>}
                {(listing.interests ?? []).map(interest => <InterestRow key={interest.id} interest={interest} onOpen={() => setConversation(interest.id)} />)}
              </div>
            </ListingCard>)}</div>)}

        {tab === "sent" && (page.sent.length === 0
          ? <div className="cs-empty">Ni har inte visat intresse för någon annons än.</div>
          : <div className="mp-list">{page.sent.map(interest => interest.listing && <ListingCard key={interest.id} listing={interest.listing}
              action={<button className="cs-button small ghost dark" onClick={() => setConversation(interest.id)}>Öppna konversationen</button>}>
              <div className="mp-interests"><InterestRow interest={interest} self onOpen={() => setConversation(interest.id)} /></div>
            </ListingCard>)}</div>)}

        <p className="mp-hint mp-attribution">Platssökning med data från <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">© OpenStreetMap-bidragsgivare</a>. Avstånd räknas fågelvägen mellan orterna.</p>
      </div>
    </section>

    {creating && client && <ListingForm client={client} accessToken={session.access_token} teams={page.teams} initialTeam={origin}
      onClose={() => setCreating(false)} onSaved={() => { setCreating(false); setTab("mine"); void load(); }} />}
    {interestFor && client && <InterestForm client={client} listing={interestFor} teams={page.teams} initialTeam={origin}
      onClose={() => setInterestFor(null)} onSaved={interestId => { setInterestFor(null); void load(); setConversation(interestId); }} />}
    {conversation && client && <ConversationView client={client} interestId={conversation}
      onClose={() => { setConversation(null); void load(); }} />}
  </>;
}

function VerifiedBadge({ verified }: { verified: boolean }) {
  return verified
    ? <span className="mp-badge verified" title="TeamZones support har granskat och godkänt klubben.">✓ Officiellt verifierad klubb</span>
    : <span className="mp-badge unverified" title="Klubben finns i TeamZone men är inte granskad. Kontrollera gärna klubben innan ni bokar.">! Ej verifierad klubb</span>;
}

function ListingCard({ listing, action, own, onReport, children }: { listing: Listing; action?: React.ReactNode; own?: boolean;
  onReport?: (reason: string) => Promise<void>; children?: React.ReactNode }) {
  const [reported, setReported] = useState(false);
  return <article className={`mp-card ${listing.verified ? "is-verified" : "is-unverified"}`}>
    <header>
      <VerifiedBadge verified={listing.verified} />
      <span className={`mp-kind ${listing.kind}`}>{listing.kind === "home_slot" ? "Har hemmatid" : "Söker bortamatch"}</span>
    </header>
    <h3>{listing.team_name} <span>· {listing.club_name}</span></h3>
    {!listing.verified && !own && <p className="mp-warning">Klubben är inte verifierad av TeamZone. Stäm gärna av med klubben innan ni bokar.</p>}
    <dl className="mp-facts">
      <div><dt>När</dt><dd>{whenLabel(listing)}</dd></div>
      <div><dt>Var</dt><dd>{listing.venue_name ? `${listing.venue_name}, ` : ""}{listing.place_label}{listing.distance_km !== null ? ` · ${listing.distance_km} km bort` : ""}</dd></div>
      {listing.kind === "away_wanted" && listing.max_distance_km && <div><dt>Reser</dt><dd>Upp till {listing.max_distance_km} km</dd></div>}
      <div><dt>Lag</dt><dd>{listing.age_class} · {genderLabels[listing.gender]} · {formatLabel(listing.match_format)}{listing.level ? ` · ${levelLabels[listing.level]}` : ""}</dd></div>
      {listing.venue_surface && <div><dt>Underlag</dt><dd>{surfaceLabels[listing.venue_surface]}</dd></div>}
    </dl>
    {listing.note && <p className="mp-note">{listing.note}</p>}
    <footer>
      {action}
      {onReport && !reported && <button className="pz-link mp-report" onClick={async () => {
        const reason = window.prompt("Vad är fel med annonsen? Rapporten går till TeamZone.");
        if (reason && reason.trim()) { await onReport(reason.trim().slice(0, 500)); setReported(true); }
      }}>Rapportera</button>}
      {reported && <span className="mp-hint">Tack, annonsen är rapporterad.</span>}
    </footer>
    {children}
  </article>;
}

function InterestRow({ interest, onOpen, self }: { interest: Interest; onOpen: () => void; self?: boolean }) {
  return <button className={`mp-interest${interest.unread ? " unread" : ""}`} onClick={onOpen}>
    <span className="mp-interest-head">
      {!self && <><strong>{interest.team_name} · {interest.club_name}</strong><VerifiedBadge verified={interest.verified} /></>}
      <span className={`mp-chip ${interest.state}`}>{interestStateLabels[interest.state]}</span>
      {interest.unread && <span className="mp-dot" aria-label="Nytt meddelande" />}
    </span>
    {interest.starts_at && <span className="mp-hint">Förslag: {slotLabel(interest.starts_at, interest.ends_at)}{interest.venue_name ? `, ${interest.venue_name}` : ""}</span>}
    {interest.last_message && <span className="mp-preview">{interest.last_message}</span>}
  </button>;
}

function PlaceSearch({ accessToken, onPick, hint }: { client: SupabaseClient | null; accessToken: string; onPick: (place: Place) => void | Promise<void>; hint?: string }) {
  const [query, setQuery] = useState("");
  const [places, setPlaces] = useState<Place[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState("");
  async function search(event?: React.FormEvent | React.MouseEvent) {
    event?.preventDefault();
    if (query.trim().length < 2 || busy) return;
    setBusy(true); setProblem("");
    try {
      const response = await fetch(`/api/public/v1/places?q=${encodeURIComponent(query.trim())}`, { headers: { authorization: `Bearer ${accessToken}` }, cache: "no-store" });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) { setProblem(body.error ?? "Platssökningen fungerar inte just nu."); setPlaces(null); return; }
      setPlaces(body.places ?? []);
    } catch { setProblem("Platssökningen fungerar inte just nu."); }
    finally { setBusy(false); }
  }
  return <div className="mp-place">
    {hint && <p className="mp-hint">{hint}</p>}
    <div className="mp-place-row">
      <input aria-label="Sök ort eller adress" placeholder="Ort, adress eller idrottsplats" value={query} maxLength={100}
        onChange={e => setQuery(e.target.value)} onKeyDown={e => { if (e.key === "Enter") void search(e as unknown as React.FormEvent); }} />
      <button type="button" className="cs-button small" disabled={busy || query.trim().length < 2} onClick={search}>{busy ? "Söker…" : "Sök"}</button>
    </div>
    {problem && <p role="alert" className="pz-error">{problem}</p>}
    {places && places.length === 0 && <p className="mp-hint">Ingen träff. Prova bara ortens namn.</p>}
    {places && places.length > 0 && <ul className="mp-place-list">{places.map(place => <li key={`${place.place_label}${place.latitude}`}>
      <button type="button" onClick={() => { void onPick(place); setPlaces(null); setQuery(""); }}>{place.place_label}</button>
    </li>)}</ul>}
  </div>;
}

function Dialog({ title, onClose, children }: { title: string; onClose: () => void; children: React.ReactNode }) {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => { window.removeEventListener("keydown", onKey); document.body.style.overflow = ""; };
  }, [onClose]);
  return <div className="mp-overlay" onMouseDown={event => { if (event.target === event.currentTarget) onClose(); }}>
    <div className="mp-dialog" role="dialog" aria-modal="true" aria-label={title}>
      <div className="mp-dialog-head"><h2>{title}</h2><button className="mp-close" aria-label="Stäng" onClick={onClose}>×</button></div>
      {children}
    </div>
  </div>;
}

function TeamSelect({ teams, value, onChange }: { teams: PoolTeam[]; value: string; onChange: (value: string) => void }) {
  return <label className="field">Lag
    <select value={value} onChange={e => onChange(e.target.value)}>
      {teams.map(team => <option key={team.team_id} value={team.team_id}>{team.team_name} · {team.club_name}</option>)}
    </select>
  </label>;
}

function ListingForm({ client, accessToken, teams, initialTeam, onClose, onSaved }: { client: SupabaseClient; accessToken: string; teams: PoolTeam[];
  initialTeam: string; onClose: () => void; onSaved: () => void }) {
  const [teamId, setTeamId] = useState(initialTeam || teams[0]?.team_id || "");
  const team = teams.find(t => t.team_id === teamId);
  const [draft, setDraft] = useState<ListingDraft>(() => ({
    kind: "home_slot", date: "", startTime: "10:00", endTime: "11:30", dateFrom: todayInStockholm(), dateTo: "", maxDistance: "50",
    place: team?.base ?? null, venueName: "", surface: "", format: "", ageClass: team?.age_class ?? "", gender: "", level: "", note: "",
  }));
  const [problem, setProblem] = useState("");
  const [busy, setBusy] = useState(false);
  const [key] = useState(newKey);
  const set = (patch: Partial<ListingDraft>) => setDraft(previous => ({ ...previous, ...patch }));
  async function save(event: React.FormEvent) {
    event.preventDefault();
    const { payload, problem: invalid } = listingPayload(draft);
    if (!payload) { setProblem(invalid ?? ""); return; }
    setBusy(true); setProblem("");
    const { error } = await client.schema("api").rpc("create_match_pool_listing", { target_team_id: teamId, listing: payload, idempotency_key: key });
    setBusy(false);
    if (error) setProblem(poolError(error)); else onSaved();
  }
  return <Dialog title="Lägg in annons" onClose={onClose}>
    <form className="mp-form" onSubmit={save}>
      <TeamSelect teams={teams} value={teamId} onChange={value => {
        setTeamId(value);
        const next = teams.find(t => t.team_id === value);
        set({ place: next?.base ?? draft.place, ageClass: next?.age_class ?? draft.ageClass });
      }} />
      <div className="mp-segment" role="radiogroup" aria-label="Typ av annons">
        <button type="button" role="radio" aria-checked={draft.kind === "home_slot"} onClick={() => set({ kind: "home_slot" })}><strong>Vi har en hemmatid</strong><span>Ni har bokat plan och söker motstånd</span></button>
        <button type="button" role="radio" aria-checked={draft.kind === "away_wanted"} onClick={() => set({ kind: "away_wanted" })}><strong>Vi söker bortamatch</strong><span>Ni reser till ett lag som har en plan</span></button>
      </div>
      {draft.kind === "home_slot" ? <>
        <div className="pz-form-row">
          <label className="field">Datum<input type="date" min={todayInStockholm()} value={draft.date} onChange={e => set({ date: e.target.value })} required /></label>
          <div className="pz-form-row">
            <label className="field">Från<input type="time" value={draft.startTime} onChange={e => set({ startTime: e.target.value })} required /></label>
            <label className="field">Till<input type="time" value={draft.endTime} onChange={e => set({ endTime: e.target.value })} required /></label>
          </div>
        </div>
        <div className="pz-form-row">
          <label className="field">Plan eller anläggning<input maxLength={160} value={draft.venueName} onChange={e => set({ venueName: e.target.value })} placeholder="t.ex. Alby IP, plan 2" required /></label>
          <label className="field">Underlag<select value={draft.surface} onChange={e => set({ surface: e.target.value as Surface | "" })}>
            <option value="">Välj</option>{Object.entries(surfaceLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select></label>
        </div>
        <p className="mp-hint">Planens namn visas bara för laget ni bokar med. I listan syns orten.</p>
      </> : <>
        <div className="pz-form-row">
          <label className="field">Från datum<input type="date" min={todayInStockholm()} value={draft.dateFrom} onChange={e => set({ dateFrom: e.target.value })} required /></label>
          <label className="field">Till datum<input type="date" min={draft.dateFrom || todayInStockholm()} value={draft.dateTo} onChange={e => set({ dateTo: e.target.value })} required /></label>
        </div>
        <label className="field">Hur långt kan ni resa?<select value={draft.maxDistance} onChange={e => set({ maxDistance: e.target.value })}>
          {[10, 20, 30, 50, 75, 100, 150, 200, 300].map(km => <option key={km} value={km}>Upp till {km} km</option>)}
        </select></label>
      </>}
      <div className="field">Ort
        {draft.place
          ? <p className="mp-picked"><strong>{draft.place.place_label}</strong> <button type="button" className="pz-link" onClick={() => set({ place: null })}>Ändra</button></p>
          : <PlaceSearch client={client} accessToken={accessToken} onPick={place => set({ place })} />}
      </div>
      <div className="pz-form-row">
        <label className="field">Spelform<select value={draft.format} onChange={e => set({ format: e.target.value })} required>
          <option value="">Välj</option>{formats.map(f => <option key={f} value={f}>{formatLabel(f)}</option>)}
        </select></label>
        <label className="field">Åldersklass<input maxLength={40} value={draft.ageClass} onChange={e => set({ ageClass: e.target.value })} placeholder="t.ex. P12 eller F2013" required /></label>
      </div>
      <div className="pz-form-row">
        <label className="field">Pojkar eller flickor<select value={draft.gender} onChange={e => set({ gender: e.target.value as Gender | "" })} required>
          <option value="">Välj</option>{Object.entries(genderLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        </select></label>
        <label className="field">Ungefärlig nivå<select value={draft.level} onChange={e => set({ level: e.target.value as Level | "" })}>
          <option value="">Vill inte ange</option>{Object.entries(levelLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        </select></label>
      </div>
      <label className="field">Kommentar (valfri)<textarea maxLength={500} value={draft.note} onChange={e => set({ note: e.target.value })} placeholder="t.ex. vi spelar gärna två halvlekar à 30 min" /></label>
      <p className="mp-hint">Skriv inga namn på spelare eller kontaktuppgifter. Lag som är intresserade kontaktar er här, och ni får en notis i appen.</p>
      {problem && <p role="alert" className="pz-error">{problem}</p>}
      <div className="mp-form-actions">
        <button type="button" className="cs-button ghost dark" onClick={onClose}>Avbryt</button>
        <button className="cs-button" disabled={busy}>{busy ? "Sparar…" : "Lägg in annonsen"}</button>
      </div>
    </form>
  </Dialog>;
}

function InterestForm({ client, listing, teams, initialTeam, onClose, onSaved }: { client: SupabaseClient; listing: Listing; teams: PoolTeam[];
  initialTeam: string; onClose: () => void; onSaved: (interestId: string) => void }) {
  const [teamId, setTeamId] = useState(initialTeam || teams[0]?.team_id || "");
  const [message, setMessage] = useState("");
  const [date, setDate] = useState(listing.date_from && listing.date_from >= todayInStockholm() ? listing.date_from : todayInStockholm());
  const [startTime, setStartTime] = useState("10:00");
  const [endTime, setEndTime] = useState("11:30");
  const [venue, setVenue] = useState("");
  const [surface, setSurface] = useState<Surface | "">("");
  const [calendar, setCalendar] = useState(true);
  const [problem, setProblem] = useState("");
  const [busy, setBusy] = useState(false);
  const [key] = useState(newKey);
  const hosting = listing.kind === "away_wanted";
  async function send(event: React.FormEvent) {
    event.preventDefault();
    if (!message.trim()) { setProblem("Skriv några rader till laget."); return; }
    const interest: Record<string, unknown> = { message: message.trim(), add_to_calendar: calendar };
    if (hosting) {
      const starts = stockholmInstant(date, startTime), ends = stockholmInstant(date, endTime);
      if (!starts || !ends || ends <= starts) { setProblem("Ange datum och tid för matchen."); return; }
      if (!venue.trim()) { setProblem("Ange er plan eller anläggning."); return; }
      Object.assign(interest, { starts_at: starts.toISOString(), ends_at: ends.toISOString(), venue_name: venue.trim(), venue_surface: surface || null });
    }
    setBusy(true); setProblem("");
    const { data, error } = await client.schema("api").rpc("express_match_pool_interest", { target_listing_id: listing.id, target_team_id: teamId, interest, idempotency_key: key });
    setBusy(false);
    if (error) setProblem(poolError(error)); else onSaved(String(data));
  }
  return <Dialog title={`Intresse: ${listing.team_name} · ${listing.club_name}`} onClose={onClose}>
    <form className="mp-form" onSubmit={send}>
      <p className="mp-summary"><VerifiedBadge verified={listing.verified} /> {whenLabel(listing)} · {listing.place_label} · {listing.age_class} · {formatLabel(listing.match_format)}</p>
      <TeamSelect teams={teams} value={teamId} onChange={setTeamId} />
      {hosting && <>
        <p className="mp-hint">Laget söker bortamatch, så ni är hemmalag. Föreslå en tid mellan {whenLabel(listing)}.</p>
        <div className="pz-form-row">
          <label className="field">Datum<input type="date" min={listing.date_from ?? undefined} max={listing.date_to ?? undefined} value={date} onChange={e => setDate(e.target.value)} required /></label>
          <div className="pz-form-row">
            <label className="field">Från<input type="time" value={startTime} onChange={e => setStartTime(e.target.value)} required /></label>
            <label className="field">Till<input type="time" value={endTime} onChange={e => setEndTime(e.target.value)} required /></label>
          </div>
        </div>
        <div className="pz-form-row">
          <label className="field">Er plan eller anläggning<input maxLength={160} value={venue} onChange={e => setVenue(e.target.value)} required /></label>
          <label className="field">Underlag<select value={surface} onChange={e => setSurface(e.target.value as Surface | "")}>
            <option value="">Välj</option>{Object.entries(surfaceLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select></label>
        </div>
      </>}
      <label className="field">Meddelande<textarea maxLength={1000} value={message} onChange={e => setMessage(e.target.value)} required placeholder="Hej! Vi är intresserade av en träningsmatch…" /></label>
      <label className="pz-check"><input type="checkbox" checked={calendar} onChange={e => setCalendar(e.target.checked)} /><span>Lägg in matchen i vår kalender om den blir av (som utkast)</span></label>
      {problem && <p role="alert" className="pz-error">{problem}</p>}
      <div className="mp-form-actions">
        <button type="button" className="cs-button ghost dark" onClick={onClose}>Avbryt</button>
        <button className="cs-button" disabled={busy}>{busy ? "Skickar…" : "Skicka intresse"}</button>
      </div>
    </form>
  </Dialog>;
}

function ConversationView({ client, interestId, onClose }: { client: SupabaseClient; interestId: string; onClose: () => void }) {
  const [data, setData] = useState<Conversation | null>(null);
  const [problem, setProblem] = useState("");
  const [reply, setReply] = useState("");
  const [busy, setBusy] = useState(false);
  const [calendar, setCalendar] = useState(true);
  const [key, setKey] = useState(newKey);
  const end = useRef<HTMLDivElement>(null);
  const load = useCallback(async () => {
    const { data: next, error } = await client.schema("api").rpc("get_match_pool_conversation", { target_interest_id: interestId });
    if (error) setProblem(poolError(error)); else setData(next as Conversation);
  }, [client, interestId]);
  useEffect(() => { void load(); }, [load]);
  useEffect(() => { end.current?.scrollIntoView({ block: "end" }); }, [data?.messages.length]);
  async function act(name: string, params: Record<string, unknown>, after?: (result: unknown) => void) {
    setBusy(true); setProblem("");
    const { data: result, error } = await client.schema("api").rpc(name, params);
    setBusy(false);
    if (error) { setProblem(poolError(error)); return; }
    after?.(result);
    void load();
  }
  if (!data) return <Dialog title="Konversation" onClose={onClose}>{problem ? <p role="alert" className="pz-error">{problem}</p> : <p>Hämtar…</p>}</Dialog>;
  const { listing, interest, my_side: side } = data;
  const other = side === "listing" ? `${interest.team_name} · ${interest.club_name}` : `${listing.team_name} · ${listing.club_name}`;
  const otherVerified = side === "listing" ? interest.verified : listing.verified;
  const open = interest.state === "pending" || interest.state === "accepted";
  const when = listing.kind === "home_slot" ? whenLabel(listing) : slotLabel(interest.starts_at, interest.ends_at) || whenLabel(listing);
  const venue = listing.kind === "home_slot" ? listing.venue_name : interest.venue_name;
  return <Dialog title={other} onClose={onClose}>
    <div className="mp-convo">
      <div className="mp-convo-summary">
        <VerifiedBadge verified={otherVerified} />
        <span className={`mp-chip ${interest.state}`}>{interestStateLabels[interest.state]}</span>
        <p><strong>{listing.kind === "home_slot" ? `${listing.team_name} har hemmatid` : `${listing.team_name} söker bortamatch`}</strong> · {listing.age_class} · {formatLabel(listing.match_format)}</p>
        <p>{when}{venue ? ` · ${venue}` : ""} · {listing.place_label}</p>
        {interest.state === "accepted" && <p className="mp-success">Matchen är bokad. {data.my_event_id ? "Den ligger som utkast i er kalender i appen – publicera den när ni är redo." : "Den är inte inlagd i er kalender, lägg in den i appen om ni vill."}</p>}
      </div>
      <div className="mp-messages" aria-live="polite">
        {data.messages.map(message => message.side === "system"
          ? <p key={message.id} className="mp-system">{message.body}</p>
          : <div key={message.id} className={`mp-message ${message.side === side ? "mine" : "theirs"}`}>
              <span className="mp-meta">{message.side === side ? "Ni" : (message.side === "listing" ? listing.team_name : interest.team_name)}{message.author_name ? ` · ${message.author_name}` : ""} · {new Date(message.created_at).toLocaleString("sv-SE", { timeZone: "Europe/Stockholm", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })}</span>
              <p>{message.body}</p>
            </div>)}
        <div ref={end} />
      </div>
      {problem && <p role="alert" className="pz-error">{problem}</p>}
      {side === "listing" && interest.state === "pending" && listing.current !== false && <div className="mp-decide">
        <label className="pz-check"><input type="checkbox" checked={calendar} onChange={e => setCalendar(e.target.checked)} /><span>Lägg in matchen i vår kalender (som utkast)</span></label>
        <div className="mp-form-actions">
          <button className="cs-button ghost dark" disabled={busy} onClick={() => { if (window.confirm("Tacka nej till laget?")) void act("decline_match_pool_interest", { target_interest_id: interest.id }); }}>Tacka nej</button>
          <button className="cs-button" disabled={busy} onClick={() => { if (window.confirm(`Boka matchen med ${interest.team_name}? Övriga intresserade får besked.`)) void act("accept_match_pool_interest", { target_interest_id: interest.id, add_to_calendar: calendar }); }}>Acceptera och boka</button>
        </div>
      </div>}
      {side === "interest" && interest.state === "pending" && <div className="mp-form-actions start">
        <button className="pz-link" disabled={busy} onClick={() => { if (window.confirm("Återkalla ert intresse?")) void act("withdraw_match_pool_interest", { target_interest_id: interest.id }); }}>Återkalla intresset</button>
      </div>}
      {open && <form className="mp-reply" onSubmit={event => { event.preventDefault(); if (!reply.trim()) return;
        void act("send_match_pool_message", { target_interest_id: interest.id, message_body: reply.trim(), idempotency_key: key }, () => { setReply(""); setKey(newKey()); }); }}>
        <textarea aria-label="Skriv ett meddelande" maxLength={2000} value={reply} onChange={e => setReply(e.target.value)} placeholder={`Skriv till ${side === "listing" ? interest.team_name : listing.team_name}…`} />
        <button className="cs-button small" disabled={busy || !reply.trim()}>Skicka</button>
      </form>}
    </div>
  </Dialog>;
}
