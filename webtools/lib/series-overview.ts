import type { Resource } from "./booking.ts";

export type SeriesOverviewPlan = {
 id:string; title?:string; state:string; last_error:string|null;
 configuration:{first_day:string;ends_on:string;start_time:string;end_time:string;end_day_offset:number;frequency:string;interval:number;weekdays:number[];resource_ids?:string[];resources?:{resource_id:string;resource_name:string}[]};
 slots:{state:string}[];
};
export type SeriesStatusFilter = "all" | "active" | "paused" | "attention";
export function seriesNeedsAttention(plan: SeriesOverviewPlan): boolean {
 return !!plan.last_error || plan.slots.some(slot => slot.state === "blocked") || !["active","paused"].includes(plan.state);
}
export function seriesResourceNames(plan: SeriesOverviewPlan, resources: Resource[]): string[] {
 const names=new Map(resources.map(resource=>[resource.id,resource.name]));
 const configured=plan.configuration.resources;
 return configured?.length ? configured.map(resource=>names.get(resource.resource_id) ?? resource.resource_name) : (plan.configuration.resource_ids??[]).map(id=>names.get(id) ?? "Resurs som inte längre visas");
}
export function filterSeriesPlans<T extends SeriesOverviewPlan>(plans:T[],resources:Resource[],query:string,status:SeriesStatusFilter):T[] {
 const words=query.trim().toLocaleLowerCase("sv").split(/\s+/).filter(Boolean);
 return plans.filter(plan=>{
  if(status==="attention"&&!seriesNeedsAttention(plan) || status!=="all"&&status!=="attention"&&plan.state!==status)return false;
  const text=[plan.title,...seriesResourceNames(plan,resources),plan.configuration.first_day,plan.configuration.ends_on].filter(Boolean).join(" ").toLocaleLowerCase("sv");
  return words.every(word=>text.includes(word));
 }).sort((a,b)=>Number(seriesNeedsAttention(b))-Number(seriesNeedsAttention(a)) || a.configuration.ends_on.localeCompare(b.configuration.ends_on) || a.id.localeCompare(b.id));
}
export function seriesSchedule(plan:SeriesOverviewPlan):string {
 const cfg=plan.configuration;
 const words=cfg.frequency==="daily"?["dag","dagars"]:cfg.frequency==="weekly"?["vecka","veckors"]:["månad","månaders"];
 const frequency=["daily","weekly","monthly"].includes(cfg.frequency) ? cfg.interval===1?`Varje ${words[0]}`:cfg.interval===2?`Varannan ${words[0]}`:`Med ${cfg.interval} ${words[1]} mellanrum` : "Annan upprepning";
 const weekdays=cfg.frequency==="weekly"?[...new Set(cfg.weekdays)].sort((a,b)=>a-b).map(day=>["mån","tis","ons","tors","fre","lör","sön"][day-1]).filter(Boolean).join(", "):"";
 return [frequency,weekdays,`${cfg.start_time.slice(0,5)}–${cfg.end_time.slice(0,5)}${cfg.end_day_offset?` (slutar ${cfg.end_day_offset} ${cfg.end_day_offset===1?"dag":"dagar"} senare)`:""}`].filter(Boolean).join(" · ");
}
