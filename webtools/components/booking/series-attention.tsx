"use client";

import {useCallback,useEffect,useRef,useState} from 'react';
import {useAccount} from '../account';
import {bookingError,type Resource} from '../../lib/booking';
import {filterSeriesPlans,seriesResourceNames,type SeriesOverviewPlan} from '../../lib/series-overview';

type AttentionPlan=SeriesOverviewPlan & {anchor_booking_id:string};

export function SeriesAttentionSummary({plans,resources,loading,error,onRefresh,onOpen}: {
  plans:AttentionPlan[]|null;resources:Resource[];loading:boolean;error:string;
  onRefresh:()=>void;onOpen:(bookingId:string|null)=>void;
}) {
  const attention=filterSeriesPlans(plans??[],resources,'','attention');
  if (!error && !loading && plans !== null && attention.length === 0) return (
    <section className="wt-panel bk-overview-clear" aria-label="Serier som behöver ses över">
      <p>Inga serier behöver ses över.</p>
      <div className="bk-overview-clear-actions">
        <button type="button" className="wt-link-button" aria-label="Uppdatera seriestatus" onClick={onRefresh}>Uppdatera</button>
        <button type="button" className="wt-link-button" aria-label="Visa återkommande bokningar" onClick={()=>onOpen(null)}>Visa serier</button>
      </div>
    </section>
  );
  return <section className="wt-panel" aria-label="Serier som behöver ses över">
    <div className="bk-panel-heading"><h3>Framtida tillfällen att se över</h3><button type="button" className="wt-link-button" disabled={loading} onClick={onRefresh}>Uppdatera seriestatus</button></div>
    <p className="wt-small">Blockerade tillfällen och problem med automatiken. Redan skapade bokningar hanteras i kalendern.</p>
    {error ? <p role="alert" className="wt-error">{error} Seriestatusen kunde inte kontrolleras.</p>
      : loading || plans===null ? <p role="status">Kontrollerar framtida tillfällen…</p>
      : attention.length===0 ? <p>Inga serier behöver ses över just nu.</p>
      : <>
        <p role="status"><strong>{attention.length===1 ? '1 serie behöver ses över.' : `${attention.length} serier behöver ses över.`}</strong></p>
        <ul className="bk-bookings">{attention.slice(0,3).map(plan=><li key={plan.id} className="bk-booking" style={{flexWrap:'wrap'}}>
          <div className="bk-booking-body" style={{minWidth:0,overflowWrap:'anywhere'}}>
            <strong>{plan.title || 'Återkommande bokning'}</strong>
            <span>{seriesResourceNames(plan,resources).join(', ') || 'Inga resurser angivna'}</span>
            <span>{plan.slots.filter(slot=>slot.state==='blocked').length} blockerade tillfällen{plan.state==='paused' ? ' · Automatiken är pausad' : ''}</span>
            {plan.last_error && <span>{bookingError({message:plan.last_error})}</span>}
            {!plan.last_error && !plan.slots.some(slot=>slot.state==='blocked') && <span>Seriens status behöver granskas.</span>}
          </div>
          <button type="button" className="wt-button secondary small" onClick={()=>onOpen(plan.anchor_booking_id)} aria-label={`Granska serien ${plan.title || 'Återkommande bokning'}`}>Granska serien</button>
        </li>)}</ul>
        {attention.length>3 && <p className="wt-small">Visar tre av {attention.length} serier som behöver ses över.</p>}
      </>}
    <button type="button" className="wt-button secondary small" onClick={()=>onOpen(null)}>Visa återkommande bokningar</button>
  </section>;
}

export function SeriesAttention({organizationId,resources,onOpen}:{organizationId:string;resources:Resource[];onOpen:(bookingId:string|null)=>void}) {
  const {client}=useAccount();const [plans,setPlans]=useState<AttentionPlan[]|null>(null);
  const [loading,setLoading]=useState(false),[error,setError]=useState('');const generation=useRef(0);
  const load=useCallback(async()=>{
    if(!client)return;const request=++generation.current;setLoading(true);setError('');setPlans(null);
    try {
      const result=await client.schema('api').rpc('list_booking_series_plans',{target_organization_id:organizationId});
      if(request!==generation.current)return;
      if(result.error)setError(bookingError(result.error));else if(Array.isArray(result.data))setPlans(result.data as AttentionPlan[]);else setError('Svaret saknade seriestatus.');
    }catch{if(request===generation.current)setError('Försök igen.');}
    finally{if(request===generation.current)setLoading(false);}
  },[client,organizationId]);
  useEffect(()=>{void load();return()=>{generation.current++;};},[load]);
  return <SeriesAttentionSummary plans={plans} resources={resources} loading={loading} error={error} onRefresh={()=>void load()} onOpen={onOpen}/>;
}
