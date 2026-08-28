-- PUB-05 automated domain claims and canonical routing. No DNS/TLS provisioning is performed.

create table internal.public_domain_runtime_state(
 singleton boolean primary key default true check(singleton),
 wildcard_dns_ready boolean not null default false check(wildcard_dns_ready=false),
 wildcard_tls_ready boolean not null default false check(wildcard_tls_ready=false),
 automatic_tenant_routing_ready boolean not null default false check(automatic_tenant_routing_ready=false),
 changed_at timestamptz not null default now(),revision bigint not null default 1 check(revision>0)
);
insert into internal.public_domain_runtime_state(singleton) values(true);

create table core.publication_domains(
 id uuid primary key default gen_random_uuid(),club_id uuid not null references core.clubs(id),
 kind text not null check(kind in('custom','teamzone_subdomain')),
 hostname text not null unique,state text not null default 'pending_verification'
  check(state in('pending_verification','verified','activating','active','failed','disabled')),
 commercial_state text not null default 'awaiting_entitlement'
  check(commercial_state in('awaiting_entitlement','approved','suspended')),
 verification_token_hash bytea not null check(octet_length(verification_token_hash)=32),
 verification_expires_at timestamptz not null,verified_at timestamptz,
 tls_state text not null default 'pending' check(tls_state in('pending','provisioning','ready','failed','revoked')),
 canonical boolean not null default false,provider_reference text,last_error_code text,
 created_by uuid not null references core.profiles(id),created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),revision bigint not null default 1 check(revision>0),
 unique(id,club_id),
 check(hostname=lower(hostname) and hostname~'^(?=.{4,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$'),
 check(hostname not in('teamzoneapp.se','www.teamzoneapp.se','app.teamzoneapp.se','public.teamzoneapp.se')),
 check(verification_expires_at<=created_at+interval '7 days'),
 check((state in('verified','activating','active') and verified_at is not null) or state not in('verified','activating','active')),
 check((state='active' and tls_state='ready') or state<>'active'),
 check(not canonical or state='active')
);
create unique index publication_domains_one_canonical_idx on core.publication_domains(club_id) where canonical;
create index publication_domains_state_idx on core.publication_domains(state,tls_state,updated_at,id);
create index publication_domains_club_idx on core.publication_domains(club_id,created_at desc,id);

create table audit.publication_domain_events(
 id uuid primary key default gen_random_uuid(),domain_id uuid not null,club_id uuid not null,
 action text not null check(action in('requested','commercial_approved','verified','activation_started','activated','failed','disabled','canonical_changed')),
 actor_profile_id uuid references core.profiles(id),actor_kind text not null check(actor_kind in('user','service')),
 metadata jsonb not null default '{}'::jsonb,created_at timestamptz not null default now(),
 foreign key(domain_id,club_id) references core.publication_domains(id,club_id)
);
create index publication_domain_events_domain_idx on audit.publication_domain_events(domain_id,created_at,id);
create index publication_domain_events_actor_idx on audit.publication_domain_events(actor_profile_id,created_at desc) where actor_profile_id is not null;

alter table internal.public_domain_runtime_state enable row level security;
alter table core.publication_domains enable row level security;
alter table audit.publication_domain_events enable row level security;
create policy public_domain_runtime_no_client_access on internal.public_domain_runtime_state for all to authenticated using(false) with check(false);
create policy publication_domains_no_client_access on core.publication_domains for all to authenticated using(false) with check(false);
create policy publication_domain_events_no_client_access on audit.publication_domain_events for all to authenticated using(false) with check(false);
revoke all on table internal.public_domain_runtime_state,core.publication_domains,audit.publication_domain_events from public,anon,authenticated;

create function internal.normalize_public_hostname(raw_hostname text)
returns text language sql immutable set search_path='' as $$
 select lower(rtrim(split_part(btrim(coalesce(raw_hostname,'')),':',1),'.'))
$$;

create function internal.request_publication_domain_for_actor(target_club_id uuid,new_kind text,raw_hostname text,
 idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();hostname_value text:=internal.normalize_public_hostname(raw_hostname);
 club_setting core.club_publication_settings%rowtype;runtime internal.public_domain_runtime_state%rowtype;
 domain_id uuid;verification_token text:=replace(gen_random_uuid()::text,'-','');existing jsonb;
begin
 if actor_id is null or not internal.actor_has_capability(target_club_id,null,'publication.manage')
 then raise insufficient_privilege using message='not_found';end if;
 select * into club_setting from core.club_publication_settings where club_id=target_club_id;
 if club_setting.mode<>'published' or club_setting.confirmation_id is null then raise check_violation using message='club_not_published';end if;
 if new_kind not in('custom','teamzone_subdomain') or hostname_value!~'^(?=.{4,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$'
  or hostname_value in('teamzoneapp.se','www.teamzoneapp.se','app.teamzoneapp.se','public.teamzoneapp.se')
 then raise invalid_parameter_value using message='invalid_hostname';end if;
 if new_kind='teamzone_subdomain' then
  select * into runtime from internal.public_domain_runtime_state where singleton;
  if not(runtime.wildcard_dns_ready and runtime.wildcard_tls_ready and runtime.automatic_tenant_routing_ready)
  then raise feature_not_supported using message='wildcard_domains_not_ready';end if;
  if hostname_value<>club_setting.slug||'.teamzoneapp.se' then raise invalid_parameter_value using message='invalid_subdomain';end if;
 else
  if hostname_value like '%.teamzoneapp.se' then raise invalid_parameter_value using message='reserved_hostname';end if;
 end if;
 select result into existing from internal.command_deduplication d where d.actor_profile_id=actor_id
  and d.command_type='publication.domain.request.v1' and d.idempotency_key=request_publication_domain_for_actor.idempotency_key;
 if existing is not null then return existing||jsonb_build_object('verification_token',null);end if;
 insert into core.publication_domains(club_id,kind,hostname,verification_token_hash,verification_expires_at,created_by)
 values(target_club_id,new_kind,hostname_value,extensions.digest(verification_token,'sha256'),now()+interval '72 hours',actor_id)
 returning id into domain_id;
 existing:=jsonb_build_object('domain_id',domain_id,'hostname',hostname_value,'state','pending_verification',
  'commercial_state','awaiting_entitlement','verification_record','_teamzone-verify.'||hostname_value,
  'verification_token',verification_token,'routing_target','public.teamzoneapp.se');
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'publication.domain.request.v1',existing-'verification_token');
 insert into audit.publication_domain_events(domain_id,club_id,action,actor_profile_id,actor_kind)
 values(domain_id,target_club_id,'requested',actor_id,'user');
 return existing;
exception when unique_violation then raise unique_violation using message='hostname_unavailable';
end;$$;

create function internal.approve_publication_domain_commercial(target_domain_id uuid,approved boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare domain_row core.publication_domains%rowtype;
begin
 update core.publication_domains set commercial_state=case when approved then 'approved' else 'suspended' end,
  updated_at=now(),revision=revision+1 where id=target_domain_id returning * into domain_row;
 if domain_row.id is null then raise no_data_found using message='domain_not_found';end if;
 insert into audit.publication_domain_events(domain_id,club_id,action,actor_kind,metadata)
 values(domain_row.id,domain_row.club_id,'commercial_approved','service',jsonb_build_object('approved',approved));
 return jsonb_build_object('domain_id',domain_row.id,'commercial_state',domain_row.commercial_state,'revision',domain_row.revision);
end;$$;

create function internal.verify_publication_domain(target_domain_id uuid,observed_verification_token text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare domain_row core.publication_domains%rowtype;
begin
 select * into domain_row from core.publication_domains where id=target_domain_id for update;
 if domain_row.id is null then raise no_data_found using message='domain_not_found';end if;
 if domain_row.state<>'pending_verification' or domain_row.commercial_state<>'approved'
  or observed_verification_token is null or observed_verification_token!~'^[a-f0-9]{32}$'
  or domain_row.verification_expires_at<=now() or extensions.digest(observed_verification_token,'sha256')<>domain_row.verification_token_hash
 then raise check_violation using message='verification_failed';end if;
 update core.publication_domains set state='verified',verified_at=now(),updated_at=now(),revision=revision+1
 where id=domain_row.id returning * into domain_row;
 insert into audit.publication_domain_events(domain_id,club_id,action,actor_kind)
 values(domain_row.id,domain_row.club_id,'verified','service');
 return jsonb_build_object('domain_id',domain_row.id,'state',domain_row.state,'revision',domain_row.revision);
end;$$;

create function internal.transition_publication_domain(target_domain_id uuid,new_state text,new_tls_state text,
 new_provider_reference text,new_error_code text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare domain_row core.publication_domains%rowtype;action_value text;
begin
 select * into domain_row from core.publication_domains where id=target_domain_id for update;
 if domain_row.id is null then raise no_data_found using message='domain_not_found';end if;
 if (new_state='activating' and(domain_row.state<>'verified' or new_tls_state<>'provisioning'))
  or(new_state='active' and(domain_row.state<>'activating' or new_tls_state<>'ready' or domain_row.commercial_state<>'approved'))
  or(new_state='failed' and new_tls_state<>'failed') or new_state not in('activating','active','failed','disabled')
 then raise check_violation using message='invalid_transition';end if;
 action_value:=case new_state when 'activating' then 'activation_started' when 'active' then 'activated'
  when 'disabled' then 'disabled' else 'failed' end;
 update core.publication_domains set state=new_state,tls_state=new_tls_state,provider_reference=nullif(btrim(new_provider_reference),''),
  last_error_code=nullif(btrim(new_error_code),''),canonical=case when new_state='active' then canonical else false end,
  updated_at=now(),revision=revision+1 where id=domain_row.id returning * into domain_row;
 insert into audit.publication_domain_events(domain_id,club_id,action,actor_kind,metadata)
 values(domain_row.id,domain_row.club_id,action_value,'service',jsonb_build_object('tls_state',new_tls_state,'error_code',new_error_code));
 return jsonb_build_object('domain_id',domain_row.id,'state',domain_row.state,'tls_state',domain_row.tls_state,'revision',domain_row.revision);
end;$$;

create function internal.set_canonical_publication_domain_for_actor(target_club_id uuid,target_domain_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();domain_row core.publication_domains%rowtype;
begin
 if actor_id is null or not internal.actor_has_capability(target_club_id,null,'publication.manage')
 then raise insufficient_privilege using message='not_found';end if;
 if target_domain_id is null then
  update core.publication_domains set canonical=false,updated_at=now(),revision=revision+1 where club_id=target_club_id and canonical;
  return jsonb_build_object('canonical','path');
 end if;
 select * into domain_row from core.publication_domains where id=target_domain_id and club_id=target_club_id and state='active' for update;
 if domain_row.id is null then raise insufficient_privilege using message='not_found';end if;
 update core.publication_domains set canonical=false,updated_at=now(),revision=revision+1 where club_id=target_club_id and canonical;
 update core.publication_domains set canonical=true,updated_at=now(),revision=revision+1 where id=domain_row.id;
 insert into audit.publication_domain_events(domain_id,club_id,action,actor_profile_id,actor_kind)
 values(domain_row.id,target_club_id,'canonical_changed',actor_id,'user');
 return jsonb_build_object('canonical',domain_row.hostname);
end;$$;

create function internal.resolve_public_hostname(raw_hostname text,request_path text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare hostname_value text:=internal.normalize_public_hostname(raw_hostname);domain_row core.publication_domains%rowtype;
 club_setting core.club_publication_settings%rowtype;canonical_domain core.publication_domains%rowtype;
 clean_path text;first_segment text;remaining_path text;
begin
 if request_path is null or request_path!~'^/' or request_path~'[?#]' or length(request_path)>2048
 then raise invalid_parameter_value using message='invalid_path';end if;
 clean_path:=case when request_path='/' then '' else request_path end;
 if hostname_value in('teamzoneapp.se','www.teamzoneapp.se','public.teamzoneapp.se') then
  first_segment:=split_part(trim(leading '/' from request_path),'/',1);
  select * into club_setting from core.club_publication_settings where slug=first_segment and mode='published';
  if club_setting.club_id is not null then
   select * into canonical_domain from core.publication_domains where club_id=club_setting.club_id and canonical
    and state='active' and commercial_state='approved';
   if canonical_domain.id is not null then
    remaining_path:=substring(request_path from length(first_segment)+2);
    return jsonb_build_object('mode','redirect','status',308,'location','https://'||canonical_domain.hostname||
     case when remaining_path in('', '/') then '/' else remaining_path end);
   end if;
  end if;
  if hostname_value='www.teamzoneapp.se' then
   return jsonb_build_object('mode','redirect','status',308,'location','https://teamzoneapp.se'||request_path);
  end if;
  return jsonb_build_object('mode','path','hostname',hostname_value);
 end if;
 select * into domain_row from core.publication_domains where hostname=hostname_value and state='active'
  and tls_state='ready' and commercial_state='approved';
 if domain_row.id is null then return jsonb_build_object('not_found',true);end if;
 select * into club_setting from core.club_publication_settings where club_id=domain_row.club_id and mode='published';
 if club_setting.club_id is null then return jsonb_build_object('not_found',true);end if;
 select * into canonical_domain from core.publication_domains where club_id=domain_row.club_id and canonical
  and state='active' and commercial_state='approved';
 if canonical_domain.id is not null and canonical_domain.id<>domain_row.id then
  return jsonb_build_object('mode','redirect','status',308,'location','https://'||canonical_domain.hostname||clean_path);
 end if;
 if canonical_domain.id is null then
  return jsonb_build_object('mode','redirect','status',308,'location','https://teamzoneapp.se/'||club_setting.slug||clean_path);
 end if;
 return jsonb_build_object('mode','rewrite','club_slug',club_setting.slug,'internal_path','/'||club_setting.slug||clean_path,
  'canonical_origin','https://'||domain_row.hostname);
end;$$;

create function api.request_publication_domain(club_id uuid,kind text,hostname text,idempotency_key uuid)
returns jsonb language sql security invoker set search_path='' as
$$select internal.request_publication_domain_for_actor(club_id,kind,hostname,idempotency_key)$$;
create function api.set_canonical_publication_domain(club_id uuid,domain_id uuid)
returns jsonb language sql security invoker set search_path='' as
$$select internal.set_canonical_publication_domain_for_actor(club_id,domain_id)$$;
create function api.resolve_public_hostname(hostname text,path text) returns jsonb language sql stable security invoker set search_path='' as
$$select internal.resolve_public_hostname(hostname,path)$$;

revoke all on function internal.normalize_public_hostname(text),internal.request_publication_domain_for_actor(uuid,text,text,uuid),
 internal.approve_publication_domain_commercial(uuid,boolean),internal.verify_publication_domain(uuid,text),
 internal.transition_publication_domain(uuid,text,text,text,text),internal.set_canonical_publication_domain_for_actor(uuid,uuid),
 internal.resolve_public_hostname(text,text),api.request_publication_domain(uuid,text,text,uuid),
 api.set_canonical_publication_domain(uuid,uuid),api.resolve_public_hostname(text,text) from public,anon,authenticated;
grant execute on function internal.request_publication_domain_for_actor(uuid,text,text,uuid),
 internal.set_canonical_publication_domain_for_actor(uuid,uuid),api.request_publication_domain(uuid,text,text,uuid),
 api.set_canonical_publication_domain(uuid,uuid) to authenticated;
grant execute on function internal.approve_publication_domain_commercial(uuid,boolean),internal.verify_publication_domain(uuid,text),
 internal.transition_publication_domain(uuid,text,text,text,text),internal.resolve_public_hostname(text,text),
 api.resolve_public_hostname(text,text) to service_role;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827135707_pub05_automated_domain_routing','greenfield','PUB-05 ownership verification, TLS state and automatic canonical routing; wildcard disabled');
notify pgrst,'reload schema';
