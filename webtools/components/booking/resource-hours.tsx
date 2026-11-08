"use client";

import type { ResourceAvailability, ResourceWindow } from "../../lib/booking";

const days = ["Måndag", "Tisdag", "Onsdag", "Torsdag", "Fredag", "Lördag", "Söndag"];
const clock = (minute: number) => `${String(Math.floor((minute % 1440) / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`;
const minutes = (value: string) => { const [h, m] = value.split(":").map(Number); return h * 60 + m; };

function Windows({ value, onChange, label }: { value: ResourceWindow[]; onChange: (value: ResourceWindow[]) => void; label: string }) {
  return <div className="wt-form">
    {value.length === 0 && <p className="wt-small">Stängt hela dagen.</p>}
    {value.map((window, index) => <div className="bk-times" key={index}>
      <label>Från<input aria-label={`${label} från ${index + 1}`} type="time" required value={clock(window.start)} onChange={event => { if (event.target.value) onChange(value.map((item, i) => i === index ? { ...item, start: minutes(event.target.value) } : item)); }} /></label>
      <label>Till<input aria-label={`${label} till ${index + 1}`} type="time" required value={clock(window.end)} onChange={event => { if (event.target.value) onChange(value.map((item, i) => i === index ? { ...item, end: minutes(event.target.value) || 1440 } : item)); }} /></label>
      <button type="button" className="wt-button secondary small" aria-label={`${label} ta bort tid ${index + 1}`} onClick={() => onChange(value.filter((_, i) => i !== index))}>Ta bort tid</button>
    </div>)}
    <button type="button" className="wt-button secondary small" disabled={value.length >= 8} onClick={() => onChange([...value, { start: 480, end: 1020 }])}>Lägg till tid för {label.toLowerCase()}</button>
  </div>;
}

export function ResourceHours({ value, onChange }: { value: ResourceAvailability; onChange: (value: ResourceAvailability) => void }) {
  return <fieldset className="wt-form">
    <legend>Bokningsbara tider</legend>
    <p className="wt-small">Tiderna gäller i resursens tidszon och inom dispositionsperioden. Till 00:00 betyder dagens slut. Dela en tid över midnatt på två dagar.</p>
    <p className="wt-small">När klockan ställs tillbaka avser en tidsgräns i den upprepade timmen det andra klockslaget.</p>
    <label>Veckotider<select value={value.mode} onChange={event => onChange({ ...value, mode: event.target.value as ResourceAvailability["mode"] })}>
      <option value="always">Hela dygnet, alla dagar</option>
      <option value="weekly">Endast angivna veckotider</option>
    </select></label>
    {value.mode === "weekly" && days.map((day, index) => <div className="wt-form" key={day}>
      <h3>{day}</h3>
      <Windows label={day} value={value.weekly.filter(window => window.day === index + 1)} onChange={windows => onChange({ ...value, weekly: [...value.weekly.filter(window => window.day !== index + 1), ...windows.map(window => ({ ...window, day: index + 1 }))] })} />
    </div>)}
    <h3>Datumundantag</h3>
    <p className="wt-small">Ett undantag ersätter hela dagens veckotider. Lämna dagen utan tider för att stänga den, eller ange särskilda öppettider.</p>
    {value.exceptions.map((exception, index) => <fieldset className="wt-form" key={index}>
      <legend>Undantag {index + 1}</legend>
      <label>Datum<input type="date" required value={exception.date} onChange={event => onChange({ ...value, exceptions: value.exceptions.map((item, i) => i === index ? { ...item, date: event.target.value } : item) })} /></label>
      <Windows label={`Undantag ${index + 1}`} value={exception.windows} onChange={windows => onChange({ ...value, exceptions: value.exceptions.map((item, i) => i === index ? { ...item, windows } : item) })} />
      <button type="button" className="wt-button secondary small" onClick={() => onChange({ ...value, exceptions: value.exceptions.filter((_, i) => i !== index) })}>Ta bort undantag {index + 1}</button>
    </fieldset>)}
    <button type="button" className="wt-button secondary small" disabled={value.exceptions.length >= 366} onClick={() => onChange({ ...value, exceptions: [...value.exceptions, { date: "", windows: [] }] })}>Lägg till datumundantag</button>
  </fieldset>;
}
