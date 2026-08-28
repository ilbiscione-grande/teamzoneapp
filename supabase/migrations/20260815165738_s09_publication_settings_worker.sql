-- S09 draft publication settings and two-phase projection/cache worker.
-- No public read privilege is introduced and runtime activation remains impossible.

alter table internal.publication_projection_jobs
  drop constraint publication_projection_jobs_state_check,
  add constraint publication_projection_jobs_state_check
    check (state in ('pending','processing','awaiting_invalidation','completed','failed'));

drop index internal.publication_projection_jobs_worker_idx;
create index publication_projection_jobs_worker_idx
  on internal.publication_projection_jobs(state,available_at,created_at,id)
  where state in ('pending','failed');

create function internal.get_publication_settings_for_actor(
  target_club_id uuid,
  target_team_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id,null,'club.memberships.manage') then
    raise insufficient_privilege using message='not_found';
  end if;
  if target_team_id is not null and not exists(
    select 1 from core.teams where id=target_team_id and club_id=target_club_id
  ) then raise insufficient_privilege using message='not_found'; end if;

  select jsonb_build_object(
    'club', coalesce((select jsonb_build_object(
      'mode',setting.mode,'public_id',setting.public_id,'slug',setting.slug,
      'locality',setting.locality,'description',setting.published_description,
      'revision',setting.revision,'changed_at',setting.changed_at
    ) from core.club_publication_settings setting
      where setting.club_id=target_club_id), jsonb_build_object('mode','private','revision',0)),
    'team', case when target_team_id is null then null else coalesce((select jsonb_build_object(
      'mode',setting.mode,'public_id',setting.public_id,'slug',setting.slug,
      'age_class',setting.published_age_class,'revision',setting.revision,
      'changed_at',setting.changed_at
    ) from core.team_publication_settings setting
      where setting.club_id=target_club_id and setting.team_id=target_team_id),
      jsonb_build_object('mode','private','revision',0)) end,
    'runtime_enabled', false
  ) into result;
  return result;
end;
$$;

create function internal.configure_club_publication_for_actor(
  target_club_id uuid,new_mode text,new_slug text,new_locality text,
  new_description text,expected_revision bigint,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); setting core.club_publication_settings%rowtype;
  existing jsonb; new_revision bigint; job_action text;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id,null,'club.memberships.manage')
     or not exists(select 1 from core.clubs where id=target_club_id and status='active') then
    raise insufficient_privilege using message='not_found';
  end if;
  if new_mode not in ('private','draft')
     or lower(btrim(coalesce(new_slug,''))) !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
     or length(btrim(new_slug)) not between 2 and 80
     or (new_locality is not null and length(btrim(new_locality)) not between 1 and 120)
     or (new_description is not null and length(new_description)>4000) then
    raise check_violation using message='invalid_publication_settings';
  end if;
  select result into existing from internal.command_deduplication dedupe
   where dedupe.actor_profile_id=actor_id and dedupe.command_type='publication.club.configured.v1'
     and dedupe.idempotency_key=p_idempotency_key;
  if existing is not null then return existing; end if;

  select * into setting from core.club_publication_settings where club_id=target_club_id for update;
  if coalesce(setting.revision,0)<>expected_revision then
    raise serialization_failure using message='stale_revision';
  end if;
  insert into core.club_publication_settings(
    club_id,mode,slug,locality,published_description,changed_by
  ) values(
    target_club_id,new_mode,lower(btrim(new_slug)),nullif(btrim(new_locality),''),
    nullif(btrim(new_description),''),actor_id
  ) on conflict(club_id) do update set
    mode=excluded.mode,slug=excluded.slug,locality=excluded.locality,
    published_description=excluded.published_description,changed_at=now(),
    changed_by=actor_id,revision=core.club_publication_settings.revision+1
  returning revision into new_revision;
  job_action:=case when new_mode='draft' then 'rebuild' else 'remove' end;
  insert into internal.publication_projection_jobs(
    club_id,aggregate_type,aggregate_id,requested_revision,action,created_by
  ) values(target_club_id,'club',target_club_id,new_revision,job_action,actor_id);
  existing:=jsonb_build_object('club_id',target_club_id,'mode',new_mode,
    'revision',new_revision,'projection_state','pending');
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,p_idempotency_key,'publication.club.configured.v1',existing);
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata
  ) values(target_club_id,actor_id,'publication.club.configured.v1','club',target_club_id,
    new_revision,jsonb_build_object('mode',new_mode,'job_action',job_action));
  return existing;
end;
$$;

create function internal.configure_team_publication_for_actor(
  target_club_id uuid,target_team_id uuid,new_mode text,new_slug text,
  new_age_class text,expected_revision bigint,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); setting core.team_publication_settings%rowtype;
  existing jsonb; new_revision bigint; job_action text;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id,null,'club.memberships.manage')
     or not exists(select 1 from core.teams where id=target_team_id and club_id=target_club_id and status='active')
     or not exists(select 1 from core.club_publication_settings where club_id=target_club_id) then
    raise insufficient_privilege using message='not_found';
  end if;
  if new_mode not in ('private','draft')
     or lower(btrim(coalesce(new_slug,''))) !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
     or length(btrim(new_slug)) not between 1 and 80
     or (new_age_class is not null and length(btrim(new_age_class)) not between 1 and 80) then
    raise check_violation using message='invalid_publication_settings';
  end if;
  select result into existing from internal.command_deduplication dedupe
   where dedupe.actor_profile_id=actor_id and dedupe.command_type='publication.team.configured.v1'
     and dedupe.idempotency_key=p_idempotency_key;
  if existing is not null then return existing; end if;
  select * into setting from core.team_publication_settings where team_id=target_team_id for update;
  if coalesce(setting.revision,0)<>expected_revision then
    raise serialization_failure using message='stale_revision';
  end if;
  insert into core.team_publication_settings(
    team_id,club_id,mode,slug,published_age_class,changed_by
  ) values(
    target_team_id,target_club_id,new_mode,lower(btrim(new_slug)),
    nullif(btrim(new_age_class),''),actor_id
  ) on conflict(team_id) do update set
    mode=excluded.mode,slug=excluded.slug,published_age_class=excluded.published_age_class,
    changed_at=now(),changed_by=actor_id,revision=core.team_publication_settings.revision+1
  returning revision into new_revision;
  job_action:=case when new_mode='draft' then 'rebuild' else 'remove' end;
  insert into internal.publication_projection_jobs(
    club_id,aggregate_type,aggregate_id,requested_revision,action,created_by
  ) values(target_club_id,'team',target_team_id,new_revision,job_action,actor_id);
  existing:=jsonb_build_object('team_id',target_team_id,'mode',new_mode,
    'revision',new_revision,'projection_state','pending');
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,p_idempotency_key,'publication.team.configured.v1',existing);
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata
  ) values(target_club_id,actor_id,'publication.team.configured.v1','team',target_team_id,
    new_revision,jsonb_build_object('mode',new_mode,'job_action',job_action));
  return existing;
end;
$$;

create function internal.claim_publication_projection_jobs(batch_size integer default 20)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  if batch_size not between 1 and 50 then raise invalid_parameter_value using message='invalid_batch'; end if;
  with claimed as (
    select id from internal.publication_projection_jobs
     where state in ('pending','failed') and available_at<=now() and attempts<20
     order by available_at,created_at,id for update skip locked limit batch_size
  ), updated as (
    update internal.publication_projection_jobs job set
      state='processing',attempts=attempts+1,last_error_code=null
     from claimed where job.id=claimed.id
     returning job.id,job.aggregate_type,job.aggregate_id,job.action,
       job.requested_revision,job.attempts
  ) select coalesce(jsonb_agg(to_jsonb(updated) order by updated.id),'[]'::jsonb)
      into result from updated;
  return result;
end;
$$;

create function internal.apply_publication_projection_job(target_job_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare job internal.publication_projection_jobs%rowtype;
  club_setting core.club_publication_settings%rowtype;
  team_setting core.team_publication_settings%rowtype;
  club_row core.clubs%rowtype; team_row core.teams%rowtype;
  paths text[]:=array[]::text[];
begin
  select * into job from internal.publication_projection_jobs where id=target_job_id for update;
  if job.id is null or job.state<>'processing' then
    raise object_not_in_prerequisite_state using message='job_not_processing';
  end if;
  if job.aggregate_type='club' then
    select * into club_setting from core.club_publication_settings where club_id=job.aggregate_id;
    if club_setting.club_id is null then raise no_data_found using message='setting_missing'; end if;
    paths:=array['/'||club_setting.slug];
    if job.action='rebuild' and club_setting.mode='draft' and club_setting.revision=job.requested_revision then
      select * into club_row from core.clubs where id=job.aggregate_id and status='active';
      if club_row.id is null then raise no_data_found using message='club_missing'; end if;
      insert into public_api.club_projections(
        public_id,slug,name,locality,description,profile_media_path,source_revision,projected_at
      ) values(
        club_setting.public_id,club_setting.slug,club_row.name,club_setting.locality,
        club_setting.published_description,null,club_setting.revision,now()
      ) on conflict(public_id) do update set
        slug=excluded.slug,name=excluded.name,locality=excluded.locality,
        description=excluded.description,profile_media_path=null,
        source_revision=excluded.source_revision,projected_at=excluded.projected_at;
    else
      delete from public_api.club_projections where public_id=club_setting.public_id;
    end if;
  elsif job.aggregate_type='team' then
    select * into team_setting from core.team_publication_settings where team_id=job.aggregate_id;
    select * into club_setting from core.club_publication_settings where club_id=job.club_id;
    if team_setting.team_id is null or club_setting.club_id is null then
      raise no_data_found using message='setting_missing';
    end if;
    paths:=array['/'||club_setting.slug||'/'||team_setting.slug];
    if job.action='rebuild' and team_setting.mode='draft' and club_setting.mode='draft'
       and team_setting.revision=job.requested_revision then
      select * into club_row from core.clubs where id=job.club_id and status='active';
      select * into team_row from core.teams where id=job.aggregate_id and club_id=job.club_id and status='active';
      if club_row.id is null or team_row.id is null then raise no_data_found using message='aggregate_missing'; end if;
      insert into public_api.club_projections(
        public_id,slug,name,locality,description,profile_media_path,source_revision,projected_at
      ) values(
        club_setting.public_id,club_setting.slug,club_row.name,club_setting.locality,
        club_setting.published_description,null,club_setting.revision,now()
      ) on conflict(public_id) do update set
        slug=excluded.slug,name=excluded.name,locality=excluded.locality,
        description=excluded.description,profile_media_path=null,
        source_revision=excluded.source_revision,projected_at=excluded.projected_at;
      insert into public_api.team_projections(
        public_id,club_public_id,club_slug,slug,name,age_class,source_revision,projected_at
      ) values(
        team_setting.public_id,club_setting.public_id,club_setting.slug,team_setting.slug,
        team_row.name,team_setting.published_age_class,team_setting.revision,now()
      ) on conflict(public_id) do update set
        club_public_id=excluded.club_public_id,club_slug=excluded.club_slug,slug=excluded.slug,
        name=excluded.name,age_class=excluded.age_class,
        source_revision=excluded.source_revision,projected_at=excluded.projected_at;
    else
      delete from public_api.team_projections where public_id=team_setting.public_id;
    end if;
  elsif job.aggregate_type='person' and job.action in ('remove','invalidate') then
    paths:=job.affected_paths;
  else
    raise feature_not_supported using message='unsupported_projection_job';
  end if;
  update internal.publication_projection_jobs set
    state='awaiting_invalidation',affected_paths=paths,last_error_code=null
   where id=job.id;
  return jsonb_build_object('job_id',job.id,'state','awaiting_invalidation','paths',paths);
exception when others then
  update internal.publication_projection_jobs set
    state='failed',available_at=now()+least(interval '15 minutes',interval '30 seconds'*(2^least(attempts,5))),
    last_error_code=sqlstate
   where id=target_job_id and state='processing';
  return jsonb_build_object('job_id',target_job_id,'state','failed','error_code',sqlstate);
end;
$$;

create function internal.finish_publication_invalidation(
  target_job_id uuid,invalidation_succeeded boolean,new_error_code text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare job internal.publication_projection_jobs%rowtype;
begin
  select * into job from internal.publication_projection_jobs where id=target_job_id for update;
  if job.id is null or job.state<>'awaiting_invalidation' then
    raise object_not_in_prerequisite_state using message='job_not_awaiting_invalidation';
  end if;
  if invalidation_succeeded then
    update internal.publication_projection_jobs set
      state='completed',completed_at=now(),last_error_code=null where id=job.id;
    return jsonb_build_object('job_id',job.id,'state','completed');
  end if;
  update internal.publication_projection_jobs set
    state='failed',available_at=now()+least(interval '15 minutes',interval '30 seconds'*(2^least(attempts,5))),
    last_error_code=coalesce(nullif(btrim(new_error_code),''),'cache_invalidation_failed')
   where id=job.id;
  return jsonb_build_object('job_id',job.id,'state','failed');
end;
$$;

revoke all on function
  internal.get_publication_settings_for_actor(uuid,uuid),
  internal.configure_club_publication_for_actor(uuid,text,text,text,text,bigint,uuid),
  internal.configure_team_publication_for_actor(uuid,uuid,text,text,text,bigint,uuid),
  internal.claim_publication_projection_jobs(integer),
  internal.apply_publication_projection_job(uuid),
  internal.finish_publication_invalidation(uuid,boolean,text)
from public,anon,authenticated;
grant execute on function
  internal.get_publication_settings_for_actor(uuid,uuid),
  internal.configure_club_publication_for_actor(uuid,text,text,text,text,bigint,uuid),
  internal.configure_team_publication_for_actor(uuid,uuid,text,text,text,bigint,uuid)
to authenticated;
grant execute on function
  internal.claim_publication_projection_jobs(integer),
  internal.apply_publication_projection_job(uuid),
  internal.finish_publication_invalidation(uuid,boolean,text)
to service_role;

create function api.get_publication_settings(club_id uuid,team_id uuid default null)
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.get_publication_settings_for_actor(club_id,team_id)$$;
create function api.configure_club_publication(
  club_id uuid,mode text,slug text,locality text,description text,
  expected_revision bigint,idempotency_key uuid
) returns jsonb language sql security invoker set search_path='' as
$$select internal.configure_club_publication_for_actor(club_id,mode,slug,locality,description,expected_revision,idempotency_key)$$;
create function api.configure_team_publication(
  club_id uuid,team_id uuid,mode text,slug text,age_class text,
  expected_revision bigint,idempotency_key uuid
) returns jsonb language sql security invoker set search_path='' as
$$select internal.configure_team_publication_for_actor(club_id,team_id,mode,slug,age_class,expected_revision,idempotency_key)$$;
create function api.claim_publication_projection_jobs(batch_size integer default 20)
returns jsonb language sql security invoker set search_path='' as
$$select internal.claim_publication_projection_jobs(batch_size)$$;
create function api.apply_publication_projection_job(job_id uuid)
returns jsonb language sql security invoker set search_path='' as
$$select internal.apply_publication_projection_job(job_id)$$;
create function api.finish_publication_invalidation(job_id uuid,succeeded boolean,error_code text default null)
returns jsonb language sql security invoker set search_path='' as
$$select internal.finish_publication_invalidation(job_id,succeeded,error_code)$$;

revoke all on function
  api.get_publication_settings(uuid,uuid),
  api.configure_club_publication(uuid,text,text,text,text,bigint,uuid),
  api.configure_team_publication(uuid,uuid,text,text,text,bigint,uuid),
  api.claim_publication_projection_jobs(integer),
  api.apply_publication_projection_job(uuid),
  api.finish_publication_invalidation(uuid,boolean,text)
from public,anon,authenticated;
grant execute on function
  api.get_publication_settings(uuid,uuid),
  api.configure_club_publication(uuid,text,text,text,text,bigint,uuid),
  api.configure_team_publication(uuid,uuid,text,text,text,bigint,uuid)
to authenticated;
grant execute on function
  api.claim_publication_projection_jobs(integer),
  api.apply_publication_projection_job(uuid),
  api.finish_publication_invalidation(uuid,boolean,text)
to service_role;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values(
  '20260815165738_s09_publication_settings_worker','greenfield',
  'Private/draft only; two-phase projection and cache invalidation; runtime remains disabled'
);
