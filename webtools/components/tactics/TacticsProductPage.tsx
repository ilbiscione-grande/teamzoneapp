"use client";

// /appar/tacticsboard: the server-rendered product page, so search engines
// read it. The signed-in have no use for it and go on to the app.
import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { useAccount } from "../account";

export function TacticsProductPage({ children }: { children: React.ReactNode }) {
  const { session } = useAccount();
  const router = useRouter();
  useEffect(() => {
    if (session) router.replace("/tacticsboard");
  }, [session, router]);
  return <>{children}</>;
}
