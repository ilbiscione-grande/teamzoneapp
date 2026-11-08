"use client";

import { useState } from 'react';
import { timeOf, type Organization, type SeriesPlan } from '../../lib/booking';
import { seriesScopeLabel } from '../../lib/series-alternatives';

/** Review the actual server plan, including unchanged dates and per-date exceptions. */
export function SeriesOccurrenceList({plan, resources, org}: {plan: SeriesPlan; resources: string; org?: Organization}) {
  const [filter,setFilter] = useState('all');
  const visible = plan.times.filter(time=>filter==='all' || (filter==='bookable' && !time.clash) || (filter==='skipped' && time.clash) || (filter==='changed' && time.changed));
  if (plan.times.length===0) return null;
  return <details>
    <summary>{plan.times.length===1 ? 'Granska tillfället' : `Granska alla ${plan.times.length} tillfällen`}</summary>
    <p className="wt-small">Kontrollera datum, tider och resurser före bekräftelsen. Listan är en förhandsvisning; inget är bokat ännu.</p>
    <label>Visa tillfällen
      <select value={filter} onChange={event=>setFilter(event.target.value)}>
        <option value="all">Alla ({plan.times.length})</option>
        <option value="bookable">Bokningsbara ({plan.times.filter(time=>!time.clash).length})</option>
        <option value="skipped">Hoppas över ({plan.times.filter(time=>time.clash).length})</option>
        <option value="changed">Egna val ({plan.times.filter(time=>time.changed).length})</option>
      </select>
    </label>
    <p className="wt-small" role="status">Visar {visible.length} av {plan.times.length}.</p>
    {visible.length===0 ? <p>Inga tillfällen matchar det valda filtret.</p> : <ol tabIndex={0} aria-label="Seriens tillfällen" style={{maxHeight:320,overflowY:'auto',paddingLeft:24,paddingRight:8,textTransform:'none'}}>
      {visible.map(time=><li key={time.original_starts_at ?? time.starts_at} style={{marginBottom:12,textTransform:'none',overflowWrap:'anywhere'}}>
        <strong>{new Date(time.starts_at).toLocaleDateString('sv-SE',{weekday:'short',day:'numeric',month:'short',year:'numeric'})} · {timeOf(time.starts_at)}–{timeOf(time.ends_at)}</strong>
        <div>{org && time.resource_ids ? seriesScopeLabel(time.resource_ids,org.resources) : resources}</div>
        <div><strong>{time.clash ? 'Hoppas över' : plan.status==='pending' ? 'Skickas för godkännande' : 'Kan bokas'}</strong>{time.changed ? ' · Eget val för detta datum' : ''}</div>
        {time.changed && time.original_starts_at && timeOf(time.original_starts_at)!==timeOf(time.starts_at) && <div className="wt-small">Ursprunglig starttid: {timeOf(time.original_starts_at)}.</div>}
        {time.clash && <div className="wt-small">{time.outside_disposition ? 'Utanför bokningsbara tider eller dispositionsperiod.' : 'En vald resurs eller överlappande plandel är upptagen.'}</div>}
      </li>)}
    </ol>}
  </details>;
}
