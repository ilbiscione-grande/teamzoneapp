"use client";

import Link from "next/link";
import { WrittenMatchReport } from "./written-match-report";
import { useEffect, useState } from "react";
import { usePersonalAccount } from "./personal-account";
import { loadOwnTeamEvents, type OwnTeamEvent, type TeamContext } from "../lib/own-team-events";
import { channelHref, feedHref } from "../lib/personal-home";
import { combineCalendar, combineResults, dayKey, eventLabels, reportFacts, type DashboardContent, type DashboardEvent, type DashboardItem, type MatchReport } from "../lib/dashboard";

export function PersonalDashboard() {
  const { client, session, home, refresh } = usePersonalAccount();
  const [data, setData] = useState<{ account: string; content: DashboardContent | null; own: OwnTeamEvent[]; teams: TeamContext[]; privateError: boolean; publicError: boolean } | null>(null);
  const [revision, setRevision] = useState(0);
  const [busy, setBusy] = useState(true);
  const [newsScope, setNewsScope] = useState("own");
  const [now] = useState(() => new Date());
  const follows = home?.following.map(item => `${item.kind}:${item.id}`).sort().join(",");
  useEffect(() => {
    if (!session || !client) return;
    let disposed = false;
    setBusy(true); setData(null);
    const start = new Date(now.getTime() - 90 * 86400000).toISOString();
    const end = new Date(now.getTime() + 90 * 86400000).toISOString();
    Promise.allSettled([
      Promise.resolve(client.schema("api").rpc("get_personal_dashboard_content")).then(({data,error}) => { if(error) throw error; return data as DashboardContent; }),
      loadOwnTeamEvents((name, params) => client.schema("api").rpc(name, params), start, end),
    ]).then(([published, own]) => {
      if (disposed) return;
      setData({ account: session.user.id, content: published.status === "fulfilled" ? published.value : null, own: own.status === "fulfilled" ? own.value.items : [], teams: own.status === "fulfilled" ? own.value.teams : [], privateError: own.status === "rejected", publicError: published.status === "rejected" });
      setBusy(false);
    });
    return () => { disposed = true; };
  }, [client, session, revision, follows, now]);
  if (!session) return null;
  const current = data?.account === session.user.id ? data : null;
  const content = current?.content;
  const calendar = combineCalendar(content?.events ?? [], current?.own ?? [], now);
  const results = combineResults(content?.results ?? [], current?.own ?? []);
  const ownTeams = content?.available ? content.own_teams : (current?.teams ?? []).map(team => ({id: team.team_id!,name:team.team_name!,club_name:team.club_name,href:null}));
  const ownResults = results.filter(item => item.is_own);
  const otherResults = results.filter(item => !item.is_own);
  const news = (content?.news ?? []).filter(item => newsScope === "all" || item.is_own === (newsScope === "own"));
  const weekEnd = now.getTime() + 7 * 86400000;
  return <div className="personal-dashboard" aria-busy={busy}>
    <div className="dashboard-toolbar"><span>Din överblick · {new Intl.DateTimeFormat("sv-SE", { weekday:"long", day:"numeric", month:"long" }).format(now)}</span><button disabled={busy} onClick={() => { setRevision(v=>v+1); refresh(); }}>{busy ? "Hämtar…" : "Uppdatera dashboard"}</button></div>
    <div className="dashboard-stats">
      <a href="#dashboard-teams"><strong>{busy ? "–" : ownTeams.length}</strong><span>egna lag</span></a>
      <a href="#dashboard-calendar"><strong>{busy ? "–" : calendar.filter(item=>new Date(item.starts_at).getTime()<weekEnd).length}</strong><span>händelser nästa 7 dagar</span></a>
      <a href="#dashboard-results"><strong>{busy ? "–" : ownResults.length}</strong><span>senaste resultaten · egna lag</span></a>
      <a href="#dashboard-news"><strong>{busy ? "–" : content?.news.length ?? 0}</strong><span>senaste nyheterna</span></a>
    </div>
    {current?.privateError && <p role="alert">Informationen från dina egna lag kunde inte hämtas. Försök uppdatera dashboarden.</p>}
    {current?.publicError && <p role="alert">Nyheter och publicerat innehåll kunde inte hämtas. Försök uppdatera dashboarden.</p>}
    {content?.available === false && <p role="status">Publicerat innehåll är tillfälligt otillgängligt.</p>}
    <section className="dashboard-team-strip" id="dashboard-teams"><div><p className="eyebrow">Din lagkoppling</p><h2>Mina lag</h2></div><div className="dashboard-team-links">{ownTeams.map(team => team.href ? <Link key={team.id} href={team.href}><span className="team-avatar">{team.name.slice(0,2).toUpperCase()}</span><span><strong>{team.name}</strong><small>{team.club_name}</small></span></Link> : <div key={team.id}><span className="team-avatar">{team.name.slice(0,2).toUpperCase()}</span><span><strong>{team.name}</strong><small>{team.club_name}</small></span></div>)}{!busy && !ownTeams.length && <p>Inga lagkopplingar ännu. Dina följda lag visas nedan.</p>}</div></section>
    <div className="dashboard-columns">
      <div className="dashboard-main">
        <DashboardCalendar items={calendar} now={now} loading={busy} truncated={content?.calendar_truncated ?? false} />
        <ResultSection title="Resultat och matchrapporter" eyebrow="Mina lag" items={ownResults} loading={busy} own />
        <ResultSection title="Resultat från andra lag" eyebrow="Lag och klubbar du följer" items={otherResults} loading={busy} />
      </div>
      <aside className="dashboard-side">
        <section className="panel dashboard-panel" id="dashboard-news"><div className="section-heading"><div><p className="eyebrow">Från klubb och lag</p><h2>Nyheter</h2></div><span className="pill">{news.length}</span></div>
          <div className="feed-filters" role="group" aria-label="Nyheter från">{[["own","Mina lag"],["other","Följda lag"],["all","Alla"]].map(([value,label]) => <button key={value} aria-pressed={newsScope===value} onClick={()=>setNewsScope(value)}>{label}</button>)}</div>
          <div className="dashboard-news-list">{news.map((item,index) => <article key={item.id} className={index===0 ? "featured-news" : ""}><p className="eyebrow">{item.club_name} · {date(item.happened_at)}</p><h3><Link href={feedHref(item)}>{item.title}</Link></h3>{item.summary && <p>{item.summary}</p>}<Link className="article-link" href={feedHref(item)}>Läs nyheten →</Link></article>)}</div>
          {!busy && !news.length && <p className="empty-note">Inga publicerade nyheter i den här vyn ännu.</p>}
        </section>
        <section className="panel dashboard-panel"><p className="eyebrow">Håll koll</p><h2>Lag och klubbar jag följer</h2><div className="dashboard-follow-list">{home?.following.map(channel => <Link key={`${channel.kind}:${channel.id}`} href={channelHref(channel)}><span><strong>{channel.name}</strong><small>{channel.club_name || "Klubb"}</small></span><span aria-hidden="true">↗</span></Link>)}</div><Link className="follow-button" href="/klubbar">Hitta fler lag och klubbar →</Link>{home?.unavailable_count ? <p>Några följda sidor är inte publika just nu.</p> : null}</section>
      </aside>
    </div>
  </div>;
}

function DashboardCalendar({ items, now, loading, truncated }: { items: DashboardEvent[]; now: Date; loading: boolean; truncated: boolean }) {
  const [monthOffset,setMonthOffset]=useState(0);
  const [selectedDay,setSelectedDay]=useState<string | null>(null);
  const [kind,setKind]=useState("all");
  const [scope,setScope]=useState("all");
  const [limit,setLimit]=useState(8);
  const month=new Date(now.getFullYear(),now.getMonth()+monthOffset,1);
  const first=(month.getDay()+6)%7;
  const days=new Date(month.getFullYear(),month.getMonth()+1,0).getDate();
  const filtered=items.filter(item=>(kind==="all"||item.event_type===kind)&&(scope==="all"||item.is_own===(scope==="own")));
  const agenda=filtered.filter(item=>!selectedDay||dayKey(new Date(item.starts_at))===selectedDay);
  return <section className="panel dashboard-panel" id="dashboard-calendar"><div className="section-heading"><div><p className="eyebrow">Planera veckan</p><h2>Min kalender</h2></div><select aria-label="Välj laggrupp" value={scope} onChange={e=>setScope(e.target.value)}><option value="all">Alla lag</option><option value="own">Mina lag</option><option value="other">Följda lag</option></select></div>
    <div className="feed-filters" role="group" aria-label="Händelsetyp">{[["all","Alla"],...Object.entries(eventLabels)].map(([value,label])=><button key={value} aria-pressed={kind===value} onClick={()=>{setKind(value);setLimit(8);}}>{label}</button>)}</div>
    <div className="calendar-month-heading"><button aria-label="Föregående månad" disabled={monthOffset===0} onClick={()=>{setMonthOffset(v=>v-1);setSelectedDay(null);}}>‹</button><h3>{new Intl.DateTimeFormat("sv-SE",{month:"long",year:"numeric"}).format(month)}</h3><button aria-label="Nästa månad" disabled={monthOffset===3} onClick={()=>{setMonthOffset(v=>v+1);setSelectedDay(null);}}>›</button></div>
    <div className="calendar-grid">{["Mån","Tis","Ons","Tor","Fre","Lör","Sön"].map(day=><span className="calendar-weekday" key={day}>{day}</span>)}{Array.from({length:first},(_,i)=><span key={`blank-${i}`} />)}{Array.from({length:days},(_,i)=>{
      const day=new Date(month.getFullYear(),month.getMonth(),i+1), key=dayKey(day), events=filtered.filter(item=>dayKey(new Date(item.starts_at))===key);
      return <button key={key} className={`calendar-day ${key===dayKey(now)?"today":""}`} aria-pressed={selectedDay===key} aria-label={`${date(day.toISOString())}, ${events.length} händelser`} onClick={()=>{setSelectedDay(selectedDay===key?null:key);setLimit(8);}}><span>{i+1}</span><span className="calendar-dots">{[...new Set(events.map(item=>item.event_type))].map(type=><i key={type} className={`event-dot ${type}`} />)}</span></button>;
    })}</div>
    <div className="calendar-agenda-title"><h3>{selectedDay ? date(`${selectedDay}T12:00:00`) : "På gång"}</h3>{selectedDay && <button onClick={()=>setSelectedDay(null)}>Visa alla dagar</button>}</div>
    <div className="dashboard-agenda">{agenda.slice(0,limit).map(item=><article key={item.event_id}><span className={`event-marker ${item.event_type}`} /><time dateTime={item.starts_at}><strong>{new Intl.DateTimeFormat("sv-SE",{day:"numeric",month:"short"}).format(new Date(item.starts_at))}</strong><span>{item.all_day?"Hela dagen":new Intl.DateTimeFormat("sv-SE",{hour:"2-digit",minute:"2-digit"}).format(new Date(item.starts_at))}</span></time><div><span className="event-kind">{eventLabels[item.event_type]} · {item.is_own?"Mitt lag":"Följer"}</span><strong>{item.title}</strong><small>{item.team_name}{item.location_name?` · ${item.location_name}`:""}</small></div></article>)}</div>
    {loading && <p role="status">Hämtar kalendern…</p>}{!loading&&!agenda.length&&<p className="empty-note">Inga händelser för de valda filtren.</p>}{agenda.length>limit&&<button className="follow-button" onClick={()=>setLimit(v=>v+12)}>Visa fler händelser</button>}
    <p className="dashboard-caption">Kommande 90 dagar. Möten och aktiviteter visas endast från egna lag där du har behörighet.{truncated?" De första 200 publicerade händelserna visas; fler finns på lagens sidor.":""}</p>
  </section>;
}

function ResultSection({title,eyebrow,items,loading,own=false}:{title:string;eyebrow:string;items:DashboardItem[];loading:boolean;own?:boolean}) {
  const [limit,setLimit]=useState(6);
  return <section className="panel dashboard-panel" id={own?"dashboard-results":undefined}><p className="eyebrow">{eyebrow}</p><h2>{title}</h2><div className="dashboard-results">{items.slice(0,limit).map(item=><article className="dashboard-result" key={item.id}><time dateTime={item.happened_at}>{date(item.happened_at)}</time><h3>{item.title}</h3><div className="dashboard-score"><strong>{item.score_us} <span>–</span> {item.score_opponent}</strong><span>Slutresultat · {item.team_name}</span></div>{own?<Report item={item}/>:<><WrittenMatchReport text={item.report_text}/><Link className="article-link" href={feedHref(item)}>Till laget →</Link></>}</article>)}</div>{!loading&&!items.length&&<p className="empty-note">Inga slutresultat att visa ännu.</p>}{items.length>limit&&<button className="follow-button" onClick={()=>setLimit(v=>v+6)}>Visa fler resultat</button>}</section>;
}

function Report({item}:{item:DashboardItem}) {
  const {client,session}=usePersonalAccount();
  const [report,setReport]=useState<MatchReport|null>(null);
  const [error,setError]=useState(false);
  const [busy,setBusy]=useState(false);
  async function load() {
    if (!client||!session||busy||report) return;
    setBusy(true);setError(false);
    try {const [snapshot,written]=await Promise.all([client.schema("api").rpc("get_match_v2_snapshot",{p_event_id:item.id}),client.schema("api").rpc("get_match_report",{p_event_id:item.id})]);if(snapshot.error||written.error||!snapshot.data||snapshot.data.state!=="completed")throw Error("unavailable");setReport({...snapshot.data,written_report:written.data} as MatchReport);}catch{setError(true);}finally{setBusy(false);}
  }
  const labels:Record<string,string>={goal:"Mål",card:"Kort",substitution:"Byte",half_time:"Halvtid",full_time:"Slut",period_end:"Periodslut",score_adjustment:"Resultat korrigerat",shot:"Mål",penalty:"Straffmål",free_kick:"Frisparksmål",corner:"Mål efter hörna"};
  return <details className="match-report" onToggle={event=>{if(event.currentTarget.open)void load();}}><summary>Visa matchrapport</summary>{busy&&<p>Hämtar rapport…</p>}{error&&<p role="alert">Rapporten är inte tillgänglig eller du saknar behörighet.</p>}{report&&<>{report.written_report?.body&&<><p>{report.written_report.published?"Matchrapport":"Matchrapport · internt utkast"}</p><p style={{whiteSpace:"pre-wrap",overflowWrap:"anywhere"}}>{report.written_report.body}</p></>}<p>Registrerade matchhändelser</p>{reportFacts(report).length?<ol>{reportFacts(report).map(fact=><li key={fact.id}><strong>{fact.minute}′</strong> {labels[fact.fact_type]}{fact.side==="us"?` · ${item.team_name}`:fact.side==="opponent"?" · Motståndare":""}</li>)}</ol>:<p>Inga matchhändelser har registrerats.</p>}</>}</details>;
}
function date(value:string) {return new Intl.DateTimeFormat("sv-SE",{day:"numeric",month:"short"}).format(new Date(value));}
