"use client";

import { useRef, useState } from 'react';
import { timeOf, type Organization, type SeriesOverride, type SeriesTime } from '../../lib/booking';
import { checkedSeriesCandidate, seriesCandidates, seriesScopeLabel } from '../../lib/series-alternatives';
import { useAccount } from '../account';

export function SeriesConflictHelp({time, org, selected, disabled, onChoose}: {
  time: SeriesTime; org: Organization; selected: string[]; disabled: boolean;
  onChoose: (alternative: SeriesOverride) => void;
}) {
  const {client} = useAccount();
  const [loading,setLoading] = useState(false), [checked,setChecked] = useState(false);
  const [choices,setChoices] = useState<SeriesOverride[]>([]), [failed,setFailed] = useState(false);
  const running = useRef(false);
  const search = async () => {
    if (!client || running.current) return;
    running.current=true;setLoading(true);setFailed(false);setChoices([]);setChecked(false);
    try {
      const available: SeriesOverride[]=[];
      // Bounded checks, sequential to avoid a burst of organization locks.
      for (const candidate of seriesCandidates(time,selected,org.resources)) {
        const {data,error} = await client.schema('api').rpc('create_booking_group',{
          target_resource_ids:candidate.resource_ids,booking_starts_at:candidate.starts_at,booking_ends_at:candidate.ends_at,
          booking_title:null,booking_notes:null,target_team_id:null,target_event_id:null,dry_run:true,
        });
        if (error) throw error;
        if (checkedSeriesCandidate(candidate.resource_ids,data)) available.push(candidate);
      }
      setChoices(available);setChecked(true);
    } catch {setFailed(true);} finally {setLoading(false);running.current=false;}
  };
  return <div>
    <button type="button" className="wt-link-button" disabled={disabled || loading} onClick={search}>{loading ? 'Kontrollerar alternativ…' : checked ? 'Kontrollera alternativ igen' : 'Hitta lediga alternativ'}</button>
    {failed && <p role="alert">Alternativen kunde inte kontrolleras. Försök igen.</p>}
    {checked && choices.length===0 && <p className="wt-small">Inga lediga alternativ hittades samma dag inom två timmar eller bland motsvarande plandelar. Ändra seriens upplägg ovan eller låt tillfället hoppas över.</p>}
    {choices.length>0 && <div role="group" aria-label="Kontrollerade alternativ">
      <p className="wt-small">Ändrar bara detta tillfälle. Övriga veckor behåller sina val. Hela serien kontrolleras igen efter valet.</p>
      {choices.map(choice=><p key={`${choice.starts_at}:${choice.resource_ids.join(',')}`}><button type="button" className="wt-button secondary" disabled={disabled || loading} onClick={()=>onChoose(choice)}>
        Välj {timeOf(choice.starts_at)}–{timeOf(choice.ends_at)} · {seriesScopeLabel(choice.resource_ids,org.resources)}
      </button></p>)}
    </div>}
  </div>;
}
