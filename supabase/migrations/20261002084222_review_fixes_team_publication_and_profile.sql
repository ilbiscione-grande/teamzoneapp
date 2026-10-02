-- Review fixes: team-wide match publication, replay-safe details, atomic own profile.

create or replace function internal.set_team_person_details_v3_for_actor(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_titles text[],new_positions text[],new_custom_titles text[],new_custom_positions text[],
 new_main_position text,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare main text:=nullif(btrim(new_main_position),''); saved_revision bigint; cached jsonb;
begin
 perform internal.assert_team_role_manager(target_club_id,target_team_id);
 perform pg_advisory_xact_lock(hashtextextended('team-person-details:'||target_team_id::text||':'||target_person_id::text,0));
 select d.result into cached from internal.command_deduplication d
 where d.actor_profile_id=auth.uid() and d.command_type='team.person_details.updated.v2'
  and d.idempotency_key=set_team_person_details_v3_for_actor.idempotency_key;
 if cached is not null then return (cached->>'revision')::bigint; end if;
 if main is not null and not (main=any(internal.normalize_labels(new_positions))
  or main=any(internal.normalize_labels(new_custom_positions))) then
  raise invalid_parameter_value using message='invalid_main_position'; end if;
 saved_revision:=internal.save_team_person_details(target_club_id,target_team_id,target_person_id,
  new_titles,new_positions,new_custom_titles,new_custom_positions,expected_revision,idempotency_key,
  'team.person_details.updated.v2');
 update core.team_person_details set main_position=main
 where team_id=target_team_id and club_person_id=target_person_id and main_position is distinct from main;
 return saved_revision;
end$$;


create or replace function internal.set_team_person_details_v4_for_actor(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_titles text[],new_positions text[],new_custom_titles text[],new_custom_positions text[],
 new_main_title text,new_main_position text,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare title text:=nullif(btrim(new_main_title),''); saved_revision bigint; cached jsonb;
begin
 perform internal.assert_team_role_manager(target_club_id,target_team_id);
 perform pg_advisory_xact_lock(hashtextextended('team-person-details:'||target_team_id::text||':'||target_person_id::text,0));
 select d.result into cached from internal.command_deduplication d
 where d.actor_profile_id=auth.uid() and d.command_type='team.person_details.updated.v2'
  and d.idempotency_key=set_team_person_details_v4_for_actor.idempotency_key;
 if cached is not null then return (cached->>'revision')::bigint; end if;
 if title is not null and not (title=any(internal.normalize_labels(new_titles))
  or title=any(internal.normalize_labels(new_custom_titles))) then
  raise invalid_parameter_value using message='invalid_main_title'; end if;
 saved_revision:=internal.set_team_person_details_v3_for_actor(target_club_id,target_team_id,target_person_id,
  new_titles,new_positions,new_custom_titles,new_custom_positions,new_main_position,expected_revision,idempotency_key);
 update core.team_person_details set main_title=title
 where team_id=target_team_id and club_person_id=target_person_id and main_title is distinct from title;
 return saved_revision;
end$$;


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
 if e.event_type not in('match','training') then return;end if;
 select t.public_id,c.slug,t.slug into team_public,club_slug,team_slug
 from core.team_publication_settings s join public_api.team_projections t on t.public_id=s.public_id
 join public_api.club_projections c on c.public_id=t.club_public_id
 where s.team_id=e.owning_team_id and t.visibility='published' and c.visibility='published';
 select exists(select 1 from core.match_workspaces where event_id=e.id and state='completed') into completed;
 select * into score from core.match_projections where event_id=e.id;
 select * into manual from core.event_publication_settings where event_id=e.id;
 if e.event_type='match' and manual.publish_location then
  select name into public_location from core.event_locations where id=e.location_id;
 end if;
 if team_public is not null and e.archived_at is null and e.state in('scheduled','completed') and (
   (e.event_type='training' and preference.show_training) or
   (e.event_type='match' and (coalesce(preference.show_matches,false) or (preference.show_results and completed and score.event_id is not null)))) then
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
 if club_slug is not null and preference.team_id is not null then
  insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,requested_revision,action,affected_paths,created_by)
  values(e.club_id,'team',e.owning_team_id,preference.revision,'invalidate',array['/'||club_slug||'/'||team_slug],preference.changed_by)
on conflict(club_id,aggregate_type,aggregate_id,requested_revision,action) do update
set state='pending',affected_paths=excluded.affected_paths,available_at=now(),attempts=0,completed_at=null,last_error_code=null;
 end if;
end;$$;

-- A match's individual command only edits presentation, including for old clients.
create or replace function internal.configure_event_publication_with_result_for_actor(target_event_id uuid,new_state text,new_public_title text,new_publish_location boolean,expected_revision bigint,idempotency_key uuid,new_publish_result boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; is_match boolean;
begin
 select event_type='match' into is_match from core.events where id=target_event_id;
 result:=internal.configure_event_publication_with_result_legacy_for_actor(target_event_id,
  case when is_match then 'private' else new_state end,new_public_title,new_publish_location,expected_revision,idempotency_key,
  case when is_match then false else new_publish_result end);
 perform internal.sync_team_public_event(target_event_id);
 if is_match then
  result:=result||jsonb_build_object('state',case when exists(select 1 from public_api.event_projections where public_id=target_event_id) then 'published' else 'private' end,
   'publish_result',exists(select 1 from public_api.match_result_projections where event_public_id=target_event_id));
 end if;
 return result;
end;$$;

-- Display the effective team-controlled visibility in the editorial list.
do $patch$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.get_publication_management_for_actor(uuid)'::regprocedure);
 patched:=replace(definition,'''publication_state'',coalesce(setting.state,''private'')',
  '''publication_state'',case when event_row.event_type=''match'' then case when exists(select 1 from public_api.event_projections effective where effective.public_id=event_row.id) then ''published'' else ''private'' end else coalesce(setting.state,''private'') end');
 if patched=definition then raise exception 'publication management patch point missing';end if;
 execute patched;
end$patch$;

-- Profile and address share one transaction and one retry receipt.
create function internal.update_my_profile_details_v2_for_actor(new_display_name text,
 new_contact_email text,new_phone text,avatar_action text,staged_avatar_id uuid,
 new_street text,new_postal text,new_city text,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); cached jsonb; saved_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 if idempotency_key is null or expected_revision is null then raise invalid_parameter_value using message='invalid_profile';end if;
 perform 1 from core.profiles where id=actor_id for update;
 select d.result into cached from internal.command_deduplication d where d.actor_profile_id=actor_id
  and d.command_type='profile.details.update.v2' and d.idempotency_key=update_my_profile_details_v2_for_actor.idempotency_key;
 if cached is not null then return (cached->>'revision')::bigint;end if;
 perform internal.normalized_address(new_street,new_postal,new_city);
 saved_revision:=internal.update_my_profile_details_for_actor(new_display_name,new_contact_email,new_phone,
  avatar_action,staged_avatar_id,expected_revision,md5(idempotency_key::text||':profile-v2')::uuid);
 perform internal.update_my_address_for_actor(new_street,new_postal,new_city);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'profile.details.update.v2',jsonb_build_object('revision',saved_revision));
 return saved_revision;
end$$;
create function api.update_my_profile_details_v2(new_display_name text,new_contact_email text,new_phone text,
 avatar_action text,staged_avatar_id uuid,new_street text,new_postal text,new_city text,expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path='' as $$
 select internal.update_my_profile_details_v2_for_actor(new_display_name,new_contact_email,new_phone,avatar_action,
 staged_avatar_id,new_street,new_postal,new_city,expected_revision,idempotency_key)
$$;
revoke all on function internal.update_my_profile_details_v2_for_actor(text,text,text,text,uuid,text,text,text,bigint,uuid),
 api.update_my_profile_details_v2(text,text,text,text,uuid,text,text,text,bigint,uuid) from public,anon,authenticated;
grant execute on function internal.update_my_profile_details_v2_for_actor(text,text,text,text,uuid,text,text,text,bigint,uuid),
 api.update_my_profile_details_v2(text,text,text,text,uuid,text,text,text,bigint,uuid) to authenticated;

-- Reconcile all existing matches, including legacy individual settings.
do $$declare item record;begin
 for item in select id from core.events where event_type='match' order by id loop
  perform internal.sync_team_public_event(item.id);
 end loop;
end$$;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261002084222_review_fixes_team_publication_and_profile','greenfield','Review fixes approved 2026-10-02');
notify pgrst,'reload schema';
