"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { useAccount } from "../account";
import { bookingError, type Booking, type Resource } from "../../lib/booking";
import { bookingCommand } from "../../lib/booking-command";
import { filterSeriesPlans, seriesNeedsAttention, seriesResourceNames, seriesSchedule, type SeriesStatusFilter } from "../../lib/series-overview";
type Config={first_day:string;ends_on:string;start_time:string;end_time:string;end_day_offset:number;timezone:string;frequency:string;interval:number;weekdays:number[];automatic:boolean;resource_ids:string[];resources?:{resource_id:string;resource_name:string;start_offset:number;end_offset:number}[]};
type Slot={id:string;local_start:string;state:string;reason:string|null};
type Saved={id:string;anchor_booking_id:string;revision:number;state:string;last_error:string|null;configuration:Config;title?:string;slots:Slot[]};
type Data={plan:Saved|null;defaults:Config;slots:Slot[]};
type Preview={configuration:Config;slots:{local_start:string;generate_now:boolean;conflicts:{resource_name?:string;reason:string}[]}[]};
const when=(s:string)=>s.replace("T"," ").slice(0,16);
export function BookingSeriesPlanEditor({bookingId,resources,onChanged,initiallyOpen=false,onClose}:{bookingId:string;resources:Resource[];onChanged:()=>void;initiallyOpen?:boolean;onClose?:()=>void}){
 const {client}=useAccount();const [open,setOpen]=useState(initiallyOpen);const [data,setData]=useState<Data|null>(null);const [cfg,setCfg]=useState<Config|null>(null);const [preview,setPreview]=useState<Preview|null>(null);const [busy,setBusy]=useState(false);const [error,setError]=useState("");
 const load=useCallback(async()=>{if(!client)return;setBusy(true);setError("");try{const r=await client.schema("api").rpc("get_booking_series_plan",{target_booking_id:bookingId});if(r.error){setError(bookingError(r.error));return;}const d=r.data as Data;setData(d);const c=d.plan?.configuration??d.defaults;setCfg({...c,first_day:c.first_day>d.defaults.first_day?c.first_day:d.defaults.first_day,resource_ids:c.resources?.map(x=>x.resource_id)??[]});setPreview(null);}catch{setError("Seriegrunden kunde inte hämtas.");}finally{setBusy(false);}},[client,bookingId]);
 useEffect(()=>{if(open)void load();},[open,load]);
 function change<K extends keyof Config>(key:K,value:Config[K]){if(cfg){setCfg({...cfg,[key]:value});setPreview(null);setError("");}}
 async function review(){if(!client||!cfg)return;setBusy(true);setError("");try{const r=await client.schema("api").rpc("preview_booking_series_plan",{target_booking_id:bookingId,configuration:cfg});if(r.error)setError(bookingError(r.error));else setPreview(r.data as Preview);}catch{setError("Förhandsvisningen kunde inte hämtas.");}finally{setBusy(false);}}
 async function save(){if(!client||!cfg||!preview)return;setBusy(true);setError("");try{const r=await bookingCommand(client,"save_booking_series_plan",{target_booking_id:bookingId,configuration:cfg,expected_plan:preview});if(r.error){setError(bookingError(r.error));setPreview(null);}else{await load();onChanged();}}catch{setError("Svaret kunde inte hämtas. Försök igen med samma ändring.");}finally{setBusy(false);}}
 async function control(action:string){if(!client||!data?.plan)return;setBusy(true);setError("");try{const r=await bookingCommand(client,"control_booking_series_plan",{plan_id:data.plan.id,action,expected_revision:data.plan.revision});if(r.error)setError(bookingError(r.error));else{await load();onChanged();}}catch{setError("Åtgärden kunde inte slutföras.");}finally{setBusy(false);}}
 if(!open)return <button type="button" className="wt-button secondary" onClick={()=>setOpen(true)}>Seriegrund och framtida tillfällen</button>;
 return <section className="wt-form" aria-label="Seriegrund och framtida tillfällen"><h3>Seriegrund och framtida tillfällen</h3>
 <p>Planera nya tillfällen efter de som redan har skapats. Redan skapade tillfällen, manuella ändringar och avbokningar lämnas kvar. Automatiken bokar 90 dagar framåt. Bakgrundskontrollen går varje minut och tar en serie åt gången.</p>
 {data?.plan&&<><p><strong>{data.plan.state==="active"?"Automatik aktiv":"Automatik pausad"}</strong>{data.plan.last_error?` · ${bookingError({message:data.plan.last_error})}`:""}</p><div className="wt-actions"><button className="wt-button secondary" disabled={busy} onClick={()=>control(data.plan!.state==="active"?"pause":"resume")}>{data.plan.state==="active"?"Pausa automatiken":"Återuppta automatiken"}</button>{data.slots.some(s=>s.state==="blocked")&&<button className="wt-button secondary" disabled={busy} onClick={()=>control("retry")}>Försök igen med blockerade tillfällen</button>}</div>
 <p>{data.slots.filter(s=>s.state==="created").length} skapade, {data.slots.filter(s=>s.state==="queued").length} väntande och {data.slots.filter(s=>s.state==="blocked").length} blockerade tillfällen.</p>
 {!!data.slots.filter(s=>s.state==="blocked").length&&<div role="alert"><h4>Blockerade tillfällen</h4><ul>{data.slots.filter(s=>s.state==="blocked").map(s=><li key={s.id}>{when(s.local_start)}: {(()=>{try{return (JSON.parse(s.reason??"[]") as {reason:string;resource_name?:string}[]).map(x=>`${x.resource_name?x.resource_name+": ":""}${bookingError({message:x.reason})}`).join(" ");}catch{return s.reason;}})()}</li>)}</ul></div>}
 </>}
 {cfg&&<><h4>{data?.plan?"Ändra ännu inte skapade tillfällen":"Ny seriegrund"}</h4>
 <label>Första nya datum<input aria-label="Första nya datum" type="date" value={cfg.first_day} disabled={busy} onChange={e=>change("first_day",e.target.value)}/></label>
 <label>Slutdatum<input aria-label="Seriens slutdatum" type="date" value={cfg.ends_on} disabled={busy} onChange={e=>change("ends_on",e.target.value)}/></label>
 <label>Upprepning<select aria-label="Seriens upprepning" value={cfg.frequency} disabled={busy} onChange={e=>change("frequency",e.target.value)}><option value="daily">Dagligen</option><option value="weekly">Veckovis</option><option value="monthly">Månadsvis, samma datum</option></select></label>
 <label>Intervall<input aria-label="Seriens intervall" type="number" min="1" max="52" value={cfg.interval} disabled={busy} onChange={e=>change("interval",Number(e.target.value))}/></label>
 {cfg.frequency==="weekly"&&<fieldset disabled={busy}><legend>Veckodagar</legend>{["Måndag","Tisdag","Onsdag","Torsdag","Fredag","Lördag","Söndag"].map((d,i)=><label key={d}><input type="checkbox" style={{width:"auto",minHeight:0}} checked={cfg.weekdays.includes(i+1)} onChange={()=>change("weekdays",cfg.weekdays.includes(i+1)?cfg.weekdays.filter(v=>v!==i+1):[...cfg.weekdays,i+1])}/>{d}</label>)}</fieldset>}
 <label>Starttid<input aria-label="Seriegrundens starttid" type="time" value={cfg.start_time.slice(0,5)} disabled={busy} onChange={e=>change("start_time",e.target.value)}/></label>
 <label>Sluttid<input aria-label="Seriegrundens sluttid" type="time" value={cfg.end_time.slice(0,5)} disabled={busy} onChange={e=>change("end_time",e.target.value)}/></label>
 <label>Antal dagar till slut<input aria-label="Antal dagar till slut" type="number" min="0" max="31" value={cfg.end_day_offset} disabled={busy} onChange={e=>change("end_day_offset",Number(e.target.value))}/></label><p>Tiderna gäller {cfg.timezone}. Välj 0 dagar om tillfället slutar samma dag.</p>
 <fieldset disabled={busy}><legend>Resurser för nya tillfällen</legend>{resources.filter(r=>r.active||cfg.resource_ids.includes(r.id)).map(r=><label key={r.id}><input type="checkbox" style={{width:"auto",minHeight:0}} checked={cfg.resource_ids.includes(r.id)} onChange={()=>change("resource_ids",cfg.resource_ids.includes(r.id)?cfg.resource_ids.filter(v=>v!==r.id):[...cfg.resource_ids,r.id])}/>{r.name}{!r.active?" · inaktiv":""}</label>)}</fieldset>
 <p>Kvarvarande resurser behåller sina marginaler från det valda tillfället. Nya resurser följer grundtiden. Varje tillfälle skapas med alla valda resurser eller blockeras helt.</p>
 <label><input type="checkbox" style={{width:"auto",minHeight:0}} checked={cfg.automatic} disabled={busy} onChange={e=>change("automatic",e.target.checked)}/>Aktivera automatisk generering. Om du lämnar detta avmarkerat sparas planen pausad.</label>
 {preview&&<div role="region" aria-label="Förhandsvisning av seriegrunden"><h4>Kontrollera nya tillfällen ({preview.slots.length})</h4><p>Lediga tillfällen inom 90 dagar skapas när den aktiva planen sparas. Övriga väntar. Konflikter blockerar hela det enskilda tillfället; de andra kan skapas. Ändringen bygger inte om tidigare tillfällen.</p><ul>{preview.slots.map((s,i)=><li key={i}>{when(s.local_start)} · {s.conflicts.length?s.conflicts.map(c=>`${c.resource_name??"Tillfället"}: ${bookingError({message:c.reason})}`).join(" "):s.generate_now?"Skapas nu om automatiken är aktiv":"Väntar tills det ligger inom 90 dagar"}</li>)}</ul></div>}
 <div className="wt-actions"><button className="wt-button" disabled={busy} onClick={preview?save:review}>{busy?"Kontrollerar…":preview?"Bekräfta seriegrunden":"Förhandsvisa seriegrunden"}</button></div></>}
 {error&&<p role="alert" className="wt-error">{error}</p>}
 <button className="wt-button secondary" disabled={busy} onClick={()=>{setOpen(false);onClose?.();}}>Stäng seriegrunden</button>
 </section>;
}
export function BookingSeriesPlans({organizationId,resources,initialBookingId}:{organizationId:string;resources:Resource[];initialBookingId?:string}){
 const {client}=useAccount();const [plans,setPlans]=useState<Saved[]|null>(null);const [error,setError]=useState("");const [selected,setSelected]=useState<string|null>(initialBookingId??null);const [query,setQuery]=useState("");const [status,setStatus]=useState<SeriesStatusFilter>("all");const [loading,setLoading]=useState(false);const editor=useRef<HTMLDivElement>(null);const generation=useRef(0);
 const load=useCallback(async()=>{if(!client)return;const request=++generation.current;setLoading(true);setError("");try{const r=await client.schema("api").rpc("list_booking_series_plans",{target_organization_id:organizationId});if(request!==generation.current)return;if(r.error)setError(bookingError(r.error));else setPlans((r.data??[]) as Saved[]);}catch{if(request===generation.current)setError("Serierna kunde inte hämtas. Försök igen.");}finally{if(request===generation.current)setLoading(false);}},[client,organizationId]);useEffect(()=>{void load();return()=>{generation.current++;};},[load]);
 useEffect(()=>{if(selected)editor.current?.scrollIntoView({block:"start",behavior:"smooth"});},[selected]);
 const shown=filterSeriesPlans(plans??[],resources,query,status);const filtered=!!query.trim()||status!=="all";
 const statuses:{value:SeriesStatusFilter;label:string;name:string;count:number}[]=[
  {value:"all",label:"Alla",name:"Alla serier",count:plans?.length??0},
  {value:"attention",label:"Att se över",name:"Behöver ses över",count:(plans??[]).filter(seriesNeedsAttention).length},
  {value:"active",label:"Aktiva",name:"Aktiv automatik",count:(plans??[]).filter(plan=>plan.state==="active").length},
  {value:"paused",label:"Pausade",name:"Pausade serier",count:(plans??[]).filter(plan=>plan.state==="paused").length},
 ];
 return <section className="wt-panel bk-series-overview" aria-label="Serier">
  <div className="bk-panel-heading bk-series-heading"><h2>Återkommande bokningar</h2><button type="button" className="wt-button secondary small bk-series-refresh" aria-label="Uppdatera serier" title="Uppdatera serier" disabled={loading||selected!==null} onClick={()=>void load()}><span aria-hidden="true">↻</span><span className="bk-series-refresh-text">Uppdatera</span></button></div>
  <p className="wt-small">Planera nya tillfällen. Bokade tider ändras i kalendern och ligger kvar när serien pausas.</p>
  <div className="bk-series-totals" role="group" aria-label="Filtrera serier efter status">{statuses.map(item=><button key={item.value} type="button" aria-label={`${item.name}: ${plans===null ? "laddar" : item.count}`} aria-pressed={status===item.value} data-status={item.value} data-attention={item.value==="attention"&&item.count>0} disabled={loading||plans===null||selected!==null} onClick={()=>setStatus(value=>value===item.value?"all":item.value)}><span>{item.label}</span><strong>{plans===null?"…":item.count}</strong></button>)}</div>
  <div className="bk-resource-controls bk-request-controls"><label>Sök serie<input type="search" value={query} disabled={selected!==null} onChange={event=>setQuery(event.target.value)} placeholder="Rubrik, resurs eller datum"/></label></div>
  <div className="bk-panel-heading"><p className="wt-small" role="status">{loading?"Hämtar serier…":`Visar ${shown.length} av ${plans?.length??0} serier · sådant som behöver ses över visas först${status!=="all"?` · ${statuses.find(item=>item.value===status)?.name}`:""}`}</p>{filtered&&<button type="button" className="wt-link-button" disabled={selected!==null} onClick={()=>{setQuery("");setStatus("all");}}>Rensa serieurval</button>}</div>
  {error&&<p className="wt-error" role="alert">{error}</p>}
  {!loading&&!error&&plans?.length===0&&<p className="wt-note">Ingen plan för framtida tillfällen finns ännu. Öppna en återkommande bokning i kalendern och välj ”Seriegrund och framtida tillfällen” för att planera fler tillfällen.</p>}
  {!loading&&!error&&!!plans?.length&&shown.length===0&&<p className="wt-note">Inga serier matchar urvalet. Ändra sökningen eller rensa serieurvalet.</p>}
  {shown.map(plan=><article key={plan.id} className="bk-series-card" data-attention={seriesNeedsAttention(plan)}>
   <div className="bk-panel-heading"><h3>{plan.title||"Återkommande bokning"}</h3><strong>{plan.state==="active"?"Automatik aktiv":plan.state==="paused"?"Automatik pausad":"Behöver ses över"}</strong></div>
   <p>{seriesSchedule(plan)}</p><p className="wt-small">{plan.configuration.first_day}–{plan.configuration.ends_on} · {plan.configuration.timezone}</p><p>{seriesResourceNames(plan,resources).join(", ")||"Inga resurser angivna"}</p>
   <p className="wt-small">Skapade tillfällen: {plan.slots.filter(slot=>slot.state==="created").length} · Väntar på generering: {plan.slots.filter(slot=>slot.state==="queued").length} · Blockerade: {plan.slots.filter(slot=>slot.state==="blocked").length}</p>
   {seriesNeedsAttention(plan)&&<p className="wt-note">{plan.last_error?bookingError({message:plan.last_error}):"Öppna hanteringen för att granska blockerade tillfällen eller seriens status."}</p>}
   <button type="button" className="wt-button secondary" aria-expanded={selected===plan.anchor_booking_id} disabled={selected!==null} onClick={()=>setSelected(plan.anchor_booking_id)}>Hantera framtida tillfällen</button>
  </article>)}
  {selected&&<div ref={editor} className="bk-series-editor"><BookingSeriesPlanEditor key={selected} bookingId={selected} resources={resources} initiallyOpen onChanged={load} onClose={()=>setSelected(null)}/></div>}
 </section>;
}
