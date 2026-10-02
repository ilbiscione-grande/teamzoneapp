import assert from 'node:assert/strict';
import fs from 'node:fs';
import {db,club,team,id,as,one} from './profile_contact.local.mjs';
const read = name => fs.readFileSync(`supabase/migrations/${name}`,'utf8');
try {
 await db.exec(`
  create role service_role;
  alter table core.clubs add column status text default 'active';
  alter table core.teams add column status text default 'active',add unique(id,club_id);
  alter table core.club_people add column birth_date date,add unique(id,club_id);
  alter table core.guardian_relations add column starts_at timestamptz default now()-interval '1 day',add column ends_at timestamptz;
  create table internal.notification_outbox(id uuid default gen_random_uuid(),club_id uuid,domain_event_id uuid,event_type text,
   aggregate_type text,aggregate_id uuid,recipient_profile_id uuid,recipient_person_id uuid,payload_ref jsonb,state text,
   created_at timestamptz default now(),unique(domain_event_id,recipient_person_id));
 `);
 const notification = read('20260827160606_msg08_notification_center.sql');
 for (const name of ['notification_title','notification_preview']) {
  const start=notification.indexOf('create function internal.'+name+'(');
  const end=notification.indexOf('$$;',notification.indexOf('as $$',start)+5);
  await db.exec(notification.slice(start,end+3));
 }
 const deep=read('20260924143236_msg08_event_notification_deep_link.sql');
 await db.exec(deep.slice(deep.indexOf('create or replace function'),deep.indexOf('revoke all')));
 for(const file of ['20261002090000_intake_forms.sql','20261002120000_intake_update_existing.sql','20261002120001_intake_contact_approval.sql']) await db.exec(read(file));
 await as(16);
 const form=await one('select api.create_intake_form($1,$2)',[club,team]);
 const submit=async()=>{
  await db.query(`select api.public_submit_intake($1,'Ada','0709999999','approved@example.se','2012-05-03','New street 1','54321','New town',$2)`,[form.token,crypto.randomUUID()]);
  return await one('select id from core.intake_submissions order by created_at desc limit 1');
 };
 const propose=async(person=22)=>{
  await as(16);
  const submission=await submit();
  return await one('select api.process_intake_contact_update($1,$2,$3)',[submission,team,id(person)]);
 };
 const decide=(request,approve=true)=>one('select api.decide_contact_change($1,$2)',[request,approve]);
 await db.exec(`update core.guardian_relations set state='ended' where guardian_person_id='${id(26)}'`);
 const baseline=await one('select internal.profile_contact_snapshot($1)',[id(12)]);
 const proposed=await propose();
 assert.equal(proposed.status,'pending_approval');
 assert.deepEqual(await one('select internal.profile_contact_snapshot($1)',[id(12)]),baseline);
 assert.equal(await one('select count(*)::int from core.intake_submissions'),0);
 await assert.rejects(()=>decide(proposed.request_id),/not_found/);
 assert.deepEqual(await one('select api.list_contact_change_requests()'),[]);
 await as(15);
 await assert.rejects(()=>decide(proposed.request_id),/not_found/);
 assert.deepEqual(await one('select api.list_contact_change_requests()'),[]);
 await as(12);
 assert.equal((await one('select api.list_contact_change_requests()')).length,1);
 await db.exec(`
  insert into core.clubs(id,name) values('${id(90)}','Other club');
  insert into core.teams(id,club_id,name) values('${id(91)}','${id(90)}','Other team');
  insert into core.club_people(id,club_id,display_name) values('${id(32)}','${id(90)}','Ada'),('${id(33)}','${id(90)}','Leader');
  insert into core.person_account_links(club_id,club_person_id,profile_id) values
   ('${id(90)}','${id(32)}','${id(12)}'),('${id(90)}','${id(33)}','${id(11)}');
  insert into core.assignments(club_id,club_person_id,team_id,role_package) values
   ('${club}','${id(22)}','${team}','player'),('${id(90)}','${id(32)}','${id(91)}','player'),('${id(90)}','${id(33)}','${id(91)}','leader');
 `);
 assert.equal(await decide(proposed.request_id),'approved');
 assert.equal(await decide(proposed.request_id),'approved');
 assert.equal(await one('select contact_email from core.profiles where id=$1',[id(12)]),'approved@example.se');
 assert.equal(await one('select contact_email from core.club_people where id=$1',[id(32)]),'approved@example.se');
 assert.equal(await one("select count(*)::int from internal.notification_outbox where event_type='profile.contact.updated.v1' and recipient_profile_id=$1",[id(11)]),2);
 assert.equal(await one("select count(*)::int from internal.notification_outbox where payload_ref::text like '%approved@example.se%'"),0);
 assert.deepEqual(await one('select proposed_contact from core.contact_change_requests where id=$1',[proposed.request_id]),{});
 assert.equal(await one("select has_function_privilege('authenticated','internal.update_person_from_intake_unlinked_for_actor(uuid,uuid,uuid)','execute')"),false);
 assert.equal(await one("select has_function_privilege('anon','api.decide_contact_change(uuid,boolean)','execute')"),false);

 const rejected=await propose(); await as(12);
 assert.equal(await decide(rejected.request_id,false),'rejected');
 assert.equal(await decide(rejected.request_id,true),'rejected');
 const stale=await propose();
 await db.query("update core.profiles set phone='0702222222' where id=$1",[id(12)]);
 await as(12);
 assert.equal((await one('select api.list_contact_change_requests()'))[0].conflict,true);
 await assert.rejects(()=>decide(stale.request_id),/stale_contact/);
 await decide(stale.request_id,false);

 await db.exec(`insert into core.guardian_relations(club_id,guardian_person_id,child_person_id)
  values('${club}','${id(23)}','${id(22)}')`);
 const guardian=await propose(); await as(13);
 assert.equal((await one('select api.list_contact_change_requests()')).length,1);
 assert.equal(await decide(guardian.request_id),'approved');
 const revoked=await propose();
 await db.exec(`update core.guardian_relations set state='ended' where guardian_person_id='${id(23)}'`);
 await as(13); await assert.rejects(()=>decide(revoked.request_id),/not_found/);
 await as(12); await decide(revoked.request_id,false);
 const expired=await propose();
 await db.query("update core.contact_change_requests set expires_at=now()-interval '1 minute' where id=$1",[expired.request_id]);
 await as(12); await assert.rejects(()=>decide(expired.request_id),/request_expired/);
 assert.deepEqual(await one('select api.list_contact_change_requests()'),[]);
 assert.equal((await propose(24)).status,'updated');
 assert.equal(await one('select contact_email from core.club_people where id=$1',[id(24)]),'approved@example.se');
 console.log('PASS contact approval: owner/guardian, rejection, revoked access, expiry, conflicts, all clubs and private notifications');
} finally { await db.close(); }
