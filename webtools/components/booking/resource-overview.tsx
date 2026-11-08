"use client";

import { useEffect, useRef, useState } from "react";
import { addDays, bookingError, bookingSpan, categoryLabels, categoryOrder, dateKey, localInstant, type Organization, type ResourceCategory } from "../../lib/booking";
import { availabilityGroups, availabilityState, type AvailabilityRow, type AvailabilityState } from "../../lib/availability-overview";
import { useAccount } from "../account";
import { BookingForm } from "./booking-form";
import { seriesScopeLabel } from "../../lib/series-alternatives";

const stateLabels: Record<AvailabilityState,string> = {inactive:"Inaktiv",unknown:"Inte bekräftad",outside:"Utanför bokningsbara tider",busy:"Upptagen",free:"Ledig den valda tiden"};
export function ResourceOverview({org}:{org:Organization}) {
 const {client}=useAccount();
 const [day,setDay]=useState(()=>new Date().getHours() >= 18 ? addDays(dateKey(new Date()),1) : dateKey(new Date())),[start,setStart]=useState("18:00"),[end,setEnd]=useState("19:30");
 const [rows,setRows]=useState<AvailabilityRow[]|null>(null),[busy,setBusy]=useState(false),[error,setError]=useState("");
 const [query,setQuery]=useState(""); const [category,setCategory]=useState<ResourceCategory | "all">("all"); const [onlyFree,setOnlyFree]=useState(false);
 const [filtersOpen,setFiltersOpen]=useState(false);
 const [draft,setDraft]=useState<string|null>(null),[notice,setNotice]=useState("");
 const generation=useRef(0);
 // Invalidate both displayed results and in-flight responses after every edit.
 useEffect(()=>{generation.current++;setRows(null);setBusy(false);setError("");setOnlyFree(false);setNotice("");},[day,start,end,org.resources]);
 useEffect(()=>()=>{generation.current++;},[]);
 async function check(){
  if(!client)return;
  if(!day||!start||!end||end<=start){setError("Välj datum och en sluttid efter starttiden.");return;}
  const from=localInstant(day,start),to=localInstant(day,end);
  if(new Date(from)<=new Date()){setError("Välj en starttid som inte har passerat.");return;}
  if(new Date(from).getHours()!==Number(start.slice(0,2))||new Date(to).getHours()!==Number(end.slice(0,2))){setError("Klocktiden finns inte vid övergången till sommartid.");return;}
  const request=++generation.current;setBusy(true);setError("");setRows(null);
  try{
   const result=await client.schema("api").rpc("list_booking_availability",{target_organization_id:org.id,range_start:from,range_end:to});
   if(request!==generation.current)return;
   if(result.error)setError(bookingError(result.error));else setRows((result.data ?? []) as AvailabilityRow[]);
  }catch{if(request===generation.current)setError("Tillgängligheten kunde inte hämtas. Försök igen.");}
  finally{if(request===generation.current)setBusy(false);}
 }
 const groups=availabilityGroups(org.resources,rows,query,category,onlyFree);
 const filtered=!!query.trim()||category!=="all"||onlyFree;
 const totals=org.resources.filter(resource=>resource.active).map(resource=>availabilityState(resource,rows));
 return <section className="wt-panel bk-availability-overview" aria-label="Resurser och tillgänglighet">
  <h2>Hitta en ledig resurs</h2>
  <p className="wt-small">Välj tid och kontrollera vilka resurser du kan boka.</p>
  <form className="wt-form" onSubmit={e=>{e.preventDefault();void check();}}><div className="bk-availability-times"><label>Datum<input type="date" required value={day} onChange={e=>setDay(e.target.value)}/></label><label>Från<input type="time" required value={start} onChange={e=>setStart(e.target.value)}/></label><label>Till<input type="time" required value={end} onChange={e=>setEnd(e.target.value)}/></label></div><button className="wt-button" disabled={busy}>{busy?"Kontrollerar…":"Kontrollera tillgänglighet"}</button></form>
  {error&&<p role="alert" className="wt-error">{error}</p>}{notice&&<p role="status">{notice}</p>}
  <details className="bk-availability-help"><summary>Om tider och bokning</summary><p className="wt-small">Valda tider i {Intl.DateTimeFormat().resolvedOptions().timeZone}. Välj sluttid senare samma dag. Dispositionstider tolkas i respektive resurs tidszon.</p><p className="wt-small">Varje resurs kontrolleras för sig. Lediga överordnade och underordnade delar kan inte bokas samtidigt. Tillgängligheten kontrolleras igen när du bokar.</p></details>
  <div className="bk-resource-controls bk-request-controls bk-availability-controls"><label>Sök resurs att boka<input type="search" value={query} onChange={event=>setQuery(event.target.value)} placeholder="Namn eller plats" /></label><button type="button" className="wt-button secondary small bk-availability-filter-toggle" aria-expanded={filtersOpen} aria-controls={`availability-filters-${org.id}`} onClick={()=>setFiltersOpen(value=>!value)}>Filter{category!=="all"?" · 1":""}</button><div id={`availability-filters-${org.id}`} className="bk-availability-filters" data-expanded={filtersOpen}><label>Typ av resurs<select value={category} onChange={event=>setCategory(event.target.value as ResourceCategory|"all")}><option value="all">Alla typer</option>{categoryOrder.map(value=><option key={value} value={value}>{categoryLabels[value]}</option>)}</select></label></div></div>
  <label className="wt-check"><input type="checkbox" checked={onlyFree} disabled={rows===null||busy} onChange={event=>setOnlyFree(event.target.checked)}/><span>Visa bara lediga resurser</span></label>
  <div className="bk-panel-heading"><p className="wt-small" role="status">{rows===null?"Kontrollera tiden för att få ett aktuellt besked.":`Kontrollerat ${day} · ${start}–${end}. Lediga: ${totals.filter(state=>state==="free").length} · Upptagna: ${totals.filter(state=>state==="busy").length} · Utanför tider: ${totals.filter(state=>state==="outside").length} · Okända: ${totals.filter(state=>state==="unknown").length}`}</p>{filtered&&<button type="button" className="wt-link-button" onClick={()=>{setQuery("");setCategory("all");setOnlyFree(false);}}>Rensa tillgänglighetsurval</button>}</div>
  <p className="wt-small">Matchande resurser: {groups.reduce((count,group)=>count+group.matchingIds.length,0)} av {org.resources.length}{category!=="all"?` · ${categoryLabels[category]}`:""}.{filtered&&" Relaterade delar visas för sammanhang, även när de inte matchar urvalet."}</p>
  {org.resources.length>0&&groups.length===0&&<p className="wt-note">Inga resurser matchar urvalet. Rensa urvalet, välj en annan tid eller kontrollera tillgängligheten igen.</p>}
  <ul className="bk-bookings">{groups.flatMap(group=>group.items.map(item=>({...item,matches:group.matchingIds.includes(item.resource.id)}))).map(({resource:r,depth,matches})=>{
   const state=rows?.find(x=>x.resource_id===r.id);
   const resultState=availabilityState(r,rows);
   return <li key={r.id} className="bk-booking" data-availability={resultState} style={{paddingInlineStart:`${Math.min(depth,6)*16+12}px`}}><div className="bk-booking-body"><strong>{seriesScopeLabel([r.id],org.resources)}</strong>{filtered&&<small>{matches?"Matchar urvalet":"Relaterad resurs · visas för sammanhang"}</small>}<span className="bk-availability-state">{stateLabels[resultState]}</span><span>{categoryLabels[r.category]}{r.requires_approval?" · Kräver godkännande":""}</span>
    {state?.busy_resource_name&&<span>Spärras av {state.busy_resource_name}{state.busy_from&&state.busy_to?` · ${bookingSpan(state.busy_from,state.busy_to)}`:""}</span>}
    <details><summary>Info och bokningstider</summary><p>{r.ownership_kind==="external"?`Externt disponerad · ${r.owner_name}`:r.ownership_kind==="owned"?"Egen resurs":"Ägande ej angivet"}{r.available_from?` · ${r.available_from}–${r.available_until || "tills vidare"} (${r.timezone})`:""}</p>{r.parent_resource_id&&<p>Även överordnade resursers tider gäller.</p>}<p>{r.availability?.mode==="weekly"?"Resursen har veckotider enligt nedan.":"Inga egna veckotider angivna. Dispositionsperioder, datumundantag och överordnade resursers tider gäller fortfarande."}</p>{r.availability?.weekly.map((w,i)=><p key={i}>{["Mån","Tis","Ons","Tor","Fre","Lör","Sön"][w.day-1]}: {minute(w.start)}–{minute(w.end)}</p>)}{r.availability?.exceptions.map(x=><p key={x.date}>{x.date}: {x.windows.length?x.windows.map(w=>`${minute(w.start)}–${minute(w.end)}`).join(", "):"Stängt"}</p>)}</details>
   </div>{resultState==="free"&&new Date(localInstant(day,start))>new Date()&&<button type="button" className="wt-button secondary small" onClick={()=>setDraft(r.id)}>Boka {r.name}</button>}</li>;
  })}</ul>
  {!org.resources.length&&<p>Inga resurser finns ännu.</p>}
  {draft&&<BookingForm org={org} resource={org.resources.find(r=>r.id===draft)??null} day={day} startTime={start} endTime={end} onClose={()=>setDraft(null)} onBooked={status=>{setDraft(null);setNotice(status==="pending"?"Bokningsförfrågan är skickad.":"Bokningen är klar.");void check();}}/>}
 </section>;
}
function minute(n:number){return `${String(Math.floor(n/60)).padStart(2,"0")}:${String(n%60).padStart(2,"0")}`;}
