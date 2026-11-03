"use client";

// Support's side of the library's reports (plan item 16): whether the
// account is support, the reported items (open ones, or all), an item whole,
// and the decision: hide it, or keep it shown.
import { useCallback, useEffect, useState } from "react";
import { reviewErrorText, type ReportedItem, type ReportedItemWhole } from "../../../lib/tactics/reports.ts";
import { useAccount } from "../../account";

/** null while asking, then whether the signed-in account is support. */
export function useSupportAdmin() {
  const { client, session } = useAccount();
  const [admin, setAdmin] = useState<boolean | null>(null);
  useEffect(() => {
    if (!client || !session) { setAdmin(false); return; }
    void client.schema("api").rpc("is_support_admin").then(({ data, error }) => setAdmin(!error && data === true));
  }, [client, session]);
  return admin;
}

export function useReportReview() {
  const { client } = useAccount();
  const [items, setItems] = useState<ReportedItem[] | null>(null);
  const [error, setError] = useState("");

  const refresh = useCallback(async (onlyOpen: boolean) => {
    if (!client) return;
    const { data, error: listError } = await client.schema("api").rpc("list_tactics_shared_reports", { only_open: onlyOpen });
    if (listError) { setError(reviewErrorText(listError.message)); setItems([]); return; }
    setError("");
    setItems(data as ReportedItem[]);
  }, [client]);

  /** The item with its boards, or null when it could not be fetched. */
  const whole = async (id: string): Promise<ReportedItemWhole | null> => {
    if (!client) return null;
    const { data, error: loadError } = await client.schema("api").rpc("get_tactics_shared_report_item", { target_shared_id: id });
    if (loadError) { setError(reviewErrorText(loadError.message)); return null; }
    return data as ReportedItemWhole;
  };

  /** Hides the item (hide) or shows it again; the open reports are resolved. True when done. */
  const decide = async (id: string, hide: boolean, note: string) => {
    if (!client) return false;
    const { error: decideError } = await client.schema("api").rpc("decide_tactics_shared_reports", {
      target_shared_id: id, hide, note: note.trim(),
    });
    if (decideError) { setError(reviewErrorText(decideError.message)); return false; }
    setError("");
    return true;
  };

  return { items, error, refresh, whole, decide };
}
