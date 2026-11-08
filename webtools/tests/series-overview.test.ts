import test from "node:test";
import assert from "node:assert/strict";
import { filterSeriesPlans,seriesNeedsAttention,seriesResourceNames,seriesSchedule,type SeriesOverviewPlan } from "../lib/series-overview.ts";
import type { Resource } from "../lib/booking.ts";
const plan=(id:string,extra:Partial<SeriesOverviewPlan>={}):SeriesOverviewPlan=>({id,title:id,state:"active",last_error:null,configuration:{first_day:"2026-11-05",ends_on:"2027-05-01",start_time:"18:00:00",end_time:"19:30:00",end_day_offset:0,frequency:"weekly",interval:2,weekdays:[4,1],resource_ids:["r"]},slots:[],...extra});
const resources=[{id:"r",name:"Stora planen"} as Resource];
test("blocked slots, errors and unfamiliar states need attention without mislabelling paused plans",()=>{
 assert.equal(seriesNeedsAttention(plan("paused",{state:"paused"})),false);
 for(const p of [plan("blocked",{slots:[{state:"blocked"}]}),plan("error",{last_error:"resource_busy"}),plan("unknown",{state:"unknown"})])assert.equal(seriesNeedsAttention(p),true);
 assert.deepEqual(filterSeriesPlans([plan("active"),plan("blocked",{slots:[{state:"blocked"}]}),plan("paused",{state:"paused"})],resources,"","attention").map(p=>p.id),["blocked"]);
});
test("resource and title search preserve the entire plan and prioritize attention without modifying source data",()=>{
 const ordinary=plan("Träning"),blocked=plan("Träning med hinder",{slots:[{state:"blocked"}]});const rows=[ordinary,blocked];
 const result=filterSeriesPlans(rows,resources,"  TRÄNING stora ","all");
 assert.equal(result[0],blocked);assert.equal(result[1],ordinary);assert.equal(rows[0],ordinary);
 assert.deepEqual(filterSeriesPlans(rows,resources,"finns inte","all"),[]);
 assert.deepEqual(filterSeriesPlans(rows,resources,"","paused"),[]);
});
test("resource names use current authorized names, retain historical names and avoid exposing ids",()=>{
 const p=plan("a");p.configuration.resources=[{resource_id:"r",resource_name:"Gammalt namn"},{resource_id:"old",resource_name:"Tidigare resurs"}];
 assert.deepEqual(seriesResourceNames(p,resources),["Stora planen","Tidigare resurs"]);
 assert.deepEqual(seriesResourceNames(plan("missing"),[]),["Resurs som inte längre visas"]);
});
test("recurrence summary uses readable intervals and weekdays without changing configuration",()=>{
 const p=plan("a");assert.equal(seriesSchedule(p),"Varannan vecka · mån, tors · 18:00–19:30");assert.deepEqual(p.configuration.weekdays,[4,1]);
 p.configuration={...p.configuration,frequency:"daily",interval:3,end_day_offset:1};assert.equal(seriesSchedule(p),"Med 3 dagars mellanrum · 18:00–19:30 (slutar 1 dag senare)");
});
