-- AUTH-07 versioned mandatory legal acknowledgement and separate optional marketing.

create table internal.legal_document_versions (
  document_type text not null check (document_type in ('terms','privacy')),
  version text not null check (version ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}(-[a-z0-9]+)?$'),
  public_url text not null check (public_url like 'https://%'),
  material_change boolean not null default true,
  active boolean not null default false,
  published_at timestamptz not null,
  created_at timestamptz not null default now(),
  primary key(document_type,version)
);
create unique index legal_document_versions_one_active
  on internal.legal_document_versions(document_type) where active;

create table core.legal_acceptances (
  profile_id uuid not null references core.profiles(id) on delete cascade,
  document_type text not null,
  document_version text not null,
  accepted_at timestamptz not null default now(),
  source text not null default 'app' check (source in ('app','web')),
  primary key(profile_id,document_type,document_version),
  foreign key(document_type,document_version)
    references internal.legal_document_versions(document_type,version)
);

create table core.communication_preferences (
  profile_id uuid primary key references core.profiles(id) on delete cascade,
  marketing_opt_in boolean not null default false,
  decided_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0)
);

alter table internal.legal_document_versions enable row level security;
alter table core.legal_acceptances enable row level security;
alter table core.communication_preferences enable row level security;
revoke all on table internal.legal_document_versions,core.legal_acceptances,
  core.communication_preferences from public,anon,authenticated;

insert into internal.legal_document_versions(
  document_type,version,public_url,material_change,active,published_at
) values
  ('terms','2026-08-24','https://teamzoneapp.se/villkor',true,true,'2026-08-24T00:00:00Z'),
  ('privacy','2026-08-24','https://teamzoneapp.se/integritet',true,true,'2026-08-24T00:00:00Z');

create function internal.get_legal_status_for_actor()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select jsonb_build_object(
    'terms_version',terms.version,'terms_url',terms.public_url,
    'terms_accepted',exists(select 1 from core.legal_acceptances acceptance
      where acceptance.profile_id=actor_id and acceptance.document_type='terms'
        and acceptance.document_version=terms.version),
    'privacy_version',privacy.version,'privacy_url',privacy.public_url,
    'privacy_accepted',exists(select 1 from core.legal_acceptances acceptance
      where acceptance.profile_id=actor_id and acceptance.document_type='privacy'
        and acceptance.document_version=privacy.version),
    'marketing_opt_in',coalesce(preference.marketing_opt_in,false)
  ) into result
  from internal.legal_document_versions terms
  cross join internal.legal_document_versions privacy
  left join core.communication_preferences preference on preference.profile_id=actor_id
  where terms.document_type='terms' and terms.active
    and privacy.document_type='privacy' and privacy.active;
  if result is null then raise invalid_parameter_value using message='legal_documents_unavailable'; end if;
  return result;
end
$$;

create function internal.accept_current_legal_for_actor(
  terms_version text,privacy_version text,marketing_opt_in boolean,idempotency_key uuid
)
returns void language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); current_terms text; current_privacy text; existing jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select version into current_terms from internal.legal_document_versions
    where document_type='terms' and active;
  select version into current_privacy from internal.legal_document_versions
    where document_type='privacy' and active;
  if terms_version is distinct from current_terms or privacy_version is distinct from current_privacy then
    raise serialization_failure using message='legal_version_changed';
  end if;
  select result into existing from internal.command_deduplication dedupe
    where dedupe.actor_profile_id=actor_id
      and dedupe.command_type='identity.legal.accept.v1'
      and dedupe.idempotency_key=accept_current_legal_for_actor.idempotency_key;
  if existing is not null then return; end if;
  insert into core.legal_acceptances(profile_id,document_type,document_version)
  values(actor_id,'terms',current_terms),(actor_id,'privacy',current_privacy)
  on conflict do nothing;
  insert into core.communication_preferences(profile_id,marketing_opt_in)
  values(actor_id,coalesce(marketing_opt_in,false))
  on conflict(profile_id) do update set marketing_opt_in=excluded.marketing_opt_in,
    decided_at=now(),revision=core.communication_preferences.revision+1;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'identity.legal.accept.v1',jsonb_build_object(
    'terms_version',current_terms,'privacy_version',current_privacy));
  insert into audit.command_events(actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
  values(actor_id,'identity.legal.accept.v1','profile',actor_id,1,jsonb_build_object(
    'terms_version',current_terms,'privacy_version',current_privacy,
    'marketing_opt_in',coalesce(marketing_opt_in,false)));
end
$$;

create function internal.set_marketing_preference_for_actor(
  marketing_opt_in boolean,idempotency_key uuid
)
returns void language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); existing jsonb; new_revision bigint;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select result into existing from internal.command_deduplication dedupe
    where dedupe.actor_profile_id=actor_id
      and dedupe.command_type='identity.marketing.preference.v1'
      and dedupe.idempotency_key=set_marketing_preference_for_actor.idempotency_key;
  if existing is not null then return; end if;
  insert into core.communication_preferences(profile_id,marketing_opt_in)
  values(actor_id,coalesce(marketing_opt_in,false))
  on conflict(profile_id) do update set marketing_opt_in=excluded.marketing_opt_in,
    decided_at=now(),revision=core.communication_preferences.revision+1
  returning revision into new_revision;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'identity.marketing.preference.v1',jsonb_build_object('revision',new_revision));
  insert into audit.command_events(actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
  values(actor_id,'identity.marketing.preference.v1','profile',actor_id,new_revision,
    jsonb_build_object('marketing_opt_in',coalesce(marketing_opt_in,false)));
end
$$;

create function api.get_legal_status()
returns jsonb language sql stable security invoker set search_path=''
as $$select internal.get_legal_status_for_actor()$$;
create function api.accept_current_legal(
  terms_version text,privacy_version text,marketing_opt_in boolean,idempotency_key uuid
)
returns void language sql security invoker set search_path=''
as $$select internal.accept_current_legal_for_actor(terms_version,privacy_version,marketing_opt_in,idempotency_key)$$;
create function api.set_marketing_preference(marketing_opt_in boolean,idempotency_key uuid)
returns void language sql security invoker set search_path=''
as $$select internal.set_marketing_preference_for_actor(marketing_opt_in,idempotency_key)$$;

revoke all on function internal.get_legal_status_for_actor(),
  internal.accept_current_legal_for_actor(text,text,boolean,uuid),
  internal.set_marketing_preference_for_actor(boolean,uuid),
  api.get_legal_status(),api.accept_current_legal(text,text,boolean,uuid),
  api.set_marketing_preference(boolean,uuid) from public,anon,authenticated;
grant execute on function internal.get_legal_status_for_actor(),
  internal.accept_current_legal_for_actor(text,text,boolean,uuid),
  internal.set_marketing_preference_for_actor(boolean,uuid),
  api.get_legal_status(),api.accept_current_legal(text,text,boolean,uuid),
  api.set_marketing_preference(boolean,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260824124115_auth07_legal_acceptance','greenfield','AUTH-07 versioned legal acknowledgement and optional marketing');
