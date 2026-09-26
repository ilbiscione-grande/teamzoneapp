import assert from "node:assert/strict";
import test from "node:test";
import { combineCalendar, combineResults, reportFacts, type DashboardEvent, type DashboardItem } from "../lib/dashboard.ts";
import type { OwnTeamEvent } from "../lib/own-team-events.ts";
const now = new Date("2026-09-26T08:00:00Z");
const own: OwnTeamEvent = {event_id:"id",owning_team_id:"team",team_name:"Own",title:"Match",event_type:"match",state:"scheduled",starts_at:"2026-09-27T10:00:00Z",ends_at:"2026-09-27T12:00:00Z",all_day:false,event_cursor:"cursor"};
test("dashboard calendar deduplicates own/public matches and keeps private events in own scope",()=>{
 const published:DashboardEvent={...own,is_own:false};
 const items=combineCalendar([published,{...published,event_id:"other",event_type:"training"},{...published,event_id:"leaked",event_type:"meeting"}],[own,{...own,event_id:"meeting",event_type:"meeting"},{...own,event_id:"activity",event_type:"activity"}],now);
 assert.equal(items.length,4);
 assert.equal(items.find(item=>item.event_id==="id")?.is_own,true);
 assert.equal(items.find(item=>item.event_id==="other")?.is_own,false);
 assert.ok(!items.some(item=>item.event_id==="leaked"));
});
test("calendar excludes old events and includes events still in progress",()=>{
 assert.equal(combineCalendar([], [{...own,starts_at:"2026-09-26T07:00:00Z",ends_at:"2026-09-26T09:00:00Z"}],now).length,1);
 assert.equal(combineCalendar([], [{...own,starts_at:"2026-09-25T07:00:00Z",ends_at:"2026-09-25T09:00:00Z"}],now).length,0);
});
test("own completed results appear without publication; live scores do not",()=>{
 const published:DashboardItem={id:"id",kind:"result",happened_at:own.starts_at,title:"Match",club_name:"Club",club_slug:"club",is_own:true,score_us:1,score_opponent:1};
 const results=combineResults([published],[{...own,match_state:"completed",score_us:0,score_opponent:2},{...own,event_id:"live",match_state:"live",score_us:3,score_opponent:1}]);
 assert.equal(results.length,1);assert.equal(results[0].score_us,0);assert.equal(results[0].score_opponent,2);
});
test("match report excludes voided facts, private injury notes and non-scoring shots",()=>{
 const base={id:"goal",state:"active",fact_type:"goal",minute:10};
 assert.deepEqual(reportFacts({state:"completed",facts:[base,{...base,id:"void",state:"voided"},{...base,id:"injury",fact_type:"injury"},{...base,id:"miss",fact_type:"shot",detail:{result:"missed"}},{...base,id:"score",fact_type:"shot",detail:{result:"scored"}}]}).map(f=>f.id),["goal","score"]);
});
