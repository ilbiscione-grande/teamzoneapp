"use client";

import { useState } from "react";
import { sendSurvey } from "../app/enkat/[token]/actions";
import type { PublicSurvey, SurveyAnswer, SurveyQuestion } from "../lib/survey";

export function SurveyForm({ token, survey }: { token: string; survey: PublicSurvey }) {
  const [values, setValues] = useState<Record<string, SurveyAnswer>>(survey.answers ?? {});
  const [name, setName] = useState("");
  const [state, setState] = useState<"idle" | "sending" | "sent">("idle");
  const [error, setError] = useState("");
  const closed = survey.state === "closed";
  const answeredBefore = survey.answers != null && Object.keys(survey.answers).length > 0;
  const set = (id: string, value: SurveyAnswer | undefined) => setValues(current => {
    const next = { ...current };
    if (value === undefined) delete next[id]; else next[id] = value;
    return next;
  });

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (state === "sending" || closed) return;
    setState("sending"); setError("");
    try {
      const result = await sendSurvey(token, name, values);
      if (result.ok) { setState("sent"); window.scrollTo({ top: 0 }); return; }
      setError(result.error);
    } catch {
      setError("Svaren kunde inte skickas. Kontrollera anslutningen och försök igen.");
    }
    setState("idle");
  }

  if (state === "sent") {
    return (
      <div className="wt-panel sv-sent" role="status">
        <h2>Tack för dina svar!</h2>
        <p>Svaren har skickats till dina ledare.</p>
        {survey.kind === "personal"
          ? <p className="wt-small">Du kan öppna länken igen och ändra svaren så länge enkäten är öppen.</p>
          : <button type="button" className="wt-button secondary small" onClick={() => { setValues({}); setName(""); setState("idle"); }}>Svara för någon annan</button>}
      </div>
    );
  }

  return (
    <form className="wt-panel wt-form sv-form" onSubmit={submit} aria-label={survey.title}>
      {closed && <p className="wt-note">Enkäten är stängd och tar inte emot fler svar.</p>}
      {!closed && answeredBefore && <p className="wt-note">Du har redan svarat. Ändra det du vill och skicka igen.</p>}
      {survey.kind === "open" && (
        <label>Ditt namn *
          <input value={name} onChange={event => setName(event.target.value)} autoComplete="name" required minLength={2} maxLength={120} disabled={closed || state === "sending"} />
        </label>
      )}
      <ol className="sv-questions">
        {survey.questions.map(question => (
          <li key={question.id}>
            <Question question={question} value={values[question.id]} disabled={closed || state === "sending"} onChange={value => set(question.id, value)} />
          </li>
        ))}
      </ol>
      <p className="wt-small">Svaren läses bara av lagets ledare.{survey.kind === "personal" ? " De kopplas till dig i laget." : ""}</p>
      {error && <p role="alert" className="wt-error">{error}</p>}
      {!closed && <button className="wt-button" disabled={state === "sending"}>{state === "sending" ? "Skickar…" : answeredBefore ? "Spara svaren" : "Skicka svaren"}</button>}
    </form>
  );
}

function Question({ question, value, disabled, onChange }: {
  question: SurveyQuestion; value: SurveyAnswer | undefined; disabled: boolean; onChange: (value: SurveyAnswer | undefined) => void;
}) {
  const label = `${question.label}${question.required ? " *" : ""}`;
  if (question.kind === "text" || question.kind === "long_text") {
    const text = typeof value === "string" ? value : "";
    return (
      <label className="sv-question">{label}
        {question.kind === "text"
          ? <input value={text} maxLength={300} required={question.required} disabled={disabled} onChange={event => onChange(event.target.value || undefined)} />
          : <textarea value={text} maxLength={4000} rows={4} required={question.required} disabled={disabled} onChange={event => onChange(event.target.value || undefined)} />}
      </label>
    );
  }
  if (question.kind === "scale") {
    return (
      <fieldset className="sv-question" disabled={disabled}>
        <legend>{label}</legend>
        <div className="sv-scale">
          {[1, 2, 3, 4, 5].map(step => (
            <label key={step} className="sv-step">
              <input type="radio" name={question.id} value={step} checked={value === step} required={question.required} onChange={() => onChange(step)} />
              <span>{step}</span>
            </label>
          ))}
        </div>
        {(question.low || question.high) && <div className="sv-scale-words"><span>{question.low ? `1 = ${question.low}` : ""}</span><span>{question.high ? `5 = ${question.high}` : ""}</span></div>}
      </fieldset>
    );
  }
  const options = question.options ?? [];
  if (question.kind === "single") {
    return (
      <fieldset className="sv-question" disabled={disabled}>
        <legend>{label}</legend>
        {options.map(option => (
          <label key={option} className="wt-check sv-option">
            <input type="radio" name={question.id} checked={value === option} required={question.required} onChange={() => onChange(option)} />
            <span>{option}</span>
          </label>
        ))}
      </fieldset>
    );
  }
  const picked = Array.isArray(value) ? value : [];
  return (
    <fieldset className="sv-question" disabled={disabled}>
      <legend>{label}<span className="wt-small"> (välj en eller flera)</span></legend>
      {options.map(option => (
        <label key={option} className="wt-check sv-option">
          <input type="checkbox" checked={picked.includes(option)} onChange={event => {
            const next = event.target.checked ? [...picked, option] : picked.filter(item => item !== option);
            onChange(next.length ? next : undefined);
          }} />
          <span>{option}</span>
        </label>
      ))}
    </fieldset>
  );
}
