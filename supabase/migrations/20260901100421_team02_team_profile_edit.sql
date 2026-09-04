-- TEAM-02 capability-scoped editing of the private team profile.

create function internal.get_team_profile_edit_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); team_row core.teams%rowtype; profile_row core.team_profiles%rowtype;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select * into team_row from core.teams team where team.id=target_team_id and team.status='active';
  if team_row.id is null or not internal.actor_has_capability(team_row.club_id,team_row.id,'club.memberships.manage')
  then raise insufficient_privilege using message='not_found'; end if;
  select * into profile_row from core.team_profiles profile where profile.team_id=team_row.id;
  return jsonb_build_object(
    'team_id',team_row.id,'team_type',profile_row.team_type,'age_class',profile_row.age_class,
    'summary',profile_row.summary,'image_url',profile_row.image_url,
    'revision',coalesce(profile_row.revision,0)
  );
end
$$;

create function internal.update_team_profile_for_actor(
  target_team_id uuid,new_team_type text,new_age_class text,new_summary text,new_image_url text,
  expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); team_row core.teams%rowtype; profile_row core.team_profiles%rowtype;
  existing_result jsonb; normalized_type text:=nullif(btrim(coalesce(new_team_type,'')),'');
  normalized_age text:=nullif(btrim(coalesce(new_age_class,'')),'');
  normalized_summary text:=nullif(btrim(coalesce(new_summary,'')),'');
  normalized_image text:=nullif(btrim(coalesce(new_image_url,'')),''); new_revision bigint;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select dedupe.result into existing_result from internal.command_deduplication dedupe
  where dedupe.actor_profile_id=actor_id and dedupe.command_type='team.profile.update.v1'
    and dedupe.idempotency_key=update_team_profile_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'revision')::bigint; end if;
  if expected_revision<0 or length(coalesce(normalized_type,''))>80 or length(coalesce(normalized_age,''))>80
    or length(coalesce(normalized_summary,''))>1000 or length(coalesce(normalized_image,''))>2048
    or (normalized_image is not null and normalized_image!~'^https://')
  then raise invalid_parameter_value using message='invalid_team_profile'; end if;
  select * into team_row from core.teams team where team.id=target_team_id and team.status='active';
  if team_row.id is null or not internal.actor_has_capability(team_row.club_id,team_row.id,'club.memberships.manage')
  then raise insufficient_privilege using message='not_found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('team-profile:'||team_row.id::text,0));
  select * into profile_row from core.team_profiles profile where profile.team_id=team_row.id for update;
  if profile_row.team_id is null then
    if expected_revision<>0 then raise serialization_failure using message='stale_revision'; end if;
    insert into core.team_profiles(team_id,team_type,age_class,summary,image_url,updated_by)
    values(team_row.id,normalized_type,normalized_age,normalized_summary,normalized_image,actor_id)
    returning revision into new_revision;
  else
    if profile_row.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
    update core.team_profiles set team_type=normalized_type,age_class=normalized_age,summary=normalized_summary,
      image_url=normalized_image,updated_at=now(),updated_by=actor_id,revision=revision+1
    where team_id=team_row.id returning revision into new_revision;
  end if;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'team.profile.update.v1',jsonb_build_object('team_id',team_row.id,'revision',new_revision));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
  values(team_row.club_id,actor_id,'team.profile.update.v1','team',team_row.id,new_revision,
    jsonb_build_object('has_summary',normalized_summary is not null,'has_image',normalized_image is not null));
  return new_revision;
end
$$;

create function api.get_team_profile_edit(target_team_id uuid)
returns jsonb language sql stable security invoker set search_path=''
as $$select internal.get_team_profile_edit_for_actor(target_team_id)$$;

create function api.update_team_profile(target_team_id uuid,new_team_type text,new_age_class text,
  new_summary text,new_image_url text,expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path=''
as $$select internal.update_team_profile_for_actor(target_team_id,new_team_type,new_age_class,new_summary,
  new_image_url,expected_revision,idempotency_key)$$;

revoke all on function internal.get_team_profile_edit_for_actor(uuid),
  internal.update_team_profile_for_actor(uuid,text,text,text,text,bigint,uuid),
  api.get_team_profile_edit(uuid),api.update_team_profile(uuid,text,text,text,text,bigint,uuid)
  from public,anon,authenticated;
grant execute on function internal.get_team_profile_edit_for_actor(uuid),
  internal.update_team_profile_for_actor(uuid,text,text,text,text,bigint,uuid),
  api.get_team_profile_edit(uuid),api.update_team_profile(uuid,text,text,text,text,bigint,uuid)
  to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260901100421_team02_team_profile_edit','greenfield','TEAM-02 private team profile edit command');

notify pgrst,'reload schema';
