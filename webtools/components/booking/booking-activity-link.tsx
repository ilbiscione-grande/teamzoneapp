"use client";

import { useEffect, useState } from "react";
import { bookingError, bookingSpan, eventOptionLabel, statusLabels, type Booking, type Organization, type TeamEvent } from "../../lib/booking";
import { bookingCommand } from "../../lib/booking-command";
import { useAccount } from "../account";

type LinkPlan = {event_title:string;event_starts_at:string;event_ends_at:string;bookings:{id:string;resource_name:string;starts_at:string;ends_at:string;status:Booking["status"]}[]};
export function BookingActivityLink({booking,org,onChanged}:{booking:Booking;org:Organization;onChanged:()=>void}) {
 const {client}=useAccount();
 const [open,setOpen]=useState(false),[team,setTeam]=useState(""),[event,setEvent]=useState("");
 const [events,setEvents]=useState<TeamEvent[]>([]),[plan,setPlan]=useState<LinkPlan|null>(null);
 const [busy,setBusy]=useState(false),[loading,setLoading]=useState(false),[error,setError]=useState("");
 useEffect(()=>{
  setEvents([]);setEvent("");setPlan(null);setError("");
  if(!client||!team)return;
  let current=true;setLoading(true);
  client.schema("api").rpc("list_booking_team_events",{target_organization_id:org.id,target_team_id:team})
   .then(({data,error})=>{if(!current)return;setLoading(false);if(error)setError(bookingError(error));else setEvents(data as TeamEvent[]);},()=>{if(current){setLoading(false);setError("Aktiviteterna kunde inte hämtas.");}});
  return ()=>{current=false;};
 },[client,team,org.id]);
 if(booking.event_id||!booking.can_cancel||Date.parse(booking.starts_at)<=Date.now()||!org.teamzone_club_id||!org.teams.length)return null;
 async function run(save:boolean){
  if(!client||!team||!event)return;
  setBusy(true);setError("");
  const payload={target_booking_id:booking.id,target_team_id:team,target_event_id:event};
  try{
   const result=save?await bookingCommand(client,"link_booking_activity",{...payload,expected_plan:plan}):await client.schema("api").rpc("preview_booking_activity_link",payload);
   if(result.error){setError(bookingError(result.error));if(result.error.message==="stale_revision")setPlan(null);}
   else if(save)onChanged();else setPlan(result.data as LinkPlan);
  }catch{setError("Svaret kunde inte hämtas. Försök igen med samma val.");}
  finally{setBusy(false);}
 }
 if(!open)return <button type="button" className="wt-button secondary" onClick={()=>setOpen(true)}>Koppla till aktivitet</button>;
 return <section className="wt-form" aria-label="Koppla bokning till aktivitet">
  <h3>Koppla till aktivitet</h3>
  <p>Bokningens tider och godkännande behålls. Alla aktiva resurser som bokades tillsammans kopplas till samma aktivitet. I en serie gäller kopplingen bara det här tillfället.</p>
  <label>Lag<select value={team} disabled={busy} onChange={e=>setTeam(e.target.value)}><option value="">Välj lag</option>{org.teams.map(t=><option key={t.team_id} value={t.team_id}>{t.name}</option>)}</select></label>
  <label>Aktivitet<select value={event} disabled={busy||loading} onChange={e=>{setEvent(e.target.value);setPlan(null);setError("");}}><option value="">{loading?"Hämtar aktiviteter…":"Välj aktivitet"}</option>{events.map(e=><option key={e.event_id} value={e.event_id}>{eventOptionLabel(e)}</option>)}</select></label>
  {team&&!loading&&!events.length&&!error&&<p>Inga kommande aktiviteter finns för laget.</p>}
  {plan&&<div role="region" aria-label="Förhandsvisning av aktivitetskoppling"><h4>{plan.event_title}</h4><p>Aktivitet: {new Date(plan.event_starts_at).toLocaleDateString("sv-SE")} · {bookingSpan(plan.event_starts_at,plan.event_ends_at)}</p><ul>{plan.bookings.map(b=><li key={b.id}>{b.resource_name}: {new Date(b.starts_at).toLocaleDateString("sv-SE")} · {bookingSpan(b.starts_at,b.ends_at)} · {statusLabels[b.status]}</li>)}</ul><p>Kontrollera eventuella tidsmarginaler ovan. När aktiviteten sedan flyttas följer bokningarna med sina marginaler. Om aktiviteten ställs in avbokas resurserna.</p></div>}
  {error&&<p className="wt-error" role="alert">{error}</p>}
  <div className="wt-actions"><button type="button" className="wt-button" disabled={busy||!event||loading} onClick={()=>void run(!!plan)}>{busy?"Kontrollerar…":plan?"Bekräfta kopplingen":"Förhandsvisa kopplingen"}</button><button type="button" className="wt-button secondary" disabled={busy} onClick={()=>{setOpen(false);setPlan(null);}}>Avbryt kopplingen</button></div>
 </section>;
}
