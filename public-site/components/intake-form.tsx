"use client";

import Link from "next/link";
import { useState } from "react";
import { useTurnstile } from "./turnstile";

const empty = { fullName: "", phone: "", email: "", birthDate: "", streetAddress: "", postalCode: "", city: "" };

export function IntakeForm({ token, receiver }: { token: string; receiver: string }) {
  const [values, setValues] = useState(empty);
  const [state, setState] = useState<"idle" | "sending" | "sent">("idle");
  const [error, setError] = useState("");
  const captcha = useTurnstile("intake");
  const set = (key: keyof typeof empty) => (event: React.ChangeEvent<HTMLInputElement>) =>
    setValues(current => ({ ...current, [key]: event.target.value }));

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (state === "sending") return;
    if (!captcha.token) { setError("Vänta tills bot-skyddet är klart och försök igen."); return; }
    setState("sending"); setError("");
    try {
      const response = await fetch("/api/public/v1/intake", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...values, token, captchaToken: captcha.token }),
      });
      if (!response.ok) {
        const data = await response.json().catch(() => ({})) as { error?: string };
        throw new Error(data.error || "Uppgifterna kunde inte skickas. Försök igen.");
      }
      setValues(empty);
      setState("sent");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Uppgifterna kunde inte skickas. Försök igen.");
      setState("idle");
    } finally {
      captcha.reset();
    }
  }

  if (state === "sent") {
    return <div className="pz-form-card pz-sent" role="status">
      <p className="cs-kicker">Tack!</p>
      <h2>Uppgifterna är skickade</h2>
      <p>{receiver} har tagit emot dina kontaktuppgifter. En ledare lägger till dig i laget.</p>
      <button type="button" className="cs-button small" onClick={() => setState("idle")}>Skicka för en person till</button>
    </div>;
  }

  return <form className="pz-form-card" onSubmit={submit} aria-label="Kontaktuppgifter">
    <label className="field">Namn<input name="fullName" autoComplete="name" required minLength={2} maxLength={120} value={values.fullName} onChange={set("fullName")} disabled={state === "sending"} /></label>
    <div className="pz-form-row">
      <label className="field">Telefon<input name="phone" type="tel" autoComplete="tel" required maxLength={30} value={values.phone} onChange={set("phone")} disabled={state === "sending"} /></label>
      <label className="field">E-post<input name="email" type="email" autoComplete="email" required maxLength={254} value={values.email} onChange={set("email")} disabled={state === "sending"} /></label>
    </div>
    <label className="field">Födelsedatum<input name="birthDate" type="date" autoComplete="bday" required min="1900-01-01" max={new Date().toISOString().slice(0, 10)} value={values.birthDate} onChange={set("birthDate")} disabled={state === "sending"} /></label>
    <label className="field">Gatuadress<input name="streetAddress" autoComplete="street-address" required minLength={2} maxLength={120} value={values.streetAddress} onChange={set("streetAddress")} disabled={state === "sending"} /></label>
    <div className="pz-form-row narrow-first">
      <label className="field">Postnummer<input name="postalCode" autoComplete="postal-code" inputMode="numeric" required minLength={3} maxLength={10} value={values.postalCode} onChange={set("postalCode")} disabled={state === "sending"} /></label>
      <label className="field">Postort<input name="city" autoComplete="address-level2" required minLength={2} maxLength={80} value={values.city} onChange={set("city")} disabled={state === "sending"} /></label>
    </div>
    <p className="pz-small muted">Uppgifterna skickas till {receiver} och används för att lägga till dig i laget och kontakta dig. Läs mer i <Link href="/integritet" target="_blank">integritetspolicyn</Link>.</p>
    {captcha.slot}
    {error && <p role="alert" className="pz-error">{error}</p>}
    <button className="primary-button" disabled={state === "sending"}>{state === "sending" ? "Skickar…" : "Skicka"}</button>
  </form>;
}
