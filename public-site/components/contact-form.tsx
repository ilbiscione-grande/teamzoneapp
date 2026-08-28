"use client";

import Script from "next/script";
import { useEffect, useRef, useState } from "react";

type TurnstileApi = {
  render: (element: HTMLElement, options: Record<string, unknown>) => string;
  reset: (widgetId: string) => void;
};

declare global {
  interface Window {
    turnstile?: TurnstileApi;
  }
}

const siteKey = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY?.trim() ?? "";

export function ContactForm({ clubId }: { clubId: string }) {
  const [state, setState] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [captchaToken, setCaptchaToken] = useState("");
  const [scriptReady, setScriptReady] = useState(false);
  const widgetHost = useRef<HTMLDivElement>(null);
  const widgetId = useRef<string | null>(null);

  useEffect(() => {
    if (!siteKey || !scriptReady || !window.turnstile || !widgetHost.current || widgetId.current) return;
    widgetId.current = window.turnstile.render(widgetHost.current, {
      sitekey: siteKey,
      action: "contact",
      appearance: "interaction-only",
      size: "flexible",
      theme: "auto",
      callback: (token: string) => setCaptchaToken(token),
      "expired-callback": () => setCaptchaToken(""),
      "error-callback": () => setCaptchaToken(""),
    });
  }, [scriptReady]);

  function resetCaptcha() {
    setCaptchaToken("");
    if (widgetId.current && window.turnstile) window.turnstile.reset(widgetId.current);
  }

  async function submit(formData: FormData) {
    if (!captchaToken) return;
    setState("sending");
    try {
      const response = await fetch("/api/public/v1/contact", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          clubId,
          senderName: formData.get("senderName"),
          senderEmail: formData.get("senderEmail"),
          subject: formData.get("subject"),
          message: formData.get("message"),
          captchaToken,
        }),
      });
      setState(response.ok ? "sent" : "error");
    } catch {
      setState("error");
    } finally {
      resetCaptcha();
    }
  }

  return (
    <form className="contact-form" action={submit}>
      {siteKey && (
        <Script
          src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
          strategy="afterInteractive"
          onReady={() => setScriptReady(true)}
        />
      )}
      <label className="field">Namn<input name="senderName" minLength={2} maxLength={120} required /></label>
      <label className="field">E-post<input name="senderEmail" type="email" maxLength={254} required /></label>
      <label className="field">Ämne<input name="subject" minLength={2} maxLength={160} required /></label>
      <label className="field">Meddelande<textarea name="message" minLength={2} maxLength={2000} required /></label>
      {siteKey
        ? <div ref={widgetHost} className="captcha-slot" aria-label="Bot-skydd" />
        : <div className="captcha-slot" role="status">Bot-skyddet är inte konfigurerat ännu.</div>}
      <button className="primary-button" type="submit" disabled={!captchaToken || state === "sending"}>
        {state === "sending" ? "Skickar…" : "Skicka meddelande"}
      </button>
      {state === "sent" && <p role="status">Tack. Ditt meddelande har tagits emot.</p>}
      {state === "error" && <p role="alert">Meddelandet kunde inte skickas. Försök senare.</p>}
    </form>
  );
}
