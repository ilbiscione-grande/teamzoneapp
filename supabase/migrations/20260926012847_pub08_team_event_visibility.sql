-- Whole-team opt-in. No existing team is opted in by this migration.
create table core.team_event_visibility (
 team_id uuid primary key references core.teams(id) on delete cascade,
 show_results boolean not null default false,
 show_training boolean not null default false,
 revision bigint not null default 1 check(revision>0),
 changed_by uuid not null references core.profiles(id),
 changed_at timestamptz not null default now()
);
alter table core.team_event_visibility enable row level security;
create policy team_event_visibility_no_direct_access on core.team_event_visibility for all to authenticated using(false) with check(false);
revoke all on core.team_event_visibility from public,anon,authenticated;
create index team_event_visibility_actor_idx on core.team_event_visibility(changed_by);

create function internal.get_team_event_visibility_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare club uuid; result jsonb;
begin
 select club_id into club from core.teams where id=target_team_id;
 if auth.uid() is null or club is null or not (
  internal.actor_has_capability(club,target_team_id,'publication.manage') or
  internal.actor_has_capability(club,target_team_id,'team.roster.manage'))
 then raise insufficient_privilege using message='not_found';end if;
 select jsonb_build_object('show_results',show_results,'show_training',show_training,'revision',revision)
 into result from core.team_event_visibility where team_id=target_team_id;
 return coalesce(result,jsonb_build_object('show_results',false,'show_training',false,'revision',0));
end;$$;

create function internal.sync_team_public_event(target_event_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare e core.events%rowtype; preference core.team_event_visibility%rowtype;
 team_public uuid; club_slug text; team_slug text; completed boolean; score core.match_projections%rowtype;
 manual core.event_publication_settings%rowtype; public_location text;
begin
 select * into e from core.events where id=target_event_id;
 if e.id is null then delete from public_api.event_projections where public_id=target_event_id;return;end if;
 perform pg_advisory_xact_lock(hashtextextended('team-event-visibility:'||e.owning_team_id::text,0));
 select * into preference from core.team_event_visibility where team_id=e.owning_team_id;
 if preference.team_id is null or e.event_type not in('match','training') then return;end if;
 select t.public_id,c.slug,t.slug into team_public,club_slug,team_slug
 from core.team_publication_settings s join public_api.team_projections t on t.public_id=s.public_id
 join public_api.club_projections c on c.public_id=t.club_public_id
 where s.team_id=e.owning_team_id and t.visibility='published' and c.visibility='published';
 select exists(select 1 from core.match_workspaces where event_id=e.id and state='completed') into completed;
 select * into score from core.match_projections where event_id=e.id;
 select * into manual from core.event_publication_settings where event_id=e.id;
 if e.event_type='match' and manual.state='published' and manual.publish_location then
  select name into public_location from core.event_locations where id=e.location_id;
 end if;
 if team_public is not null and e.archived_at is null and e.state in('scheduled','completed') and (
   (e.event_type='training' and preference.show_training) or
   (e.event_type='match' and (manual.state='published' or (preference.show_results and completed and score.event_id is not null)))) then
  insert into public_api.event_projections(public_id,team_public_id,starts_at,event_type,title,location_name,source_revision,projected_at)
  values(e.id,team_public,e.starts_at,e.event_type,
   case when e.event_type='training' then 'Träning' else coalesce(manual.public_title,e.title) end,public_location,preference.revision,now())
  on conflict(public_id) do update set team_public_id=excluded.team_public_id,starts_at=excluded.starts_at,
   event_type=excluded.event_type,title=excluded.title,location_name=excluded.location_name,source_revision=excluded.source_revision,projected_at=excluded.projected_at;
  if e.event_type='match' and preference.show_results and completed and score.event_id is not null then
   insert into public_api.match_result_projections(event_public_id,score_us,score_opponent,source_match_revision)
   values(e.id,score.score_us,score.score_opponent,score.revision)
   on conflict(event_public_id) do update set score_us=excluded.score_us,score_opponent=excluded.score_opponent,source_match_revision=excluded.source_match_revision;
  end if;
 else
  delete from public_api.event_projections where public_id=e.id;
 end if;
 if club_slug is not null then
  insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,requested_revision,action,affected_paths,created_by)
  values(e.club_id,'team',e.owning_team_id,preference.revision,'invalidate',array['/'||club_slug||'/'||team_slug],preference.changed_by);
 end if;
end;$$;

create function internal.set_team_event_visibility_for_actor(target_team_id uuid,new_show_results boolean,new_show_training boolean,expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare current_settings jsonb; e record; club uuid; next_revision bigint;
begin
 -- Serialize preference changes and reject stale clients.
 perform pg_advisory_xact_lock(hashtextextended('team-event-visibility:'||target_team_id::text,0));
 current_settings:=internal.get_team_event_visibility_for_actor(target_team_id);
 if (current_settings->>'revision')::bigint<>expected_revision then raise serialization_failure using message='revision_conflict';end if;
 if new_show_results is null or new_show_training is null then raise invalid_parameter_value using message='invalid_visibility';end if;
 insert into core.team_event_visibility(team_id,show_results,show_training,changed_by)
 values(target_team_id,new_show_results,new_show_training,auth.uid())
 on conflict(team_id) do update set show_results=excluded.show_results,show_training=excluded.show_training,
 revision=core.team_event_visibility.revision+1,changed_by=excluded.changed_by,changed_at=now()
 returning revision into next_revision;
 for e in select id from core.events where owning_team_id=target_team_id and event_type in('training','match') order by id loop
  perform internal.sync_team_public_event(e.id);
 end loop;
 select club_id into club from core.teams where id=target_team_id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(club,auth.uid(),'publication.team.events.configure','team',target_team_id,next_revision,
 jsonb_build_object('show_results',new_show_results,'show_training',new_show_training));
 return internal.get_team_event_visibility_for_actor(target_team_id);
end;$$;

create function internal.sync_team_public_event_trigger() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='events' then
  perform internal.sync_team_public_event(case when tg_op='DELETE' then old.id else new.id end);
 else
  perform internal.sync_team_public_event(case when tg_op='DELETE' then old.event_id else new.event_id end);
 end if;
 return null;
end;$$;
-- Run after the legacy clear-result triggers, so corrections can republish only
-- for teams that have explicitly enabled automatic results.
create trigger z_sync_team_event after insert or update or delete on core.events for each row execute function internal.sync_team_public_event_trigger();
create trigger z_sync_team_score after insert or update or delete on core.match_projections for each row execute function internal.sync_team_public_event_trigger();
create trigger z_sync_team_match after insert or update or delete on core.match_workspaces for each row execute function internal.sync_team_public_event_trigger();

create function internal.sync_team_public_events_on_projection() returns trigger
language plpgsql security definer set search_path='' as $$
declare e record;
begin
 for e in select event.id from core.events event join core.team_publication_settings s on s.team_id=event.owning_team_id
 where s.public_id=new.public_id order by event.id loop perform internal.sync_team_public_event(e.id);end loop;
 return null;
end;$$;
create trigger z_sync_team_events after insert or update on public_api.team_projections for each row execute function internal.sync_team_public_events_on_projection();

-- Keep older event clients from overriding the team-level choice.
alter function internal.configure_event_publication_with_result_for_actor(uuid,text,text,boolean,bigint,uuid,boolean)
 rename to configure_event_publication_with_result_legacy_for_actor;
do $$begin
 execute replace(pg_get_functiondef('internal.configure_event_publication_with_result_legacy_for_actor(uuid,text,text,boolean,bigint,uuid,boolean)'::regprocedure),
  'configure_event_publication_with_result_for_actor.idempotency_key','configure_event_publication_with_result_legacy_for_actor.idempotency_key');
end;$$;
create function internal.configure_event_publication_with_result_for_actor(target_event_id uuid,new_state text,new_public_title text,new_publish_location boolean,expected_revision bigint,idempotency_key uuid,new_publish_result boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 result:=internal.configure_event_publication_with_result_legacy_for_actor(target_event_id,new_state,new_public_title,new_publish_location,expected_revision,idempotency_key,new_publish_result);
 perform internal.sync_team_public_event(target_event_id);
 return result;
end;$$;
-- Rebind the SQL wrapper to the new function after the rename.
create or replace function api.configure_event_publication(event_id uuid,state text,public_title text,publish_location boolean,expected_revision bigint,idempotency_key uuid,publish_result boolean default false)
returns jsonb language sql security invoker set search_path='' as $$select internal.configure_event_publication_with_result_for_actor(event_id,state,public_title,publish_location,expected_revision,idempotency_key,publish_result)$$;
revoke all on function internal.configure_event_publication_with_result_legacy_for_actor(uuid,text,text,boolean,bigint,uuid,boolean) from public,anon,authenticated;
revoke all on function internal.configure_event_publication_with_result_for_actor(uuid,text,text,boolean,bigint,uuid,boolean) from public,anon,authenticated;
grant execute on function internal.configure_event_publication_with_result_for_actor(uuid,text,text,boolean,bigint,uuid,boolean) to authenticated;

create function api.get_team_event_visibility(team_id uuid) returns jsonb language sql security invoker set search_path='' as $$select internal.get_team_event_visibility_for_actor(team_id)$$;
create function api.set_team_event_visibility(team_id uuid,show_results boolean,show_training boolean,expected_revision bigint) returns jsonb language sql security invoker set search_path='' as $$select internal.set_team_event_visibility_for_actor(team_id,show_results,show_training,expected_revision)$$;
revoke all on function internal.get_team_event_visibility_for_actor(uuid),internal.set_team_event_visibility_for_actor(uuid,boolean,boolean,bigint),api.get_team_event_visibility(uuid),api.set_team_event_visibility(uuid,boolean,boolean,bigint),internal.sync_team_public_event(uuid),internal.sync_team_public_event_trigger(),internal.sync_team_public_events_on_projection() from public,anon,authenticated;
grant execute on function internal.get_team_event_visibility_for_actor(uuid),internal.set_team_event_visibility_for_actor(uuid,boolean,boolean,bigint),api.get_team_event_visibility(uuid),api.set_team_event_visibility(uuid,boolean,boolean,bigint) to authenticated;
notify pgrst,'reload schema';
