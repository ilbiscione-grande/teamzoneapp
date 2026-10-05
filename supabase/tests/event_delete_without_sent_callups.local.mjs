// Real event tables and the real delete rule/command in isolated Postgres.
// Only identity/capability and dependent history tables are fixtures.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const db = new PGlite();
const read = name => fs.readFileSync(`supabase/migrations/${name}`, 'utf8');
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const actor = id(1), club = id(2), team = id(3), other = id(30);
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
    insert into core.profiles values('${actor}');
    insert into core.clubs values('${club}');
    insert into core.teams values('${team}','${club}'),('${other}','${club}');
    select set_config('test.actor','${actor}',false);
  `);
  const s03 = read('20260807224555_s03_event_calendar.sql');
  await db.exec(s03.slice(0, s03.indexOf('create function internal.event_snapshot')));
  await db.exec(`alter table core.events add column archived_at timestamptz;
    create function internal.actor_can_manage_event_sharing(e uuid) returns boolean language sql as $$
      select current_setting('test.can_manage',true) is distinct from 'off' $$;
    create table core.squad_revisions(id uuid primary key default gen_random_uuid(),event_id uuid,club_id uuid,state text,
      unique(id,club_id),foreign key(event_id,club_id) references core.events(id,club_id) on delete cascade);
    create table core.callups(id uuid default gen_random_uuid(),event_id uuid,club_id uuid,squad_revision_id uuid,
      state text,sent_at timestamptz,foreign key(event_id,club_id) references core.events(id,club_id) on delete cascade,
      foreign key(squad_revision_id,club_id) references core.squad_revisions(id,club_id));
    create table core.attendance_facts(event_id uuid,club_id uuid,
      foreign key(event_id,club_id) references core.events(id,club_id) on delete cascade);
    create table core.match_workspaces(event_id uuid primary key);
    create table core.sponsor_pledges(event_id uuid,club_id uuid,
      foreign key(event_id,club_id) references core.events(id,club_id));
    create table core.event_publication_settings(event_id uuid primary key,club_id uuid,team_id uuid,state text,
      foreign key(event_id,club_id,team_id) references core.events(id,club_id,owning_team_id));
  `);
  await db.exec(read('20261005090000_event_delete_without_sent_callups.sql').replace(/notify pgrst[^;]*;/, ''));

  const create = async (n, state = 'scheduled', extras = '') => db.exec(`
    insert into core.events(id,club_id,owning_team_id,event_type,title,state,starts_at,ends_at,timezone,created_by)
    values('${id(n)}','${club}','${team}','training','Event ${n}','${state}',now()+interval '1 day',
      now()+interval '25 hours','Europe/Stockholm','${actor}');
    insert into core.event_teams(club_id,event_id,team_id,relation,capabilities,created_by)
    values('${club}','${id(n)}','${team}','primary',array['view','co_manage'],'${actor}');
    ${extras}`);
  const can = n => one('select internal.event_can_be_deleted_by_manager($1)', [id(n)]);
  const del = (n, revision = 1, key = crypto.randomUUID()) =>
    one('select internal.delete_event_draft_for_actor($1,$2,$3)', [id(n), revision, key]);
  const exists = n => one('select count(*)::int from core.events where id=$1', [id(n)]);

  await create(100, 'draft');
  await create(101, 'scheduled', `
    update core.events set revision=4 where id='${id(101)}';
    insert into core.squad_revisions(id,event_id,club_id,state) values('${id(900)}','${id(101)}','${club}','draft');
    insert into core.callups(event_id,club_id,squad_revision_id,state) values('${id(101)}','${club}','${id(900)}','draft');
    insert into core.event_publication_settings values('${id(101)}','${club}','${team}','private');`);
  await create(102, 'cancelled');
  assert.equal(await can(100), true);
  assert.equal(await can(101), true, 'revised, scheduled event with an unsent squad draft');
  assert.equal(await can(102), true);
  console.log('PASS: draft, scheduled and cancelled events without sent callups are deletable');

  await create(110, 'scheduled', `
    insert into core.callups(event_id,club_id,state,sent_at) values('${id(110)}','${club}','pending',now());`);
  await create(111, 'cancelled', `
    insert into core.callups(event_id,club_id,state,sent_at) values('${id(111)}','${club}','cancelled',now());`);
  await create(112, 'scheduled', `
    insert into core.squad_revisions(event_id,club_id,state) values('${id(112)}','${club}','sent');`);
  await create(113, 'scheduled', `insert into core.attendance_facts values('${id(113)}','${club}');`);
  await create(114, 'scheduled', `insert into core.match_workspaces values('${id(114)}');`);
  await create(115, 'scheduled', `insert into core.sponsor_pledges values('${id(115)}','${club}');`);
  await create(116, 'scheduled', `
    insert into core.event_publication_settings values('${id(116)}','${club}','${team}','published');`);
  await create(117, 'scheduled', `
    insert into core.event_teams(club_id,event_id,team_id,relation,capabilities,created_by)
    values('${club}','${id(117)}','${other}','shared',array['view'],'${actor}');`);
  await create(118, 'completed');
  await create(119, 'scheduled', `update core.events set archived_at=now() where id='${id(119)}';`);
  for (const n of [110, 111, 112, 113, 114, 115, 116, 117, 118, 119]) {
    assert.equal(await can(n), false, `event ${n} must be archived, not deleted`);
  }
  await one(`select set_config('test.can_manage','off',false)`);
  assert.equal(await can(100), false, 'requires the sharing/manage capability');
  await one(`select set_config('test.can_manage','on',false)`);
  console.log('PASS: sent callups, sent squad, attendance, match, pledge, publication, sharing, completed, archived and capability block deletion');

  await assert.rejects(del(110, 1), /not_found/);
  await assert.rejects(del(101, 1), /stale_revision/);
  const key = crypto.randomUUID();
  const result = await del(101, 4, key);
  assert.deepEqual(result, { event_id: id(101), deleted: true });
  assert.equal(await exists(101), 0);
  assert.equal(await one('select count(*)::int from core.callups where event_id=$1', [id(101)]), 0);
  assert.equal(await one('select count(*)::int from core.squad_revisions where event_id=$1', [id(101)]), 0);
  assert.equal(await one('select count(*)::int from core.event_publication_settings where event_id=$1', [id(101)]), 0);
  assert.deepEqual(await del(101, 4, key), result, 'idempotent retry');
  assert.equal(await one(`select count(*)::int from audit.command_events where aggregate_id=$1`, [id(101)]), 1);
  assert.equal(await one(`select metadata->>'title' from audit.command_events where aggregate_id=$1`, [id(101)]), 'Event 101');
  assert.equal(await (await del(100)).deleted, true);
  assert.equal(await exists(100), 0);
  assert.equal(await exists(110), 1);
  console.log('PASS: delete command removes event and unsent dependants, is revision-checked, audited and idempotent');
} finally {
  await db.close();
}
