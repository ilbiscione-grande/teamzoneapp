-- PUB-02 catalog and publication model. Runtime activation remains separate.

alter table core.club_publication_settings
  drop constraint club_publication_settings_mode_check,
  add constraint club_publication_settings_mode_check
    check(mode in ('private','listed','published')),
  add column published_fields text[] not null default array[]::text[],
  add column confirmation_id uuid,
  add constraint club_publication_fields_allowlist check(
    published_fields <@ array['name','locality','description','profile_media']::text[]
    and cardinality(published_fields)<=4
  );

alter table core.team_publication_settings
  drop constraint team_publication_settings_mode_check,
  add constraint team_publication_settings_mode_check
    check(mode in ('private','listed','published')),
  add column published_fields text[] not null default array[]::text[],
  add column confirmation_id uuid,
  add constraint team_publication_fields_allowlist check(
    published_fields <@ array['name','age_class','profile_media','squad']::text[]
    and cardinality(published_fields)<=4
  );

-- Existing draft configuration was never publicly active. Preserve its content
-- as private until a publisher makes a fresh, audited V2 decision.
update core.club_publication_settings set mode='private' where mode='draft';
update core.team_publication_settings set mode='private' where mode='draft';

create table core.publication_confirmations(
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  aggregate_type text not null check(aggregate_type in ('club','team')),
  aggregate_id uuid not null,
  mode text not null check(mode in ('listed','published')),
  field_allowlist text[] not null,
  policy_version text not null check(length(btrim(policy_version)) between 1 and 80),
  confirmed_by uuid not null references core.profiles(id),
  confirmed_at timestamptz not null default now(),
  expires_at timestamptz not null,
  state text not null default 'active' check(state in ('active','superseded','expired','revoked')),
  revoked_at timestamptz,
  revision bigint not null default 1 check(revision>0),
  check(expires_at>confirmed_at and expires_at<=confirmed_at+interval '366 days'),
  check(cardinality(field_allowlist)>0 and cardinality(field_allowlist)<=8),
  check((state='revoked')=(revoked_at is not null))
);
create unique index publication_confirmations_one_active_idx
  on core.publication_confirmations(club_id,aggregate_type,aggregate_id)
  where state='active';
create index publication_confirmations_expiry_idx
  on core.publication_confirmations(expires_at,club_id) where state='active';
create index publication_confirmations_actor_idx on core.publication_confirmations(confirmed_by);
alter table core.publication_confirmations enable row level security;
create policy publication_confirmations_no_client_access on core.publication_confirmations
  for all to authenticated using(false) with check(false);
revoke all on table core.publication_confirmations from public,anon,authenticated;

-- One-time explicit bootstrap for existing club administrators. This creates a
-- real grant row; runtime checks never infer publishing rights from role names.
insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by)
select membership.club_id,membership.assignment_id,'publication.manage','club',membership.club_id,
 greatest(membership.starts_at,now()),membership.created_by
from core.capability_grants membership
where membership.capability='club.memberships.manage' and membership.scope_type='club'
on conflict(assignment_id,capability,scope_type,scope_id) do nothing;

alter table core.club_publication_settings
  add constraint club_publication_confirmation_fk foreign key(confirmation_id)
    references core.publication_confirmations(id);
alter table core.team_publication_settings
  add constraint team_publication_confirmation_fk foreign key(confirmation_id)
    references core.publication_confirmations(id);

alter table public_api.club_projections
  add column official boolean not null default false,
  add column visibility text not null default 'listed'
    check(visibility in ('listed','published'));
alter table public_api.team_projections
  add column visibility text not null default 'listed'
    check(visibility in ('listed','published'));

create function internal.publication_fields_valid(target_type text,fields text[])
returns boolean language sql immutable set search_path='' as $$
 select fields is not null and cardinality(fields)>0
  and cardinality(fields)=cardinality(array(select distinct unnest(fields)))
  and case target_type
   when 'club' then fields <@ array['name','locality','description','profile_media']::text[]
   when 'team' then fields <@ array['name','age_class','profile_media','squad']::text[]
   else false end
$$;

create function internal.configure_publication_v2_for_actor(
 target_club_id uuid,target_type text,target_id uuid,new_mode text,new_slug text,
 new_fields text[],new_locality text,new_description text,new_age_class text,
 new_policy_version text,new_confirmation_expires_at timestamptz,
 expected_revision bigint,idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();existing jsonb;confirmation_id uuid;new_revision bigint;
 target_aggregate_id uuid:=case when target_type='club' then target_club_id else target_id end;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 if not internal.actor_has_capability(target_club_id,
   case when target_type='team' then target_id else null end,'publication.manage')
 then raise insufficient_privilege using message='not_found';end if;
 if target_type not in('club','team') or new_mode not in('private','listed','published')
  or lower(btrim(coalesce(new_slug,'')))!~'^[a-z0-9]+(?:-[a-z0-9]+)*$'
  or length(btrim(new_slug)) not between 1 and 80
  or (new_mode<>'private' and not internal.publication_fields_valid(target_type,new_fields))
  or (new_mode<>'private' and (new_confirmation_expires_at<=now()
    or new_confirmation_expires_at>now()+interval '366 days'
    or length(btrim(coalesce(new_policy_version,''))) not between 1 and 80))
 then raise invalid_parameter_value using message='invalid_publication_settings';end if;
 if new_mode<>'private' and not exists(select 1 from core.clubs club
   where club.id=target_club_id and club.status='active' and club.verification_status='official')
 then raise insufficient_privilege using message='official_club_required';end if;
 if target_type='team' and not exists(select 1 from core.teams team
   where team.id=target_id and team.club_id=target_club_id and team.status='active')
 then raise insufficient_privilege using message='not_found';end if;
 select result into existing from internal.command_deduplication dedupe
  where dedupe.actor_profile_id=actor_id and dedupe.command_type='publication.settings.v2'
   and dedupe.idempotency_key=configure_publication_v2_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 perform pg_advisory_xact_lock(hashtextextended('publication:'||target_type||':'||target_aggregate_id::text,0));
 update core.publication_confirmations set state='superseded',revision=revision+1
  where club_id=target_club_id and aggregate_type=target_type and aggregate_id=target_aggregate_id
   and state='active';
 if new_mode<>'private' then
  insert into core.publication_confirmations(club_id,aggregate_type,aggregate_id,mode,
   field_allowlist,policy_version,confirmed_by,expires_at)
  values(target_club_id,target_type,target_aggregate_id,new_mode,new_fields,btrim(new_policy_version),
   actor_id,new_confirmation_expires_at) returning id into confirmation_id;
 end if;
 if target_type='club' then
  if coalesce((select revision from core.club_publication_settings where club_id=target_club_id),0)<>expected_revision
   then raise serialization_failure using message='stale_revision';end if;
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
  if coalesce((select revision from core.team_publication_settings where team_id=target_id),0)<>expected_revision
   then raise serialization_failure using message='stale_revision';end if;
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

create function internal.expire_publication_confirmations(batch_size integer default 100)
returns integer language plpgsql security definer set search_path='' as $$
declare changed integer;
begin
 if batch_size not between 1 and 500 then raise invalid_parameter_value using message='invalid_batch';end if;
 with expired as(select id,aggregate_type,aggregate_id from core.publication_confirmations
   where state='active' and expires_at<=now() order by expires_at,id for update skip locked limit batch_size),
 changed_rows as(update core.publication_confirmations confirmation set state='expired',revision=revision+1
   from expired where confirmation.id=expired.id returning expired.aggregate_type,expired.aggregate_id)
 select count(*) into changed from changed_rows;
 insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,
  requested_revision,action,created_by)
 select setting.club_id,'club',setting.club_id,setting.revision+1,'remove',null
 from core.club_publication_settings setting join core.publication_confirmations confirmation
  on confirmation.id=setting.confirmation_id where confirmation.state='expired'
 on conflict(club_id,aggregate_type,aggregate_id,requested_revision,action) do nothing;
 insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,
  requested_revision,action,created_by)
 select setting.club_id,'team',setting.team_id,setting.revision+1,'remove',null
 from core.team_publication_settings setting join core.publication_confirmations confirmation
  on confirmation.id=setting.confirmation_id where confirmation.state='expired'
 on conflict(club_id,aggregate_type,aggregate_id,requested_revision,action) do nothing;
 update core.club_publication_settings setting set mode='private',published_fields=array[]::text[],
  confirmation_id=null,changed_at=now(),revision=revision+1
  where exists(select 1 from core.publication_confirmations confirmation where confirmation.id=setting.confirmation_id and confirmation.state='expired');
 update core.team_publication_settings setting set mode='private',published_fields=array[]::text[],
  confirmation_id=null,changed_at=now(),revision=revision+1
  where exists(select 1 from core.publication_confirmations confirmation where confirmation.id=setting.confirmation_id and confirmation.state='expired');
 return changed;
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
   select * into club_row from core.clubs where id=job.aggregate_id and status='active'
    and verification_status='official';
   if club_row.id is null then raise no_data_found using message='official_club_required';end if;
   insert into public_api.club_projections(public_id,slug,name,locality,description,
    profile_media_path,source_revision,projected_at,official,visibility)
   values(club_setting.public_id,club_setting.slug,club_row.name,
    case when 'locality'=any(club_setting.published_fields) then club_setting.locality end,
    case when club_setting.mode='published' and 'description'=any(club_setting.published_fields)
      then club_setting.published_description end,null,club_setting.revision,now(),true,club_setting.mode)
   on conflict(public_id) do update set slug=excluded.slug,name=excluded.name,
    locality=excluded.locality,description=excluded.description,profile_media_path=null,
    source_revision=excluded.source_revision,projected_at=excluded.projected_at,
    official=true,visibility=excluded.visibility;
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
   and club_setting.mode in('listed','published') and team_setting.revision=job.requested_revision
   and valid_confirmation then
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
  'locality',locality,'official',official) order by lower(name),public_id),'[]'::jsonb) into result
 from(select public_id,slug,name,locality,official from public_api.club_projections
  where visibility in('listed','published') and official
   and lower(name)>=lower(btrim(search_text)) and lower(name)<lower(btrim(search_text))||chr(1114111)
  order by lower(name),public_id limit page_limit) matches;
 return jsonb_build_object('available',true,'items',result,'cache_control','no-store');
end;$$;

create function api.configure_publication_v2(club_id uuid,aggregate_type text,aggregate_id uuid,
 mode text,slug text,fields text[],locality text,description text,age_class text,
 policy_version text,confirmation_expires_at timestamptz,expected_revision bigint,idempotency_key uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select internal.configure_publication_v2_for_actor(club_id,aggregate_type,aggregate_id,mode,slug,
  fields,locality,description,age_class,policy_version,confirmation_expires_at,expected_revision,idempotency_key)
$$;
create function api.expire_publication_confirmations(batch_size integer default 100)
returns integer language sql security invoker set search_path='' as
$$select internal.expire_publication_confirmations(batch_size)$$;

revoke all on function internal.publication_fields_valid(text,text[]),
 internal.configure_publication_v2_for_actor(uuid,text,uuid,text,text,text[],text,text,text,text,timestamptz,bigint,uuid),
 internal.expire_publication_confirmations(integer),
 api.configure_publication_v2(uuid,text,uuid,text,text,text[],text,text,text,text,timestamptz,bigint,uuid),
 api.expire_publication_confirmations(integer) from public,anon,authenticated;
grant execute on function internal.configure_publication_v2_for_actor(uuid,text,uuid,text,text,text[],text,text,text,text,timestamptz,bigint,uuid),
 api.configure_publication_v2(uuid,text,uuid,text,text,text[],text,text,text,text,timestamptz,bigint,uuid)
 to authenticated;
grant execute on function internal.expire_publication_confirmations(integer),
 api.expire_publication_confirmations(integer) to service_role;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827125738_pub02_catalog_publication_model','greenfield',
 'PUB-02 private/listed/published, explicit publisher capability and expiring field confirmation');
notify pgrst,'reload schema';
