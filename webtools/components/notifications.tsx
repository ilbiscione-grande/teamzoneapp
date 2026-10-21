"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { bookingSpan } from "../lib/booking";
import { useAccount } from "./account";
import { RequireAccount } from "./shell";

type Notification = {
  id: string;
  kind: "requested" | "approved" | "declined" | "cancelled";
  created_at: string;
  read: boolean;
  organization_id: string;
  organization_name: string;
  resource_name: string;
  title: string | null;
  starts_at: string;
  ends_at: string;
  booked_by_name: string | null;
};

type Inbox = { unread: number; items: Notification[] };

const headlines: Record<Notification["kind"], string> = {
  requested: "Bokning att godkänna",
  approved: "Din bokning är godkänd",
  declined: "Din bokning nekades",
  cancelled: "Din bokning är avbokad",
};

function useInbox(poll: boolean) {
  const { client, session, accepted } = useAccount();
  const [inbox, setInbox] = useState<Inbox | null>(null);
  const load = useCallback(async () => {
    if (!client || !session || !accepted) return;
    const { data, error } = await client.schema("api").rpc("list_booking_notifications");
    if (!error && data) setInbox(data as Inbox);
  }, [client, session, accepted]);
  useEffect(() => {
    void load();
    if (!poll) return;
    // New requests show without reloading: every minute, and on return.
    const timer = setInterval(() => void load(), 60_000);
    const onFocus = () => void load();
    window.addEventListener("focus", onFocus);
    return () => { clearInterval(timer); window.removeEventListener("focus", onFocus); };
  }, [load, poll]);
  return { inbox, reload: load, client };
}

/** The header's bell with the unread count. */
export function NotificationBell() {
  const { session, accepted } = useAccount();
  const path = usePathname();
  const { inbox, reload } = useInbox(true);
  // Reading the list clears the count; refresh when leaving it.
  useEffect(() => { void reload(); }, [path, reload]);
  if (!session || !accepted) return null;
  const unread = inbox?.unread ?? 0;
  return (
    <Link href="/aviseringar" className="wt-bell" aria-current={path === "/aviseringar" ? "page" : undefined}
      aria-label={unread > 0 ? `Aviseringar, ${unread} olästa` : "Aviseringar"}>
      <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path fill="currentColor" d="M12 22a2.5 2.5 0 0 0 2.45-2h-4.9A2.5 2.5 0 0 0 12 22Zm7-6V11a7 7 0 0 0-5.5-6.84V3.5a1.5 1.5 0 0 0-3 0v.66A7 7 0 0 0 5 11v5l-2 2v1h18v-1l-2-2Z" /></svg>
      {unread > 0 && <span className="wt-bell-count">{unread > 99 ? "99+" : unread}</span>}
    </Link>
  );
}

function NotificationList() {
  const { inbox, client } = useInbox(false);
  // Opening the list reads it; the new ones stay marked until next time.
  useEffect(() => {
    if (!client || !inbox || inbox.unread === 0) return;
    void client.schema("api").rpc("mark_booking_notifications_read", {});
  }, [client, inbox]);
  if (!inbox) return <p className="wt-status">Laddar…</p>;
  if (inbox.items.length === 0) return <section className="wt-panel"><p>Inga aviseringar än. Här hamnar förfrågningar att godkänna och besked om dina bokningar.</p></section>;
  return (
    <ul className="wt-notifications">
      {inbox.items.map(item => (
        <li key={item.id} data-unread={!item.read} data-kind={item.kind}>
          <Link href={`/bokningar/${item.organization_id}`}>
            <strong>{headlines[item.kind]}</strong>
            <span>
              {[item.resource_name, item.title, `${new Date(item.starts_at).toLocaleDateString("sv-SE", { weekday: "short", day: "numeric", month: "short" })} ${bookingSpan(item.starts_at, item.ends_at)}`,
                item.kind === "requested" ? item.booked_by_name : null].filter(Boolean).join(" · ")}
            </span>
            <small>{item.organization_name} · {new Date(item.created_at).toLocaleString("sv-SE", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })}</small>
          </Link>
        </li>
      ))}
    </ul>
  );
}

export function NotificationsPage() {
  return <RequireAccount returnTo="/aviseringar"><NotificationList /></RequireAccount>;
}
