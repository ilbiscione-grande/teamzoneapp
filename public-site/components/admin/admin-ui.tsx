"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { useCallback, useState } from "react";
import { adminErrorMessage, type AdminRpc, type AdminScope, type SelfService } from "../../lib/admin";

export type AdminEnv = {
  rpc: AdminRpc;
  client: SupabaseClient;
  scope: AdminScope;
  selfService: SelfService;
  /** Reloads rights and page settings after a change. */
  reload: () => Promise<void>;
};

export type Notice = { kind: "success" | "error"; text: string } | null;

/** Runs one command at a time and reports the outcome in plain Swedish. */
export function useAdminAction() {
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<Notice>(null);
  const run = useCallback(async (command: () => Promise<void>, success: string, failure?: string) => {
    setBusy(true);
    setNotice(null);
    try {
      await command();
      setNotice({ kind: "success", text: success });
      return true;
    } catch (error) {
      setNotice({ kind: "error", text: adminErrorMessage(error, failure) });
      return false;
    } finally {
      setBusy(false);
    }
  }, []);
  return { busy, notice, setNotice, run };
}

/** Throws the RPC error so useAdminAction can report it. */
export async function call(rpc: AdminRpc, name: string, params: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await rpc(name, params);
  if (error) throw error;
  return data;
}

export function NoticeBar({ notice }: { notice: Notice }) {
  if (!notice) return null;
  return <p className={`ad-notice ${notice.kind}`} role={notice.kind === "error" ? "alert" : "status"}>{notice.text}</p>;
}

export function Panel({ title, lead, children, actions }: { title: string; lead?: string; children: React.ReactNode; actions?: React.ReactNode }) {
  return <section className="ad-panel">
    <div className="ad-panel-head"><div><h2>{title}</h2>{lead && <p>{lead}</p>}</div>{actions}</div>
    {children}
  </section>;
}
