// Min assistent feedback and support switches: the real migration in isolated
// Postgres, with the leader home base, personal conflicts and the task state
// command stubbed (their rules are tested with their own migrations).
// node supabase/tests/assistant_feedback_switches.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const leader = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', support = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const context = 'c0000000-0000-4000-8000-000000000001';
const route = '/calendar/event/30000000-0000-4000-8000-000000000001?tab=participants';
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
try {
  await db.exec(`create role anon;create role authenticated;
  create schema internal;create schema api;create schema core;create schema auth;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table core.profiles(id uuid primary key);
  insert into core.profiles values('${leader}'),('${support}');
  create table core.person_account_links(profile_id uuid,club_id uuid,club_person_id uuid,state text);
  create table core.events(id uuid,club_id uuid,title text,event_type text,state text,starts_at timestamptz,ends_at timestamptz,
   timezone text,archived_at timestamptz,location_id uuid);
  create table core.event_teams(event_id uuid,club_id uuid,team_id uuid);
  create table core.event_locations(id uuid,club_id uuid,name text,pitch text,address text);
  create function internal.get_my_contexts_for_actor() returns table(context_id uuid,club_id uuid,team_id uuid)
   language sql as $$select '${context}'::uuid,null::uuid,null::uuid$$;
  create function internal.home_my_callup(uuid,uuid,timestamptz) returns jsonb language sql as $$select null::jsonb$$;
  create function internal.event_place_label(text,text) returns text language sql as $$select $1$$;
  -- Stub: two tasks on the leader's home.
  create function internal.get_leader_home_base_for_actor(target uuid) returns jsonb language sql stable as $$
   select jsonb_build_object('tasks',jsonb_build_array(
     jsonb_build_object('kind','pending_callups','route','${route}','count',2),
     jsonb_build_object('kind','missing_attendance','route','${route}','count',1)),
    'today_events','[]'::jsonb)$$;
  create function internal.get_personal_calendar_conflicts_for_actor() returns jsonb language sql stable as $$
   select jsonb_build_object('tasks',jsonb_build_array(jsonb_build_object('kind','personal_calendar_conflict')))$$;
  create function api.get_personal_calendar_conflicts() returns jsonb language sql as $$select '{}'::jsonb$$;
  -- Stub of Skjut upp/Arkivera: validates against the (filtered) home.
  create table public.dispositions(profile uuid,kind text,route text,status text);
  create function internal.set_assistant_task_state_for_actor(context_id uuid,task_kind text,task_route text,new_status text,snooze_minutes integer default null)
  returns void language plpgsql security definer set search_path='' as $$
  begin
   if not exists(select 1 from jsonb_array_elements(internal.get_leader_home_for_actor(context_id)->'tasks') t
     where t->>'kind'=task_kind and t->>'route'=task_route) then raise insufficient_privilege using message='not_found'; end if;
   insert into public.dispositions values(auth.uid(),task_kind,task_route,new_status);
  end$$;
  create table internal.support_admins(profile_id uuid,active boolean);
  insert into internal.support_admins values('${support}',true);
  create function internal.actor_is_support_admin() returns boolean language sql stable security definer set search_path='' as $$
   select exists(select 1 from internal.support_admins where profile_id=auth.uid() and active)$$;
  grant usage on schema api, internal, core to authenticated;`);
  await db.exec(read('supabase/migrations/20261030090000_assistant_feedback_and_switches.sql').replace(/notify pgrst[^;]*;/, ''));
  await db.exec('begin');
  const kinds = async () => (await one('select internal.get_leader_home_for_actor($1)', [context])).tasks.map(t => t.kind);

  // 1. All task types are on to begin with.
  await as(leader);
  assert.deepEqual(await kinds(), ['pending_callups', 'missing_attendance']);

  // 2. Only support can switch a type off; a reason is required.
  await db.exec('set role authenticated');
  await reject(() => db.query('select api.set_assistant_task_kind_switch($1,true,$2)', ['missing_attendance', 'Visar fel']), /not_found/);
  await reject(() => db.query('select api.list_assistant_task_kinds_for_support()'), /not_found/);
  await db.exec('reset role');
  await as(support);
  await db.exec('set role authenticated');
  await reject(() => db.query('select api.set_assistant_task_kind_switch($1,true,$2)', ['missing_attendance', 'x']), /invalid_switch/);
  await reject(() => db.query('select api.set_assistant_task_kind_switch($1,true,$2)', ['watchpoints', 'Visar fel']), /invalid_switch/);
  await db.query('select api.set_assistant_task_kind_switch($1,true,$2)', ['missing_attendance', 'Regeln visar fel efter sommaruppehållet']);
  await db.query('select api.set_assistant_task_kind_switch($1,true,$2)', ['personal_calendar_conflict', 'Testar avstängning']);
  await db.exec('reset role');

  // 3. Switched-off types disappear for everyone, including personal conflicts.
  await as(leader);
  assert.deepEqual(await kinds(), ['pending_callups']);
  assert.deepEqual((await one('select api.get_personal_calendar_conflicts()')).tasks, []);
  // A disabled type cannot be snoozed or given feedback.
  await reject(() => db.query('select api.give_assistant_task_feedback($1,$2,$3,$4)', [context, 'missing_attendance', route, 'incorrect']), /not_found/);

  // 4. Switching on again brings them back; the history keeps both changes.
  await as(support);
  await db.query('select api.set_assistant_task_kind_switch($1,false,$2)', ['missing_attendance', 'Regeln rättad']);
  await as(leader);
  assert.deepEqual(await kinds(), ['pending_callups', 'missing_attendance']);
  assert.equal(await one("select count(*)::int from internal.assistant_task_kind_switch_history where kind='missing_attendance'"), 2);

  // 5. Feedback archives the card and is stored with a fixed reason only.
  await db.exec('set role authenticated');
  await reject(() => db.query('select api.give_assistant_task_feedback($1,$2,$3,$4)', [context, 'pending_callups', route, 'boring']), /invalid_feedback/);
  const first = await one('select api.give_assistant_task_feedback($1,$2,$3,$4)', [context, 'pending_callups', route, 'incorrect']);
  await db.exec('reset role');
  assert.deepEqual(first, { archived: true, offer_hide: false });
  assert.deepEqual((await db.query('select status from public.dispositions')).rows, [{ status: 'archived' }]);

  // 6. "Visas för ofta" a third time within 30 days offers to hide the type.
  for (const expected of [false, false, true]) {
    await db.exec('set role authenticated');
    const result = await one('select api.give_assistant_task_feedback($1,$2,$3,$4)', [context, 'pending_callups', route, 'too_often']);
    await db.exec('reset role');
    assert.equal(result.offer_hide, expected);
  }
  await db.query("update internal.assistant_task_feedback set created_at=now()-interval '31 days' where reason='too_often'");
  await db.exec('set role authenticated');
  assert.equal((await one('select api.give_assistant_task_feedback($1,$2,$3,$4)', [context, 'pending_callups', route, 'too_often'])).offer_hide, false,
    'older feedback does not count');
  await db.exec('reset role');

  // 7. Support sees counts per type and reason, never who.
  await as(support);
  await db.exec('set role authenticated');
  const list = await one('select api.list_assistant_task_kinds_for_support()');
  await db.exec('reset role');
  assert.equal(list.length, 8);
  const pending = list.find(row => row.kind === 'pending_callups');
  assert.deepEqual(pending.feedback, { incorrect: 1, too_often: 1 });
  assert.equal(pending.feedback_people, 1);
  assert.equal(list.find(row => row.kind === 'personal_calendar_conflict').disabled, true);
  assert.ok(!JSON.stringify(list).includes(leader), 'no profile ids reach support');

  // 8. Tables are not readable by users; anon cannot call anything.
  for (const table of ['assistant_task_feedback', 'assistant_task_kind_switches', 'assistant_task_kind_switch_history']) {
    assert.equal(await one('select has_table_privilege($1,$2,$3)', ['authenticated', `internal.${table}`, 'select']), false, table);
  }
  for (const fn of ['api.give_assistant_task_feedback(uuid,text,text,text)', 'api.set_assistant_task_kind_switch(text,boolean,text)',
    'api.list_assistant_task_kinds_for_support()']) {
    assert.equal(await one('select has_function_privilege($1,$2,$3)', ['anon', fn, 'execute']), false, fn);
  }
  await db.exec('rollback');
  console.log('assistant feedback and switches: ok');
} finally {
  await db.close();
}
