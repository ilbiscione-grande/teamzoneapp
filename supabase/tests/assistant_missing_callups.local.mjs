// Real leader projection, event snapshot and V2/V3 edit functions in isolated
// Postgres. Only identity/capability dependencies use controlled fixtures.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const db = new PGlite();
const read = name => fs.readFileSync(`supabase/migrations/${name}`, 'utf8');
const fn = (source, name) => {
  const start = source.search(new RegExp(`create (?:or replace )?function internal\\.${name}\\(`, 'i'));
  assert(start >= 0, name);
  const text = source.slice(start);
  const tag = text.match(/\$(?:function)?\$/)[0];
  return text.slice(0, text.indexOf(`${tag};`, text.indexOf(tag) + tag.length) + tag.length + 1);
};
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const actor = id(1), club = id(2), team = id(3), context = id(4);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
try {
  await db.exec(`
    create schema core; create schema internal; create schema api; create schema auth; create schema audit;
    create role authenticated; create role anon;
    create function auth.uid() returns uuid language sql as $$
      select nullif(current_setting('test.actor',true),'')::uuid $$;
    create table core.profiles(id uuid primary key);
    create table core.clubs(id uuid primary key);
    create table core.teams(id uuid primary key,club_id uuid,unique(id,club_id));
    create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
    create table internal.command_deduplication(actor_profile_id uuid,idempotency_key uuid,command_type text,result jsonb,
      unique(actor_profile_id,idempotency_key,command_type));
    create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,
      aggregate_id uuid,aggregate_revision bigint,metadata jsonb);
    create table auth.test_contexts(context_id uuid,actor_id uuid,club_id uuid,team_id uuid,role_package text,
      can_squad boolean default true,can_manage boolean default true,can_attendance boolean default true,can_logistics boolean default true);
    create function internal.get_my_contexts_for_actor()
      returns table(context_id uuid,club_id uuid,team_id uuid,role_package text) language sql as $$
      select context_id,club_id,team_id,role_package from auth.test_contexts where actor_id=auth.uid() $$;
    create function internal.actor_has_capability(c uuid,t uuid,cap text) returns boolean language sql as $$
      select coalesce(bool_or(case cap when 'event.squad.manage' then can_squad
        when 'event.manage' then can_manage when 'event.logistics' then can_logistics when 'match.live' then can_manage when 'event.attendance.manage' then can_attendance else false end),false)
      from auth.test_contexts where actor_id=auth.uid() and club_id=c and team_id=t $$;
    insert into core.profiles values('${actor}');
    insert into core.clubs values('${club}'),('${id(20)}');
    insert into core.teams values('${team}','${club}'),('${id(30)}','${club}'),('${id(31)}','${id(20)}');
    insert into auth.test_contexts(context_id,actor_id,club_id,team_id,role_package)
      values('${context}','${actor}','${club}','${team}','leader');
    select set_config('test.actor','${actor}',false);
  `);
  const s03 = read('20260807224555_s03_event_calendar.sql');
  await db.exec(s03.slice(0, s03.indexOf('create function internal.event_snapshot')));
  await db.exec(`alter table core.events add column archived_at timestamptz;
    alter table core.event_locations add column pitch text, add column surface text;
    create function internal.actor_can_manage_event(e uuid) returns boolean language sql as $$
      select internal.actor_has_capability(club_id,owning_team_id,'event.manage') from core.events where id=e $$;
    create table core.person_account_links(profile_id uuid,club_person_id uuid,club_id uuid,state text);
    create table core.callups(id uuid default gen_random_uuid(),event_id uuid,club_id uuid,club_person_id uuid,
      state text,revision bigint,expires_at timestamptz,created_at timestamptz default now());
    create table core.attendance_facts(id uuid,event_id uuid,club_person_id uuid);
    create table core.match_workspaces(event_id uuid primary key,state text);
    create table core.match_reports(event_id uuid primary key,body text);
    create table core.event_preparation_items(id uuid default gen_random_uuid(),event_id uuid,club_id uuid,kind text,done boolean default false);
    create function internal.actor_can_read_event(e uuid) returns boolean language sql as $$
      select auth.uid() is not null and e::text is distinct from current_setting('test.hidden_event',true) $$;
    create function internal.actor_has_event_capability(e uuid,cap text) returns boolean language sql as $$
      select internal.actor_has_capability(club_id,owning_team_id,cap) from core.events where id=e $$;
  `);
  const typed = read('20260915104026_cal02_typed_event_fields_and_assembly.sql');
  await db.exec(typed.slice(0, typed.indexOf('create function internal.create_event_v2_for_actor')));
  await db.exec(fn(read('20260827063902_cal02_event_editor_locations.sql'), 'revise_event_v2_for_actor'));
  const places = read('20260930090000_event_place_pitch_surface.sql');
  await db.exec(fn(places, 'resolve_event_place'));
  await db.exec(fn(places, 'revise_event_v3_for_actor'));
  await db.exec(fn(read('20260907170000_cal11e_leader_and_manager_callup_responses.sql'), 'get_leader_home_for_actor'));
  await db.exec(read('20261002121840_assistant_missing_callups.sql'));
  await db.exec(read('20261002132339_assistant_match_followup.sql'));
  await db.exec(read('20261002135847_assistant_conflicts_preparation.sql'));
  await db.exec(read('20261002142418_assistant_task_disposition.sql'));

  const create = async (n, hours, extras = '') => db.exec(`
    insert into core.events(id,club_id,owning_team_id,event_type,title,state,starts_at,ends_at,timezone,created_by,assembly_minutes_before)
    values('${id(n)}','${club}','${team}','training','Event ${n}','scheduled',now()+interval '${hours} hours',
      now()+interval '${hours} hours'+interval '1 hour','Europe/Stockholm','${actor}',15);
    ${extras}
    insert into core.event_teams(club_id,event_id,team_id,relation,capabilities,created_by)
    select club_id,id,owning_team_id,'primary',array['view','co_manage'],'${actor}' from core.events where id='${id(n)}';
  `);
  const tasks = async () => (await one('select internal.get_leader_home_for_actor($1)', [context])).tasks;
  const missing = async () => (await tasks()).filter(t => t.kind === 'missing_callups').map(t => t.route.split('=')[1]).sort();
  await create(100, 24);
  await create(101, 47.99);
  await create(102, 48.01);
  await create(103, -1);
  await create(104, 24, `update core.events set state='cancelled' where id='${id(104)}';`);
  await create(105, 24, `update core.events set state='draft' where id='${id(105)}';`);
  await create(106, 24, `update core.events set archived_at=now() where id='${id(106)}';`);
  await create(107, 24, `update core.events set callups_required=false where id='${id(107)}';`);
  await create(108, 24, `update core.events set owning_team_id='${id(30)}' where id='${id(108)}';`);
  await create(109, 24, `update core.events set club_id='${id(20)}',owning_team_id='${id(31)}' where id='${id(109)}';`);
  await create(110, 24, `update core.events set state='completed' where id='${id(110)}';`);
  assert.deepEqual(await missing(), [id(100), id(101)]);
  // Exact inclusive upper boundary, using the same statement clock for setup
  // and the projection via a DO block (separate statements inside PL/pgSQL).
  await db.exec(`do $$ declare result jsonb; begin
    update core.events set starts_at=statement_timestamp()+interval '48 hours',
      ends_at=statement_timestamp()+interval '49 hours' where id='${id(102)}';
    result:=internal.get_leader_home_for_actor('${context}');
    if not exists(select 1 from jsonb_array_elements(result->'tasks') t
      where t->>'kind'='missing_callups' and t->>'route'='/calendar?event=${id(102)}')
    then raise exception '48 hour boundary missing'; end if;
    update core.events set starts_at=statement_timestamp(),ends_at=statement_timestamp()+interval '1 hour' where id='${id(102)}';
    result:=internal.get_leader_home_for_actor('${context}');
    if exists(select 1 from jsonb_array_elements(result->'tasks') t
      where t->>'kind'='missing_callups' and t->>'route'='/calendar?event=${id(102)}')
    then raise exception 'already started included'; end if;
  end$$;`);
  console.log('PASS: 48-hour boundaries, scheduled state, opt-out, archived and cross-team/club isolation');

  const edit = (value, revision, key) => one(`select internal.revise_event_v3_for_actor($1,'one',$2::jsonb,$3,$4)`,
    [id(100), JSON.stringify({callups_required: value}), revision, key]);
  const key = crypto.randomUUID();
  assert.equal(await edit(false, 1, key), 2);
  assert.deepEqual(await missing(), [id(101)]);
  assert.equal(await one(`select snapshot->'callups_required' from core.event_revisions where event_id=$1 and event_revision=2`, [id(100)]), false);
  assert.equal(await edit(true, 2, crypto.randomUUID()), 3);
  assert.equal(await edit(false, 1, key), 2); // Retry must not undo the later edit.
  assert.equal(await one('select callups_required from core.events where id=$1', [id(100)]), true);
  await assert.rejects(edit(false, 1, crypto.randomUUID()), /stale_revision/);
  await assert.rejects(edit(null, 3, crypto.randomUUID()), /invalid_input/);
  await assert.rejects(edit('false', 3, crypto.randomUUID()), /invalid_input/);
  assert.equal(await one('select count(*)::int from audit.command_events'), 2);
  console.log('PASS: real V3/V2 command, revision, snapshot, audit, retry and input validation');

  await db.exec(`insert into core.callups(event_id,club_id,club_person_id,state,revision,expires_at)
    values('${id(100)}','${club}','${actor}','pending',1,now()+interval '1 day');`);
  assert.deepEqual(await missing(), [id(101)]);
  assert((await tasks()).some(t => t.kind === 'pending_callups'));
  await db.exec(`update core.callups set state='cancelled';`);
  assert.deepEqual(await missing(), [id(101)]); // Issued once, no new reminder.
  await create(200, -24, `update core.events set event_type='match' where id='${id(200)}';`);
  await create(201, -200, `update core.events set event_type='match' where id='${id(201)}';`);
  await create(202, -24, `update core.events set event_type='match',state='cancelled' where id='${id(202)}';`);
  await create(203, -24, `update core.events set event_type='match',archived_at=now() where id='${id(203)}';`);
  await create(204, -24, `update core.events set event_type='match',owning_team_id='${id(30)}' where id='${id(204)}';`);
  await create(205, 24, `update core.events set event_type='match' where id='${id(205)}';`);
  await create(206, -24, `update core.events set event_type='match',club_id='${id(20)}',owning_team_id='${id(31)}' where id='${id(206)}';`);
  const followup = async () => (await tasks()).filter(t => t.kind.startsWith('missing_match'));
  assert.deepEqual((await followup()).map(t => t.route), [`/calendar?event=${id(200)}`]);
  assert.equal((await followup())[0].kind, 'missing_match_result');
  await db.exec(`do $$ declare result jsonb; begin
    update core.events set starts_at=statement_timestamp()-interval '7 days 2 hours',
      ends_at=statement_timestamp()-interval '7 days' where id='${id(200)}';
    result:=internal.get_leader_home_for_actor('${context}');
    if not exists(select 1 from jsonb_array_elements(result->'tasks') t
      where t->>'kind'='missing_match_result' and t->>'route'='/calendar?event=${id(200)}')
    then raise exception 'seven day boundary missing'; end if;
    update core.events set ends_at=statement_timestamp() where id='${id(200)}';
    result:=internal.get_leader_home_for_actor('${context}');
    if exists(select 1 from jsonb_array_elements(result->'tasks') t
      where t->>'kind'='missing_match_result' and t->>'route'='/calendar?event=${id(200)}')
    then raise exception 'not yet ended included'; end if;
    update core.events set starts_at=now()-interval '24 hours',ends_at=now()-interval '23 hours'
      where id='${id(200)}';
  end$$;`);
  await db.exec(`insert into core.match_workspaces values('${id(200)}','live');`);
  assert.equal((await followup())[0].kind, 'missing_match_result');
  await db.exec(`update core.match_workspaces set state='completed';`);
  assert.equal((await followup())[0].kind, 'missing_match_report');
  await db.exec(`insert into core.match_reports values('${id(200)}','   ');`);
  assert.equal((await followup())[0].kind, 'missing_match_report');
  await db.exec(`update core.match_reports set body='Written draft';`);
  assert.deepEqual(await followup(), []);
  await db.exec(`update core.match_reports set body='';`);
  console.log('PASS: match result/report lifecycle, whitespace, draft and scope/time exclusions');
  // Isolate the planning fixtures from the earlier lifecycle fixtures.
  await db.exec('update core.events set archived_at=now()');
  await create(300, 24);
  await create(301, 24.5);
  await create(302, 25); // Touching 300 is not an overlap; 301 still overlaps.
  await create(303, 24);
  await one(`select set_config('test.hidden_event',$1,false)`, [id(303)]);
  await create(304, 24, `update core.events set owning_team_id='${id(30)}' where id='${id(304)}';`);
  await db.exec(`update core.events set starts_at=(select ends_at from core.events where id='${id(300)}'),
    ends_at=(select ends_at+interval '1 hour' from core.events where id='${id(300)}') where id='${id(302)}';
    update core.events set starts_at=(select starts_at from core.events where id='${id(300)}'),
    ends_at=(select ends_at from core.events where id='${id(300)}') where id='${id(304)}';`);
  await create(305, 200);
  await create(306, 200.5);
  await create(307, -24);
  await create(308, -23.5);
  await create(309, 24, `update core.events set state='cancelled' where id='${id(309)}';`);
  const collisions = async () => (await tasks()).filter(t => t.kind === 'calendar_conflict').map(t => t.route).sort();
  const pair = (a,b) => `/calendar?event=${id(a)}&overlap=${id(b)}`;
  assert.deepEqual(await collisions(), [pair(300,301),pair(301,302)]);
  await db.exec(`update core.events set starts_at=now()+interval '30 hours',ends_at=now()+interval '31 hours' where id='${id(301)}';`);
  assert.deepEqual(await collisions(), []);
  await db.exec(`insert into core.event_teams(club_id,event_id,team_id,relation,capabilities,created_by)
    values('${club}','${id(304)}','${team}','shared',array['view'],'${actor}');`);
  assert.deepEqual(await collisions(), [pair(300,304)]);
  await db.exec(`insert into core.event_preparation_items(event_id,club_id,kind,done) values
    ('${id(300)}','${club}','task',false),('${id(300)}','${club}','material',false),
    ('${id(300)}','${club}','task',true),('${id(300)}','${club}','focus',false),
    ('${id(300)}','${club}','agenda',false),('${id(305)}','${club}','task',false),
    ('${id(303)}','${club}','task',false),('${id(304)}','${club}','task',false),
    ('${id(309)}','${club}','task',false);`);
  const preparation = async () => (await tasks()).filter(t => t.kind === 'unfinished_preparation');
  assert.deepEqual((await preparation()).map(t => [t.route,t.count]), [[`/calendar?event=${id(300)}`,2]]);
  await db.exec(`update auth.test_contexts set can_logistics=false;`);
  assert.deepEqual(await preparation(), []);
  assert.deepEqual(await collisions(), [pair(300,304)]);
  await db.exec(`update auth.test_contexts set can_logistics=true;`);
  await db.exec(`update core.event_preparation_items set done=true where event_id='${id(300)}' and kind in('material','task');`);
  assert.deepEqual(await preparation(), []);
  await db.exec(`update core.event_preparation_items set done=false where event_id='${id(300)}' and kind='task';`);
  console.log('PASS: overlap pairs, touching boundaries, hidden/shared events, rescheduling, preparation counts and completion');
  await db.exec(`do $$ declare result jsonb; begin
    update core.events set starts_at=statement_timestamp()+interval '7 days',
      ends_at=statement_timestamp()+interval '7 days 1 hour' where id='${id(305)}';
    update core.events set starts_at=statement_timestamp()+interval '6 days 23 hours 30 minutes',
      ends_at=statement_timestamp()+interval '7 days 30 minutes' where id='${id(306)}';
    result:=internal.get_leader_home_for_actor('${context}');
    if exists(select 1 from jsonb_array_elements(result->'tasks') t
      where t->>'route'='${pair(305,306)}') then raise exception 'seven day upper boundary included'; end if;
    update core.events set starts_at=starts_at-interval '1 second' where id='${id(305)}';
    result:=internal.get_leader_home_for_actor('${context}');
    if not exists(select 1 from jsonb_array_elements(result->'tasks') t
      where t->>'route'='${pair(305,306)}') then raise exception 'inside seven day boundary missing'; end if;
    update core.events set starts_at=statement_timestamp()+interval '48 hours',
      ends_at=statement_timestamp()+interval '49 hours' where id='${id(305)}';
    result:=internal.get_leader_home_for_actor('${context}');
    if not exists(select 1 from jsonb_array_elements(result->'tasks') t
      where t->>'kind'='unfinished_preparation' and t->>'route'='/calendar?event=${id(305)}')
    then raise exception 'preparation 48 hour boundary missing'; end if;
    update core.events set starts_at=starts_at+interval '1 second' where id='${id(305)}';
    result:=internal.get_leader_home_for_actor('${context}');
    if exists(select 1 from jsonb_array_elements(result->'tasks') t
      where t->>'kind'='unfinished_preparation' and t->>'route'='/calendar?event=${id(305)}')
    then raise exception 'preparation beyond 48 hours included'; end if;
  end$$;`);
  console.log('PASS: exact seven-day conflict and 48-hour preparation horizons');
  const route = `/calendar?event=${id(300)}`;
  const setState = (status, minutes=null, targetRoute=route) => db.query(
    `select api.set_assistant_task_state($1,'unfinished_preparation',$2,$3,$4)`, [context,targetRoute,status,minutes]);
  await setState('snoozed',60);
  assert.equal((await preparation())[0].assistant_state.status,'snoozed');
  await db.exec(`update internal.assistant_task_dispositions set until_at=now()-interval '1 minute';`);
  assert.deepEqual((await preparation())[0].assistant_state,{});
  await setState('archived');
  assert.equal((await preparation())[0].assistant_state.status,'archived');
  await db.exec(`insert into core.profiles values('${id(99)}');
    insert into auth.test_contexts(context_id,actor_id,club_id,team_id,role_package)
      values('${context}','${id(99)}','${club}','${team}','leader');`);
  await one(`select set_config('test.actor',$1,false)`,[id(99)]);
  assert.deepEqual((await preparation())[0].assistant_state,{});
  await one(`select set_config('test.actor',$1,false)`,[actor]);
  await assert.rejects(setState('snoozed',0),/invalid_task_state/);
  await assert.rejects(setState('archived',null,'/calendar?event=foreign'),/not_found/);
  await setState('active');
  assert.deepEqual((await preparation())[0].assistant_state,{});
  assert.equal(await one(`select revision::int from core.events where id='${id(300)}'`),1);
  console.log('PASS: private account archive, restore, snooze expiry, invalid input, unknown tasks and unchanged event');
  await db.exec(`update auth.test_contexts set can_squad=false,can_manage=false,can_logistics=false;`);
  await assert.rejects(setState('archived'),/not_found/);
  assert.deepEqual(await collisions(), []);
  assert.deepEqual(await preparation(), []);
  assert.deepEqual(await followup(), []);
  assert.deepEqual(await missing(), []);
  await assert.rejects(edit(false, 3, crypto.randomUUID()), /not_found/);
  await one(`select set_config('test.actor',$1,false)`, [id(999)]);
  await assert.rejects(tasks(), /not_found/);
  await one(`select set_config('test.actor','',false)`);
  await assert.rejects(tasks(), /unauthenticated/);
  console.log('PASS: issued/cancelled callups, capability denial, outsider and unauthenticated');
} finally { await db.close(); }
