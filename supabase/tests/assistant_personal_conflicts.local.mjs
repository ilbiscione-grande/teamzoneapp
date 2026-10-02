import fs from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const migration = fs.readFileSync('supabase/migrations/20261002185842_assistant_personal_calendar_conflicts.sql', 'utf8');
const dispositions = fs.readFileSync('supabase/migrations/20261002142418_assistant_task_disposition.sql', 'utf8');
const read = async () => (await db.query('select api.get_personal_calendar_conflicts() value')).rows[0].value.tasks;
try {
 await db.exec(`
 create schema core; create schema internal; create schema api; create schema auth;
 create role anon; create role authenticated;
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
 create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
 create table internal.assistant_task_dispositions(profile_id uuid,kind text,route text,status text,until_at timestamptz,primary key(profile_id,kind,route));
 create table core.person_account_links(profile_id uuid,club_person_id uuid,club_id uuid,state text);
 create table core.callups(id uuid,event_id uuid,club_person_id uuid,club_id uuid,state text);
 create table core.events(id uuid,club_id uuid,owning_team_id uuid,starts_at timestamptz,ends_at timestamptz,state text,archived_at timestamptz,readable boolean default true);
 create table core.event_teams(event_id uuid,club_id uuid,team_id uuid);
 create table auth.contexts(actor uuid,context_id uuid,club_id uuid,team_id uuid,role_package text);
 create function internal.get_my_contexts_for_actor() returns table(context_id uuid,club_id uuid,team_id uuid,role_package text)
 language sql as $$select context_id,club_id,team_id,role_package from auth.contexts where actor=auth.uid()$$;
 create function internal.actor_can_read_event(e uuid) returns boolean language sql as $$select readable from core.events where id=e$$;
 create function internal.get_leader_home_for_actor(c uuid) returns jsonb language sql as $$select '{"tasks":[]}'::jsonb$$;
 select set_config('test.actor','${id(1)}',false);
 insert into auth.contexts values('${id(1)}','${id(11)}','${id(21)}','${id(31)}','player'),
 ('${id(1)}','${id(12)}','${id(22)}','${id(32)}','player'),
 ('${id(1)}','${id(13)}','${id(22)}','${id(32)}','leader'),
 ('${id(2)}','${id(14)}','${id(21)}','${id(31)}','leader'),
 ('${id(2)}','${id(15)}','${id(22)}','${id(32)}','leader');
 insert into core.person_account_links values('${id(1)}','${id(41)}','${id(21)}','active'),('${id(1)}','${id(42)}','${id(22)}','active');
 insert into core.events(id,club_id,owning_team_id,starts_at,ends_at,state) values
 ('${id(51)}','${id(21)}','${id(31)}',now()+interval '1 day',now()+interval '1 day 2 hours','scheduled'),
 ('${id(52)}','${id(22)}','${id(32)}',now()+interval '1 day 1 hour',now()+interval '1 day 3 hours','scheduled');
 insert into core.event_teams select id,club_id,owning_team_id from core.events;
 insert into core.callups values('${id(61)}','${id(51)}','${id(41)}','${id(21)}','accepted'),('${id(62)}','${id(52)}','${id(42)}','${id(22)}','pending');
 `);
 await db.exec(dispositions.slice(dispositions.indexOf('create function internal.set_assistant_task_state_for_actor'), dispositions.indexOf('insert into internal.migration_provenance')));
 await db.exec(migration);
 let tasks = await read();
 assert.equal(tasks.length,1,'deduplicates role contexts and pairs');
 assert.equal(tasks[0].title,'Möjlig personlig krock');
 const route = tasks[0].route;
 await db.query("select api.set_assistant_task_state($1,'personal_calendar_conflict',$2,'archived',null)",[id(11),route]);
 assert.equal((await read())[0].assistant_state.status,'archived');
 await db.query("select api.set_assistant_task_state($1,'personal_calendar_conflict',$2,'snoozed',60)",[id(11),route]);
 assert.equal((await read())[0].assistant_state.status,'snoozed');
 await db.query("select api.set_assistant_task_state($1,'personal_calendar_conflict',$2,'active',null)",[id(11),route]);
 await db.exec("update core.callups set state='accepted'");
 assert.equal((await read())[0].title,'Du är dubbelbokad');
 for (const state of ['declined','cancelled','expired']) {
   await db.query('update core.callups set state=$1 where id=$2',[state,id(62)]);
   assert.equal((await read()).length,0,state);
 }
 await db.exec("update core.callups set state='accepted'");
 await db.query("update core.events set state='cancelled' where id=$1",[id(52)]);
 assert.equal((await read()).length,0);
 await db.query("update core.events set state='scheduled',archived_at=now() where id=$1",[id(52)]);
 assert.equal((await read()).length,0);
 await db.query('update core.events set archived_at=null,readable=false where id=$1',[id(52)]);
 assert.equal((await read()).length,0,'revoked event read');
 await db.query('update core.events set readable=true,starts_at=(select ends_at from core.events where id=$1) where id=$2',[id(51),id(52)]);
 assert.equal((await read()).length,0,'touching boundaries are not overlapping');
 await db.query("update core.events set starts_at=now()+interval '1 day 1 hour' where id=$1",[id(52)]);
 await db.query("update core.person_account_links set state='ended' where club_id=$1",[id(22)]);
 assert.equal((await read()).length,0,'ended own account link');
 await db.exec("update core.person_account_links set state='active'");
 await db.query("update core.events set starts_at=now()+interval '8 days',ends_at=now()+interval '8 days 1 hour' where id=$1",[id(52)]);
 assert.equal((await read()).length,0,'outside the seven-day window');
 await db.query("update core.events set starts_at=now()+interval '1 day 1 hour',ends_at=now()+interval '1 day 3 hours' where id=$1",[id(52)]);
 await db.exec("update auth.contexts set role_package='guardian' where role_package in('player','leader')");
 assert.equal((await read()).length,0,'guardian context does not merge child calendars with own');
 await db.exec("update auth.contexts set role_package='player'");
 await db.query("delete from auth.contexts where club_id=$1 and actor=$2",[id(22),id(1)]);
 assert.equal((await read()).length,0,'revoked context');
 await db.query("select set_config('test.actor',$1,false)",[id(2)]);
 assert.equal((await read()).length,0,'leader access to both clubs does not expose another person');
 await assert.rejects(db.query("select api.set_assistant_task_state($1,'personal_calendar_conflict',$2,'archived',null)",[id(11),route]));
 await db.query("select set_config('test.actor','',false)");
 await assert.rejects(read());
 const acl = (await db.query("select has_function_privilege('anon','api.get_personal_calendar_conflicts()','execute') a,has_function_privilege('authenticated','api.get_personal_calendar_conflicts()','execute') b")).rows[0];
 assert.equal(acl.a,false); assert.equal(acl.b,true);
 console.log('PASS: personal conflicts, response states, context deduplication, dates, permission/account isolation, dispositions and ACL');
} finally { await db.close(); }
