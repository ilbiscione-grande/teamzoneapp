"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { loadAdminScope } from "../../lib/admin";
import { usePersonalAccount } from "../personal-account";

const cacheMinutes = 5;

/**
 * "Hantera sidan" on a public club or team page, shown only to a signed-in
 * account that may administer it. The answer is cached briefly per club and
 * account so ordinary browsing does not repeat the permission lookups.
 */
export function AdminEntry({ clubSlug, section, className = "cs-button ghost" }: { clubSlug: string; section?: string; className?: string }) {
  const { client, session } = usePersonalAccount();
  const [allowed, setAllowed] = useState(false);
  useEffect(() => {
    if (!client || !session) { setAllowed(false); return; }
    const key = `teamzone-admin:${session.user.id}:${clubSlug}`;
    try {
      const cached = JSON.parse(sessionStorage.getItem(key) ?? "null") as { allowed: boolean; at: number } | null;
      if (cached && Date.now() - cached.at < cacheMinutes * 60_000) { setAllowed(cached.allowed); return; }
    } catch { /* storage unavailable: look it up */ }
    let disposed = false;
    loadAdminScope((name, params) => client.schema("api").rpc(name, params), clubSlug)
      .then(result => {
        const next = result.scope !== null;
        try { sessionStorage.setItem(key, JSON.stringify({ allowed: next, at: Date.now() })); } catch { /* ignore */ }
        if (!disposed) setAllowed(next);
      })
      .catch(() => { if (!disposed) setAllowed(false); });
    return () => { disposed = true; };
  }, [client, session, clubSlug]);
  if (!allowed) return null;
  return <Link className={`${className} ad-entry`} href={`/${clubSlug}/admin${section ? `#${section}` : ""}`}>Hantera sidan</Link>;
}
