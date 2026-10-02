"use client";

import Script from "next/script";
import { useCallback, useEffect, useRef, useState } from "react";
import { mountTurnstile, type TurnstileApi } from "../lib/turnstile-widget";

const siteKey = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY?.trim() ?? "";

/** Cloudflare Turnstile for one action; the token is verified on the server. */
export function useTurnstile(action: string) {
  const [token, setToken] = useState("");
  const [scriptReady, setScriptReady] = useState(false);
  const [host, setHost] = useState<HTMLDivElement | null>(null);
  const widget = useRef<ReturnType<typeof mountTurnstile> | null>(null);

  useEffect(() => {
    const api = (window as { turnstile?: TurnstileApi }).turnstile;
    setToken("");
    if (!siteKey || !scriptReady || !api || !host) return;
    const mounted = mountTurnstile(api, host, siteKey, action, setToken);
    widget.current = mounted;
    return () => {
      widget.current = null;
      mounted.dispose();
    };
  }, [scriptReady, action, host]);

  const reset = useCallback(() => {
    setToken("");
    widget.current?.reset();
  }, []);

  const slot = <>
    {siteKey && <Script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" strategy="afterInteractive" onReady={() => setScriptReady(true)} />}
    {siteKey
      ? <div ref={setHost} className="captcha-slot" aria-label="Bot-skydd" />
      : <div className="captcha-slot" role="status">Bot-skyddet är inte konfigurerat ännu.</div>}
  </>;
  return { token, reset, slot };
}
