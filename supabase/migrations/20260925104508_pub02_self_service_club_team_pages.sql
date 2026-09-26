-- PUB-02 self-service: club publication is a club decision; team leaders may
-- request a channel, but cannot publish it on behalf of the club.
create table core.team_publication_requests (
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references core.clubs(id),
 team_id uuid not null,
 requested_by uuid not null references core.profiles(id),
 message text not null default '' check (length(message)<=1000),
 status text not null default 'pending' check (status in ('pending','approved','rejected')),
 decided_by uuid references core.profiles(id),
 decision_note text check (decision_note is null or length(decision_note)<=1000),
 created_at timestamptz not null default now(),
 decided_at timestamptz,
 foreign key (team_id,club_id) references core.teams(id,club_id),
 check ((status='pending' and decided_by is null and decided_at is null)
     or (status<>'pending' and decided_by is not null and decided_at is not null))
);
create unique index team_publication_one_pending_idx on core.team_publication_requests(team_id) where status='pending';
create index team_publication_requests_club_idx on core.team_publication_requests(club_id,status,created_at desc);
create index team_publication_requests_requester_idx on core.team_publication_requests(requested_by);
create index team_publication_requests_decider_idx on core.team_publication_requests(decided_by) where decided_by is not null;
alter table core.team_publication_requests enable row level security;
revoke all on core.team_publication_requests from public,anon,authenticated;

create function internal.get_publication_self_service_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare is_club_manager boolean;result jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 is_club_manager:=internal.actor_has_capability(target_club_id,null,'publication.manage');
 if not is_club_manager and not exists(select 1 from core.teams t where t.club_id=target_club_id
   and t.status='active' and internal.actor_has_capability(target_club_id,t.id,'team.roster.manage'))
 then raise insufficient_privilege using message='not_found';end if;
 select jsonb_build_object(
  'club',jsonb_build_object('id',c.id,'name',c.name,'slug',coalesce(cs.slug,c.slug),
   'mode',coalesce(cs.mode,'private'),'revision',coalesce(cs.revision,0),
   'official',c.verification_status='official','locality',cs.locality,
   'description',cs.published_description,'fields',coalesce(to_jsonb(cs.published_fields),'[]'::jsonb)),
  'can_manage_club',is_club_manager,
  'teams',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,
    'slug',coalesce(ts.slug,lower(regexp_replace(t.name,'[^a-zA-Z0-9]+','-','g'))),
    'mode',coalesce(ts.mode,'private'),'revision',coalesce(ts.revision,0),
    'fields',coalesce(to_jsonb(ts.published_fields),'[]'::jsonb),
    'age_class',ts.published_age_class,
    'can_request',internal.actor_has_capability(target_club_id,t.id,'team.roster.manage'),
    'request_status',(select r.status from core.team_publication_requests r
      where r.team_id=t.id order by r.created_at desc limit 1)) order by t.name)
    from core.teams t left join core.team_publication_settings ts on ts.team_id=t.id
    where t.club_id=target_club_id and t.status='active' and
      (is_club_manager or internal.actor_has_capability(target_club_id,t.id,'team.roster.manage'))),'[]'::jsonb),
  'requests',case when is_club_manager then coalesce((select jsonb_agg(
    jsonb_build_object('id',r.id,'team_id',r.team_id,'team_name',t.name,
     'message',r.message,'status',r.status,'created_at',r.created_at)
    order by r.created_at desc) from core.team_publication_requests r
    join core.teams t on t.id=r.team_id where r.club_id=target_club_id),'[]'::jsonb)
    else '[]'::jsonb end)
 into result from core.clubs c left join core.club_publication_settings cs on cs.club_id=c.id
 where c.id=target_club_id and c.status='active';
 if result is null then raise insufficient_privilege using message='not_found';end if;
 return result;
end;$$;

-- Public search includes both verified and unverified clubs, with the existing
-- official bit preserved for the UI badge.
create or replace function internal.public_search_clubs(search_text text,ip_sha256_hex text,page_limit integer default 10)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb;result jsonb;
begin
 if not internal.public_runtime_enabled() then return jsonb_build_object('available',false,'items','[]'::jsonb);end if;
 if length(btrim(coalesce(search_text,'')))<3 or length(search_text)>80 or page_limit not between 1 and 10
 then raise invalid_parameter_value using message='invalid_request';end if;
 rate:=internal.consume_public_rate_limit(ip_sha256_hex,'search',null);
 if not(rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',public_id,'slug',slug,'name',name,
  'locality',locality,'official',official,'visibility',visibility) order by lower(name),public_id),'[]'::jsonb) into result
 from(select public_id,slug,name,locality,official,visibility from public_api.club_projections
  where visibility in('listed','published')
   and lower(name)>=lower(btrim(search_text)) and lower(name)<lower(btrim(search_text))||chr(1114111)
  order by lower(name),public_id limit page_limit) matches;
 return jsonb_build_object('available',true,'items',result,'cache_control','no-store');
end;$$;

create function internal.request_team_publication_for_actor(target_club_id uuid,target_team_id uuid,request_message text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare existing_id uuid;new_id uuid;
begin
 if auth.uid() is null or not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.manage')
  or not exists(select 1 from core.teams where id=target_team_id and club_id=target_club_id and status='active')
 then raise insufficient_privilege using message='not_found';end if;
 if length(coalesce(request_message,''))>1000 then raise invalid_parameter_value using message='invalid_message';end if;
 perform pg_advisory_xact_lock(hashtextextended('team-publication-request:'||target_team_id::text,0));
 select id into existing_id from core.team_publication_requests where team_id=target_team_id and status='pending';
 if existing_id is not null then return jsonb_build_object('id',existing_id,'status','pending');end if;
 insert into core.team_publication_requests(club_id,team_id,requested_by,message)
 values(target_club_id,target_team_id,auth.uid(),btrim(coalesce(request_message,''))) returning id into new_id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,
  aggregate_id,aggregate_revision,metadata)
 values(target_club_id,auth.uid(),'publication.team.requested','team',target_team_id,1,
  jsonb_build_object('request_id',new_id));
 return jsonb_build_object('id',new_id,'status','pending');
end;$$;

create function internal.decide_team_publication_for_actor(request_id uuid,approve boolean,note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare request_row core.team_publication_requests%rowtype;
begin
 select * into request_row from core.team_publication_requests where id=request_id for update;
 if request_row.id is null or auth.uid() is null or
   not internal.actor_has_capability(request_row.club_id,null,'publication.manage')
 then raise insufficient_privilege using message='not_found';end if;
 if length(coalesce(note,''))>1000 then raise invalid_parameter_value using message='invalid_note';end if;
 if request_row.status<>'pending' then
  return jsonb_build_object('id',request_row.id,'status',request_row.status);
 end if;
 update core.team_publication_requests set status=case when approve then 'approved' else 'rejected' end,
  decided_by=auth.uid(),decided_at=now(),decision_note=nullif(btrim(coalesce(note,'')),'')
 where id=request_id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,
  aggregate_id,aggregate_revision,metadata)
 values(request_row.club_id,auth.uid(),'publication.team.decided','team',request_row.team_id,1,
  jsonb_build_object('request_id',request_id,'approved',approve));
 return jsonb_build_object('id',request_id,'status',case when approve then 'approved' else 'rejected' end);
end;$$;

create function api.get_publication_self_service(club_id uuid) returns jsonb
language sql stable security invoker set search_path='' as
$$select internal.get_publication_self_service_for_actor(club_id)$$;
create function api.request_team_publication(club_id uuid,team_id uuid,message text default '') returns jsonb
language sql security invoker set search_path='' as
$$select internal.request_team_publication_for_actor(club_id,team_id,message)$$;
create function api.decide_team_publication(request_id uuid,approve boolean,note text default '') returns jsonb
language sql security invoker set search_path='' as
$$select internal.decide_team_publication_for_actor(request_id,approve,note)$$;
revoke all on function internal.get_publication_self_service_for_actor(uuid),
 internal.request_team_publication_for_actor(uuid,uuid,text),
 internal.decide_team_publication_for_actor(uuid,boolean,text),
 api.get_publication_self_service(uuid),api.request_team_publication(uuid,uuid,text),
 api.decide_team_publication(uuid,boolean,text) from public,anon,authenticated;
grant execute on function internal.get_publication_self_service_for_actor(uuid),
 internal.request_team_publication_for_actor(uuid,uuid,text),
 internal.decide_team_publication_for_actor(uuid,boolean,text),
 api.get_publication_self_service(uuid),api.request_team_publication(uuid,uuid,text),
 api.decide_team_publication(uuid,boolean,text) to authenticated;

create or replace function internal.configure_publication_v2_for_actor(
 target_club_id uuid,target_type text,target_id uuid,new_mode text,new_slug text,
 new_fields text[],new_locality text,new_description text,new_age_class text,
 new_policy_version text,new_confirmation_expires_at timestamptz,
 expected_revision bigint,idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();existing jsonb;confirmation_id uuid;new_revision bigint;
 target_aggregate_id uuid:=case when target_type='club' then target_club_id else target_id end;
begin
 -- Deliberately club-scoped for both aggregates: a leader requests, a club manager publishes.
 if actor_id is null or not internal.actor_has_capability(target_club_id,null,'publication.manage')
 then raise insufficient_privilege using message='not_found';end if;
 if target_type not in('club','team') or new_mode not in('private','listed','published')
  or lower(btrim(coalesce(new_slug,'')))!~'^[a-z0-9]+(?:-[a-z0-9]+)*$'
  or length(btrim(new_slug)) not between 2 and 80
  or (new_mode<>'private' and not internal.publication_fields_valid(target_type,new_fields))
  or (new_mode<>'private' and (new_confirmation_expires_at<=now()
    or new_confirmation_expires_at>now()+interval '366 days'
    or length(btrim(coalesce(new_policy_version,''))) not between 1 and 80))
 then raise invalid_parameter_value using message='invalid_publication_settings';end if;
 if not exists(select 1 from core.clubs c where c.id=target_club_id and c.status='active')
 then raise insufficient_privilege using message='not_found';end if;
 if target_type='team' and not exists(select 1 from core.teams t
   where t.id=target_id and t.club_id=target_club_id and t.status='active')
 then raise insufficient_privilege using message='not_found';end if;
 if target_type='team' and new_mode<>'private' and not exists(
   select 1 from core.club_publication_settings s
   join core.publication_confirmations c on c.id=s.confirmation_id
   where s.club_id=target_club_id and s.mode='published' and c.state='active' and c.expires_at>now())
 then raise object_not_in_prerequisite_state using message='club_page_required';end if;
 select result into existing from internal.command_deduplication d
  where d.actor_profile_id=actor_id and d.command_type='publication.settings.v2'
   and d.idempotency_key=configure_publication_v2_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 perform pg_advisory_xact_lock(hashtextextended('publication:'||target_type||':'||target_aggregate_id::text,0));
 if target_type='club' then
  if coalesce((select revision from core.club_publication_settings where club_id=target_club_id),0)<>expected_revision
   then raise serialization_failure using message='stale_revision';end if;
 else
  if coalesce((select revision from core.team_publication_settings where team_id=target_id),0)<>expected_revision
   then raise serialization_failure using message='stale_revision';end if;
 end if;
 update core.publication_confirmations set state='superseded',revision=revision+1
  where club_id=target_club_id and aggregate_type=target_type and aggregate_id=target_aggregate_id and state='active';
 if new_mode<>'private' then
  insert into core.publication_confirmations(club_id,aggregate_type,aggregate_id,mode,
   field_allowlist,policy_version,confirmed_by,expires_at)
  values(target_club_id,target_type,target_aggregate_id,new_mode,new_fields,btrim(new_policy_version),
   actor_id,new_confirmation_expires_at) returning id into confirmation_id;
 end if;
 if target_type='club' then
  insert into core.club_publication_settings(club_id,mode,slug,locality,published_description,
   published_fields,confirmation_id,changed_by)
  values(target_club_id,new_mode,lower(btrim(new_slug)),nullif(btrim(new_locality),''),
   nullif(btrim(new_description),''),case when new_mode='private' then array[]::text[] else new_fields end,
   confirmation_id,actor_id)
  on conflict(club_id) do update set mode=excluded.mode,slug=excluded.slug,locality=excluded.locality,
   published_description=excluded.published_description,published_fields=excluded.published_fields,
   confirmation_id=excluded.confirmation_id,changed_at=now(),changed_by=actor_id,
   revision=core.club_publication_settings.revision+1 returning revision into new_revision;
 else
  insert into core.team_publication_settings(team_id,club_id,mode,slug,published_age_class,
   published_fields,confirmation_id,changed_by)
  values(target_id,target_club_id,new_mode,lower(btrim(new_slug)),nullif(btrim(new_age_class),''),
   case when new_mode='private' then array[]::text[] else new_fields end,confirmation_id,actor_id)
  on conflict(team_id) do update set mode=excluded.mode,slug=excluded.slug,
   published_age_class=excluded.published_age_class,published_fields=excluded.published_fields,
   confirmation_id=excluded.confirmation_id,changed_at=now(),changed_by=actor_id,
   revision=core.team_publication_settings.revision+1 returning revision into new_revision;
 end if;
 insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,
  requested_revision,action,created_by)
 values(target_club_id,target_type,target_aggregate_id,new_revision,
  case when new_mode='private' then 'remove' else 'rebuild' end,actor_id);
 -- A private club must remove all of its public team channels as well.
 if target_type='club' and new_mode<>'published' then
  insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,
    requested_revision,action,created_by)
  select target_club_id,'team',s.team_id,s.revision,'remove',actor_id
  from core.team_publication_settings s where s.club_id=target_club_id and s.mode<>'private'
  on conflict(club_id,aggregate_type,aggregate_id,requested_revision,action) do nothing;
 end if;
 if target_type='club' and new_mode='published' then
  insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,
    requested_revision,action,created_by)
  select target_club_id,'team',s.team_id,s.revision,'rebuild',actor_id
  from core.team_publication_settings s where s.club_id=target_club_id and s.mode<>'private'
  on conflict(club_id,aggregate_type,aggregate_id,requested_revision,action) do nothing;
 end if;
 existing:=jsonb_build_object('aggregate_type',target_type,'aggregate_id',target_aggregate_id,
  'mode',new_mode,'fields',case when new_mode='private' then array[]::text[] else new_fields end,
  'revision',new_revision,'projection_state','pending');
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'publication.settings.v2',existing);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,
  aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,'publication.settings.v2',target_type,target_aggregate_id,new_revision,
  jsonb_build_object('mode',new_mode,'fields',case when new_mode='private' then array[]::text[] else new_fields end,
   'confirmation_id',confirmation_id,'policy_version',new_policy_version));
 return existing;
end;$$;

create or replace function internal.apply_publication_projection_job(target_job_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare job internal.publication_projection_jobs%rowtype;
 club_setting core.club_publication_settings%rowtype;
 team_setting core.team_publication_settings%rowtype;
 club_row core.clubs%rowtype;team_row core.teams%rowtype;paths text[]:=array[]::text[];
 valid_confirmation boolean:=false;
begin
 select * into job from internal.publication_projection_jobs where id=target_job_id for update;
 if job.id is null or job.state<>'processing' then
  raise object_not_in_prerequisite_state using message='job_not_processing';end if;
 if job.aggregate_type='club' then
  select * into club_setting from core.club_publication_settings where club_id=job.aggregate_id;
  if club_setting.club_id is null then raise no_data_found using message='setting_missing';end if;
  paths:=array['/'||club_setting.slug];
  select exists(select 1 from core.publication_confirmations confirmation
   where confirmation.id=club_setting.confirmation_id and confirmation.club_id=job.club_id
    and confirmation.aggregate_type='club' and confirmation.aggregate_id=job.aggregate_id
    and confirmation.state='active' and confirmation.expires_at>now()
    and confirmation.mode=club_setting.mode and confirmation.field_allowlist=club_setting.published_fields)
   into valid_confirmation;
  if job.action='rebuild' and club_setting.mode in('listed','published')
   and club_setting.revision=job.requested_revision and valid_confirmation then
   select * into club_row from core.clubs where id=job.aggregate_id and status='active';
   if club_row.id is null then raise no_data_found using message='club_not_active';end if;
   insert into public_api.club_projections(public_id,slug,name,locality,description,
    profile_media_path,source_revision,projected_at,official,visibility)
   values(club_setting.public_id,club_setting.slug,club_row.name,
    case when 'locality'=any(club_setting.published_fields) then club_setting.locality end,
    case when club_setting.mode='published' and 'description'=any(club_setting.published_fields)
      then club_setting.published_description end,null,club_setting.revision,now(),
    club_row.verification_status='official',club_setting.mode)
   on conflict(public_id) do update set slug=excluded.slug,name=excluded.name,
    locality=excluded.locality,description=excluded.description,profile_media_path=null,
    source_revision=excluded.source_revision,projected_at=excluded.projected_at,
    official=excluded.official,visibility=excluded.visibility;
  else delete from public_api.club_projections where public_id=club_setting.public_id;end if;
 elsif job.aggregate_type='team' then
  select * into team_setting from core.team_publication_settings where team_id=job.aggregate_id;
  select * into club_setting from core.club_publication_settings where club_id=job.club_id;
  if team_setting.team_id is null or club_setting.club_id is null then
   raise no_data_found using message='setting_missing';end if;
  paths:=array['/'||club_setting.slug||'/'||team_setting.slug];
  select exists(select 1 from core.publication_confirmations confirmation
   where confirmation.id=team_setting.confirmation_id and confirmation.club_id=job.club_id
    and confirmation.aggregate_type='team' and confirmation.aggregate_id=job.aggregate_id
    and confirmation.state='active' and confirmation.expires_at>now()
    and confirmation.mode=team_setting.mode and confirmation.field_allowlist=team_setting.published_fields)
   into valid_confirmation;
  if job.action='rebuild' and team_setting.mode in('listed','published')
   and club_setting.mode='published' and team_setting.revision=job.requested_revision
   and valid_confirmation and exists(select 1 from core.publication_confirmations c
     where c.id=club_setting.confirmation_id and c.state='active' and c.expires_at>now()) then
   select * into team_row from core.teams where id=job.aggregate_id and club_id=job.club_id and status='active';
   if team_row.id is null then raise no_data_found using message='aggregate_missing';end if;
   insert into public_api.team_projections(public_id,club_public_id,club_slug,slug,name,
    age_class,source_revision,projected_at,visibility)
   values(team_setting.public_id,club_setting.public_id,club_setting.slug,team_setting.slug,
    team_row.name,case when 'age_class'=any(team_setting.published_fields) then team_setting.published_age_class end,
    team_setting.revision,now(),team_setting.mode)
   on conflict(public_id) do update set club_public_id=excluded.club_public_id,
    club_slug=excluded.club_slug,slug=excluded.slug,name=excluded.name,age_class=excluded.age_class,
    source_revision=excluded.source_revision,projected_at=excluded.projected_at,visibility=excluded.visibility;
  else delete from public_api.team_projections where public_id=team_setting.public_id;end if;
 else raise feature_not_supported using message='unsupported_projection_job';end if;
 update internal.publication_projection_jobs set state='awaiting_invalidation',affected_paths=paths,
  last_error_code=null where id=job.id;
 return jsonb_build_object('job_id',job.id,'state','awaiting_invalidation','paths',paths);
exception when others then
 update internal.publication_projection_jobs set state='failed',
  available_at=now()+least(interval '15 minutes',interval '30 seconds'*(2^least(attempts,5))),
  last_error_code=sqlstate where id=target_job_id and state='processing';
 return jsonb_build_object('job_id',target_job_id,'state','failed','error_code',sqlstate);
end;$$;
notify pgrst,'reload schema';
