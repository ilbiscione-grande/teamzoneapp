import { timeOf, type Organization, type SeriesOverride, type SeriesPlan } from "../../lib/booking";
import { SeriesConflictHelp } from './series-conflict-help';
import { seriesScopeLabel } from '../../lib/series-alternatives';
import { SeriesOccurrenceList } from './series-occurrence-list';

/** Explain the server's preview without treating it as an already saved booking. */
export function SeriesPreview({ plan, resources, asks, org, selected = [], disabled = false, onChoose, onReset }: { plan: SeriesPlan; resources: string; asks: boolean;
  org?: Organization; selected?: string[]; disabled?: boolean; onChoose?: (alternative: SeriesOverride) => void; onReset?: (original: string) => void }) {
  const skipped = plan.times.filter(time => time.clash);
  const free = plan.times.length - skipped.length;
  const outside = skipped.some(time => time.outside_disposition);
  const changed = plan.times.filter(time => time.changed);
  return <section className="wt-note bk-plan" aria-label="Förhandsvisning av bokningsserie" aria-live="polite">
    <p><strong>{free} av {plan.times.length} tillfällen kan bokas</strong></p>
    <p>{resources}</p>
    <p className="wt-small">Inget har bokats ännu. När du bekräftar {asks ? "skickas de bokningsbara tillfällena för godkännande" : "bokas de bokningsbara tillfällena"}. Tillgängligheten kontrolleras igen vid bekräftelsen. {plan.times.length === 0 ? "Datumintervallet innehåller inga tillfällen på de valda veckodagarna." : skipped.length > 0 ? "Övriga tillfällen hoppas över helt, för alla valda delar." : "Alla tillfällen i förhandsvisningen kan bokas."}</p>
    {skipped.length > 0 && <details open>
      <summary>{skipped.length} {skipped.length === 1 ? "tillfälle hoppas" : "tillfällen hoppas"} över – visa orsaker</summary>
      <ul tabIndex={0} aria-label="Tillfällen som hoppas över" style={{maxHeight:240,overflowY:"auto",paddingRight:8}}>
        {skipped.map(time => <li key={`${time.starts_at}:${time.ends_at}`} style={{textTransform:'none'}}>
          <strong>{new Date(time.starts_at).toLocaleDateString("sv-SE",{weekday:"short",day:"numeric",month:"short",year:"numeric"})} · {timeOf(time.starts_at)}–{timeOf(time.ends_at)}</strong>
          {time.blocked_resources?.length ? time.blocked_resources.map(item=><div key={item.resource_id}>{item.name}: {item.outside_disposition ? 'utanför bokningsbara tider eller dispositionsperiod.' : 'upptagen, eller spärrad av en överlappande plandel.'}</div>) : <div>{time.outside_disposition ? "Utanför resursens bokningsbara tider eller dispositionsperiod." : "En vald resurs eller en överlappande plandel är upptagen."}</div>}
          {org && onChoose && <SeriesConflictHelp key={JSON.stringify(time)} time={time} org={org} selected={selected} disabled={disabled} onChoose={onChoose} />}
        </li>)}
      </ul>
      {outside && <p className="wt-small">Dispositionsperiod, veckotider och datumundantag gäller även för planens delar.</p>}
      <p className="wt-small">Ändra tid, veckodagar, slutdatum eller omfattning och välj Visa tillfällen igen för att kontrollera ett annat upplägg.</p>
    </details>}
    {changed.length>0 && <details open><summary>{changed.length===1 ? '1 tillfälle har ett eget val' : `${changed.length} tillfällen har egna val`}</summary><ul style={{maxHeight:240,overflowY:'auto'}}>
      {changed.map(time=><li key={time.original_starts_at} style={{textTransform:'none'}}>
        <strong>{new Date(time.starts_at).toLocaleDateString('sv-SE',{day:'numeric',month:'short',year:'numeric'})} · {timeOf(time.starts_at)}–{timeOf(time.ends_at)}</strong>
        <div>{org && time.resource_ids && seriesScopeLabel(time.resource_ids,org.resources)}</div>
        <div>{time.clash ? 'Fortfarande blockerad – hoppas över.' : 'Kan bokas med detta val.'}</div>
        {onReset && time.original_starts_at && <button type="button" className="wt-link-button" disabled={disabled} onClick={()=>onReset(time.original_starts_at!)}>Återställ detta tillfälle</button>}
      </li>)}
    </ul></details>}
    <SeriesOccurrenceList plan={plan} resources={resources} org={org} />
    {free === 0 && <p><strong>Inga tillfällen kan bokas med de här valen.</strong></p>}
    {asks && <p className="wt-small">Hela serien godkänns av en administratör i ett steg.</p>}
  </section>;
}
