create or replace function internal.sync_team_public_event(target_event_id uuid)
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
  values(e.club_id,'team',e.owning_team_id,preference.revision,'invalidate',array['/'||club_slug||'/'||team_slug],preference.changed_by)
on conflict(club_id,aggregate_type,aggregate_id,requested_revision,action) do update
set state='pending',affected_paths=excluded.affected_paths,available_at=now(),attempts=0,completed_at=null,last_error_code=null;
 end if;
end;$$;


