"use client";

import Script from "next/script";
import { useCallback, useEffect, useRef, useState } from "react";

type TurnstileApi = {
  render: (element: HTMLElement, options: Record<string, unknown>) => string;
  reset: (widgetId: string) => void;
};

const siteKey = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY?.trim() ?? "";

/** Cloudflare Turnstile for one action; the token is verified on the server. */
export function useTurnstile(action: string) {
  const [token, setToken] = useState("");
  const [scriptReady, setScriptReady] = useState(false);
  const host = useRef<HTMLDivElement>(null);
  const widget = useRef<string | null>(null);

  useEffect(() => {
    const api = (window as { turnstile?: TurnstileApi }).turnstile;
    if (!siteKey || !scriptReady || !api || !host.current || widget.current) return;
    widget.current = api.render(host.current, {
      sitekey: siteKey,
      action,
      appearance: "interaction-only",
      size: "flexible",
      theme: "light",
      callback: (value: string) => setToken(value),
      "expired-callback": () => setToken(""),
      "error-callback": () => setToken(""),
    });
  }, [scriptReady, action]);

  const reset = useCallback(() => {
    setToken("");
    const api = (window as { turnstile?: TurnstileApi }).turnstile;
    if (widget.current && api) api.reset(widget.current);
  }, []);

  const slot = <>
    {siteKey && <Script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" strategy="afterInteractive" onReady={() => setScriptReady(true)} />}
    {siteKey
      ? <div ref={host} className="captcha-slot" aria-label="Bot-skydd" />
      : <div className="captcha-slot" role="status">Bot-skyddet är inte konfigurerat ännu.</div>}
  </>;
  return { token, reset, slot };
}
