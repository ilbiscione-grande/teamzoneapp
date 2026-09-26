"use client";

import Link from "next/link";
import { useState } from "react";
import type { Channel } from "../lib/personal-home";
import { channelHref } from "../lib/personal-home";
import { usePersonalAccount } from "./personal-account";

export function FollowButton({ channel }: { channel: Channel }) {
  const { client, session, ready, enabled, home, refresh } = usePersonalAccount();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  if (!ready || !enabled) return null;
  const label = channel.kind === "team" ? "Följ laget" : "Följ klubben";
  if (!session) return <Link className="follow-button" href={`/?returnTo=${encodeURIComponent(channelHref(channel))}`} title="Logga in för att följa">+ {label}</Link>;
  const following = home?.following.some(item => item.kind === channel.kind && item.id === channel.id) ?? false;
  async function toggle() {
    if (!client || busy || !home) return;
    setBusy(true); setMessage("");
    try {
      const { error } = await client.schema("api").rpc("set_public_channel_follow", { kind: channel.kind, public_id: channel.id, following: !following });
      if (error) throw error;
      refresh();
    } catch (error) { setMessage(String((error as { message?: string }).message).includes("follow_limit") ? "Du kan följa högst 100 lag och klubbar." : "Ändringen kunde inte sparas. Försök igen."); }
    finally { setBusy(false); }
  }
  return <span className="follow-control"><button className="follow-button" type="button" disabled={busy || !home || !home.available} aria-pressed={following} onClick={toggle}>{busy ? "Sparar…" : following ? "✓ Följer · Sluta följa" : `+ ${label}`}</button>{message && <span role="alert">{message}</span>}</span>;
}
