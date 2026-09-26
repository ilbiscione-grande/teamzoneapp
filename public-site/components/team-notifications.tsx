"use client";

import { useEffect, useState } from "react";
import { usePersonalAccount } from "./personal-account";

type TeamPreference = { id: string; name: string; is_own: boolean; news: boolean; results: boolean; reports: boolean; schedule: boolean; revision: number };
type Notification = { id: string; title: string; preview: string; web_link: string; unread: boolean; created_at: string };
type Notifications = { unread_count: number; items: Notification[]; teams: TeamPreference[] };

export function TeamNotifications() {
  const { client, session, home } = usePersonalAccount();
  const [data,setData] = useState<Notifications|null>(null);
  const [revision,setRevision] = useState(0);
  const [error,setError] = useState("");
  const [busy,setBusy] = useState(false);
  const [limit,setLimit] = useState(10);
  const userId = session?.user.id;
  useEffect(() => {
    if (!client || !userId) return;
    let disposed = false, pending = false;
    async function load() {
      if (pending || document.visibilityState === "hidden") return;
      pending = true;
      try {
        const {data,error} = await client!.schema("api").rpc("get_team_notifications");
        if (disposed) return;
        if (error) throw error;
        setData(data as Notifications);setError("");
      } catch {if(!disposed)setError("Notiserna kunde inte hämtas. Försök igen.");}
      finally {pending=false;}
    }
    void load();
    const timer = window.setInterval(()=>void load(),45000);
    const refresh = ()=>void load();
    window.addEventListener("focus",refresh);
    document.addEventListener("visibilitychange",refresh);
    return ()=>{disposed=true;window.clearInterval(timer);window.removeEventListener("focus",refresh);document.removeEventListener("visibilitychange",refresh);};
  },[client,userId,revision,home]);
  async function read(item?: Notification) {
    if (!client || busy) return;
    setBusy(true);setError("");
    try {
      const {error}=await client.schema("api").rpc(item?"set_notification_state":"mark_team_notifications_read",
        item?{notification_id:item.id,state:"read",idempotency_key:crypto.randomUUID()}:{idempotency_key:crypto.randomUUID()});
      if(error)throw error;
      setRevision(v=>v+1);
      if(item && item.web_link.startsWith("/") && !item.web_link.startsWith("//")) window.location.assign(item.web_link);
    }catch{setError("Läsmarkeringen kunde inte sparas. Försök igen.");}
    finally{setBusy(false);}
  }
  if(!userId)return null;
  return <section className="panel home-section team-notifications" aria-label="Lagnotiser">
    <details><summary>Notiser <span className="notification-count" aria-live="polite">{data?`${data.unread_count} olästa`:"Hämtar…"}</span></summary>
      {error&&<p role="alert">{error} <button onClick={()=>setRevision(v=>v+1)}>Försök igen</button></p>}
      <div className="notification-toolbar"><p>Nyheter från dina lag och lag du följer.</p><button disabled={busy||!data?.unread_count} onClick={()=>void read()}>Markera alla som lästa</button></div>
      <ul className="notification-list">{data?.items.slice(0,limit).map(item=><li key={item.id} className={item.unread?"unread":""}>
        <button disabled={busy} onClick={()=>void read(item)}><strong>{item.title}{item.unread?" · Nytt":""}</strong><span>{item.preview}</span><time dateTime={item.created_at}>{new Intl.DateTimeFormat("sv-SE",{dateStyle:"short",timeStyle:"short"}).format(new Date(item.created_at))}</time></button>
      </li>)}</ul>
      {data&&!data.items.length&&<p>Inga lagnotiser ännu. Nya händelser visas här.</p>}
      {data&&data.items.length>limit&&<button onClick={()=>setLimit(v=>v+20)}>Visa fler notiser</button>}
      <p className="dashboard-caption">De senaste 30 dagarna, högst 100 notiser. Uppdateras automatiskt.</p>
    </details>
    <details><summary>Notisinställningar per lag</summary>
      <p>Välj vad du vill få notiser om. Kalenderändringar gäller bara dina egna lag.</p>
      {data?.teams.map(team=><TeamSettings key={`${team.id}:${team.revision}`} team={team} onSaved={()=>setRevision(v=>v+1)}/>)}
      {data&&!data.teams.length&&<p>Följ ett lag eller en klubb för att få lagnotiser.</p>}
    </details>
  </section>;
}

function TeamSettings({team,onSaved}:{team:TeamPreference;onSaved:()=>void}) {
  const {client}=usePersonalAccount();
  const [value,setValue]=useState(team);
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState("");
  async function save(event:React.FormEvent) {
    event.preventDefault();if(!client||busy)return;
    setBusy(true);setError("");
    try{
      const {error}=await client.schema("api").rpc("set_team_notification_preferences",{
        p_team_id:team.id,p_news:value.news,p_results:value.results,p_reports:value.reports,p_schedule:value.schedule,p_expected_revision:team.revision});
      if(error)throw error;onSaved();
    }catch{setError("Inställningarna kunde inte sparas. Uppdatera sidan och försök igen.");}
    finally{setBusy(false);}
  }
  const options = [["news","Nyheter"],["results","Slutresultat"],["reports","Matchrapporter"],...(team.is_own?[["schedule","Ändrad tid eller plats"]]:[])] as ["news"|"results"|"reports"|"schedule",string][];
  return <form className="team-notification-settings" onSubmit={save}><fieldset disabled={busy}><legend>{team.name} · {team.is_own?"Mitt lag":"Följer"}</legend>
    {options.map(([key,label])=><label key={key}><input type="checkbox" checked={value[key]} onChange={event=>setValue({...value,[key]:event.target.checked})}/>{label}</label>)}
    <button type="submit">{busy?"Sparar…":"Spara val"}</button>{error&&<p role="alert">{error}</p>}
  </fieldset></form>;
}
