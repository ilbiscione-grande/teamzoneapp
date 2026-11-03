"use client";

// /tacticsboard: the product page for the signed-out, the app for the
// signed-in. The product page itself is server-rendered and passed in.
import { useAccount } from "../account";

export function TacticsboardEntry({ product, children }: { product: React.ReactNode; children: React.ReactNode }) {
  const { ready, available, session } = useAccount();
  if (!ready) return <div className="wt-wrap wt-section"><p className="wt-status">Laddar…</p></div>;
  return <>{available && !session ? product : children}</>;
}
