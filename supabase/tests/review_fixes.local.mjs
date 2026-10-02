// Regression checks using real profile, detail-save and publication functions.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { db, club, team, id, as, one } from './profile_contact.local.mjs';
const read = name => fs.readFileSync(`supabase/migrations/${name}`, 'utf8');
const functionSql = (source, name) => {
  const start = source.search(new RegExp(`create(?: or replace)? function internal\\.${name}\\(`));
  assert(start >= 0, name);
  const end = source.indexOf('$$;', source.indexOf('as $$', start) + 5);
  return source.slice(start, end + 3);
};
try {
  await db.exec(`
    create schema public_api;
    alter table core.team_person_details add column positions text[] default '{}',
      add column custom_positions text[] default '{}',add column main_position text,add column main_title text,
      add column revision bigint default 0,add column updated_by uuid,add column updated_at timestamptz,
      add unique(team_id,club_person_id);
    create function internal.assert_team_role_manager(c uuid,t uuid) returns void language plpgsql as $$begin
      if not internal.actor_has_capability(c,t,'club.memberships.manage') then raise insufficient_privilege;end if;
    end$$;
    create table core.events(id uuid primary key,club_id uuid,owning_team_id uuid,event_type text,
      state text,starts_at timestamptz,archived_at timestamptz,title text,location_id uuid);
    create table core.event_publication_settings(event_id uuid primary key,club_id uuid,team_id uuid,
      state text,public_title text,publish_location boolean,changed_by uuid,changed_at timestamptz,revision bigint default 1);
    create table core.team_event_visibility(team_id uuid primary key,show_results boolean,show_training boolean,
      show_matches boolean,revision bigint,changed_by uuid);
    create table core.match_workspaces(event_id uuid,state text);
    create table core.match_projections(event_id uuid,score_us int,score_opponent int,revision bigint);
    create table core.event_locations(id uuid,name text);
    create table core.team_publication_settings(team_id uuid,public_id uuid,slug text,mode text,confirmation_id uuid);
    create table core.club_publication_settings(club_id uuid,slug text);
    create table public_api.team_projections(public_id uuid,club_public_id uuid,slug text,visibility text);
    create table public_api.club_projections(public_id uuid,slug text,visibility text);
    create table public_api.event_projections(public_id uuid primary key,team_public_id uuid,starts_at timestamptz,
      event_type text,title text,location_name text,source_revision bigint,projected_at timestamptz);
    create table public_api.match_result_projections(event_public_id uuid primary key references public_api.event_projections(public_id) on delete cascade,
      score_us int,score_opponent int,source_match_revision bigint,published_at timestamptz);
    create table internal.publication_projection_jobs(club_id uuid,aggregate_type text,aggregate_id uuid,requested_revision bigint,
      action text,affected_paths text[],created_by uuid,state text,available_at timestamptz,attempts int,
      completed_at timestamptz,last_error_code text,unique(club_id,aggregate_type,aggregate_id,requested_revision,action));
    create function internal.get_publication_management_for_actor(c uuid) returns jsonb language sql as $$
      select jsonb_build_object('publication_state',coalesce(setting.state,'private'))
      from core.events event_row left join core.event_publication_settings setting on setting.event_id=event_row.id limit 1
    $$;
  `);
  const titles = read('20260929140000_team_titles_positions_by_sport.sql');
  await db.exec(functionSql(titles, 'normalize_labels'));
  await db.exec(functionSql(titles, 'save_team_person_details'));
  const resultMigration = read('20260925203446_pub07_explicit_public_match_results.sql');
  await db.exec(functionSql(resultMigration, 'clear_public_match_result'));
  await db.exec(`create trigger clear_result_on_event_projection_update after update on public_api.event_projections
    for each row execute function internal.clear_public_match_result();`);
  await db.exec(functionSql(resultMigration, 'configure_event_publication_with_result_for_actor')
    .replaceAll('configure_event_publication_with_result_for_actor', 'configure_event_publication_with_result_legacy_for_actor'));
  await db.exec(read('20261002084222_review_fixes_team_publication_and_profile.sql'));

  // A retry of an earlier command must not mutate newer main choices or revisions.
  await as(16);
  await db.exec(`insert into core.assignments(club_id,club_person_id,team_id,role_package)
    values('${club}','${id(21)}','${team}','player');`);
  const save = (title, position, rev, key) => one(`select internal.set_team_person_details_v4_for_actor(
    $1,$2,$3,array['head_coach','team_manager'],array['striker','central_midfielder'],'{}','{}',$4,$5,$6,$7)`,
    [club,team,id(21),title,position,rev,key]);
  const firstKey = crypto.randomUUID();
  assert.equal(await save('head_coach','striker',0,firstKey),1);
  assert.equal(await save('team_manager','central_midfielder',1,crypto.randomUUID()),2);
  assert.equal(await save('head_coach','striker',0,firstKey),1);
  const details = (await db.query('select main_title,main_position,revision from core.team_person_details where club_person_id=$1',[id(21)])).rows[0];
  assert.deepEqual(details,{main_title:'team_manager',main_position:'central_midfielder',revision:2});
  await assert.rejects(() => save('head_coach','striker',0,crypto.randomUUID()),/stale_revision/);
  await as(15);
  await assert.rejects(() => save('head_coach','striker',2,crypto.randomUUID()));

  // Invalid address rolls back the entire profile; same revision remains usable.
  await as(12);
  const initial = await one('select api.get_my_profile_details()');
  const profileSave = (name, postal, revision, key) => one(`select api.update_my_profile_details_v2(
    $1,'new@example.se','0701111111','keep',null,'Street 1',$2,'Town',$3,$4)`,[name,postal,revision,key]);
  const profileKey = crypto.randomUUID();
  await assert.rejects(() => profileSave('New name','!',initial.revision,profileKey),/invalid_address/);
  assert.deepEqual(await one('select api.get_my_profile_details()'),initial);
  const revision = await profileSave('New name','12345',initial.revision,profileKey);
  assert.equal(revision,initial.revision+1);
  assert.equal((await one('select api.get_my_profile_details()')).postal_code,'12345');
  await profileSave('Newest name','54321',revision,crypto.randomUUID());
  await profileSave('New name','12345',initial.revision,profileKey);
  const newest = await one('select api.get_my_profile_details()');
  assert.equal(newest.display_name,'Newest name');
  assert.equal(newest.postal_code,'54321');
  assert.equal(await one(`select has_function_privilege('anon','api.update_my_profile_details_v2(text,text,text,text,uuid,text,text,text,bigint,uuid)','execute')`),false);

  // Team policy wins over both private and published legacy per-match choices.
  await db.exec(`
    insert into core.events values('${id(81)}','${club}','${team}','match','completed',now(),null,'Match',null);
    insert into core.event_publication_settings(event_id,state) values('${id(81)}','private');
    insert into core.team_event_visibility values('${team}',false,false,true,1,'${id(16)}');
    insert into core.match_workspaces values('${id(81)}','completed');
    insert into core.match_projections values('${id(81)}',3,1,1);
    insert into core.team_publication_settings values('${team}','${id(70)}','laget','published','${id(73)}');
    insert into core.club_publication_settings values('${club}','klubben');
    insert into public_api.team_projections values('${id(70)}','${id(71)}','laget','published');
    insert into public_api.club_projections values('${id(71)}','klubben','published');
  `);
  const sync = () => db.query('select internal.sync_team_public_event($1)',[id(81)]);
  await sync();
  assert.equal(await one('select count(*)::int from public_api.event_projections'),1);
  assert.equal(await one('select count(*)::int from public_api.match_result_projections'),0);
  await db.exec('update core.team_event_visibility set show_results=true'); await sync();
  assert.equal(await one('select count(*)::int from public_api.match_result_projections'),1);
  await db.exec('update core.team_event_visibility set show_results=false'); await sync();
  assert.equal(await one('select count(*)::int from public_api.match_result_projections'),0);
  await db.exec("update core.event_publication_settings set state='published'; update core.team_event_visibility set show_matches=false"); await sync();
  assert.equal(await one('select count(*)::int from public_api.event_projections'),0);
  await db.exec('delete from core.team_event_visibility'); await sync();
  assert.equal(await one('select count(*)::int from public_api.event_projections'),0);
  console.log('PASS review fixes: repeat safety, atomic profile, team-wide match visibility and score removal');
} finally { await db.close(); }
