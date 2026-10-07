"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { loadAdminScope, type AdminRpc, type AdminScope, type SelfService } from "../../lib/admin";
import { usePersonalAccount } from "../personal-account";
import { AdminBrand } from "./admin-brand";
import { AdminNews } from "./admin-news";
import { AdminPages } from "./admin-pages";
import { AdminPartners } from "./admin-partners";
import { AdminTeams } from "./admin-teams";
import type { AdminEnv } from "./admin-ui";

type Tab = "nyheter" | "sidan" | "matcher" | "utseende" | "partners";
const tabLabels: Record<Tab, string> = { nyheter: "Nyheter", sidan: "Sidan", matcher: "Matcher och träningar", utseende: "Utseende", partners: "Partners" };

export function tabsFor(scope: AdminScope): Tab[] {
  return [
    ...(scope.canPublishNews ? ["nyheter" as const] : []),
    "sidan" as const,
    ...(scope.teams.length ? ["matcher" as const] : []),
    ...(scope.canManageBrand ? ["utseende" as const] : []),
    ...(scope.canManageClub ? ["partners" as const] : []),
  ];
}

export function AdminApp({ clubSlug, clubName }: { clubSlug: string; clubName: string }) {
  const { client, session, ready, enabled } = usePersonalAccount();
  const [scope, setScope] = useState<AdminScope | null>(null);
  const [selfService, setSelfService] = useState<SelfService | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "denied" | "error">("loading");
  const [tab, setTab] = useState<Tab | null>(null);
  const rpc = useMemo<AdminRpc | null>(() => client ? (name, params) => client.schema("api").rpc(name, params) : null, [client]);

  const load = useCallback(async () => {
    if (!rpc) return;
    try {
      const result = await loadAdminScope(rpc, clubSlug);
      if (!result.scope || !result.selfService) { setState("denied"); return; }
      setScope(result.scope);
      setSelfService(result.selfService);
      setState("ready");
    } catch { setState("error"); }
  }, [rpc, clubSlug]);

  useEffect(() => { if (session && rpc) void load(); }, [session, rpc, load]);

  useEffect(() => {
    if (!scope) return;
    const available = tabsFor(scope);
    const fromHash = window.location.hash.slice(1) as Tab;
    setTab(current => current && available.includes(current) ? current : available.includes(fromHash) ? fromHash : available[0]);
  }, [scope]);

  const signInHref = `/?returnTo=${encodeURIComponent(`/${clubSlug}/admin`)}`;
  if (!ready) return <AdminMessage title="Hämtar…" />;
  if (!enabled) return <AdminMessage title="Inloggningen är inte tillgänglig" text="Kontotjänsten kan inte nås just nu. Försök igen senare." />;
  if (!session) return <AdminMessage title={`Hantera ${clubName}s sida`} text="Logga in med ditt TeamZone-konto för att sköta klubbens och lagens publika sidor.">
    <Link className="ad-button" href={signInHref}>Logga in</Link>
  </AdminMessage>;
  if (state === "loading") return <AdminMessage title="Kontrollerar behörighet…" />;
  if (state === "error") return <AdminMessage title="Något gick fel" text="Behörigheten kunde inte kontrolleras. Försök igen.">
    <button className="ad-button" onClick={() => { setState("loading"); void load(); }}>Försök igen</button>
  </AdminMessage>;
  if (state === "denied" || !scope || !selfService || !client || !rpc) return <AdminMessage title="Du saknar behörighet" text={`Ditt konto kan inte hantera ${clubName}s sida. Be en klubbadministratör om behörighet att publicera.`}>
    <Link className="ad-button ghost" href={`/${clubSlug}`}>Till klubbsidan</Link>
  </AdminMessage>;

  const env: AdminEnv = { rpc, client, scope, selfService, reload: load };
  const tabs = tabsFor(scope);
  const active = tab && tabs.includes(tab) ? tab : tabs[0];
  return <div className="ad-shell">
    <div className="ad-top">
      <div><p className="ad-kicker">Hantera sidan</p><h1>{scope.clubName}</h1></div>
      <Link className="ad-link" href={`/${clubSlug}`}>Visa klubbsidan →</Link>
    </div>
    <nav className="ad-tabs" aria-label="Administrera">
      {tabs.map(item => <button key={item} aria-current={item === active ? "page" : undefined} onClick={() => { setTab(item); history.replaceState(null, "", `#${item}`); }}>{tabLabels[item]}</button>)}
    </nav>
    {active === "nyheter" && <AdminNews env={env} clubSlug={clubSlug} />}
    {active === "sidan" && <AdminPages env={env} />}
    {active === "matcher" && <AdminTeams env={env} />}
    {active === "utseende" && <AdminBrand env={env} />}
    {active === "partners" && <AdminPartners env={env} />}
  </div>;
}

function AdminMessage({ title, text, children }: { title: string; text?: string; children?: React.ReactNode }) {
  return <div className="ad-shell"><section className="ad-panel ad-message"><h1>{title}</h1>{text && <p>{text}</p>}{children && <div className="ad-actions">{children}</div>}</section></div>;
}
