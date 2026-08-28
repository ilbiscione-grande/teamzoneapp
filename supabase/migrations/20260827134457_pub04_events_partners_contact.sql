-- PUB-04 explicit event fields, safe partner media and public contact closure.
-- Runtime activation and hosted rollout remain separate decisions.

create table core.public_media_assets(
 id uuid primary key default gen_random_uuid(),club_id uuid not null references core.clubs(id),
 public_token text not null unique default replace(gen_random_uuid()::text,'-',''),
 purpose text not null check(purpose in('partner_logo','club_profile','team_profile','editorial_hero')),
 source_object_key text not null,content_type text not null check(content_type in('image/avif','image/jpeg','image/png','image/webp')),
 scan_state text not null default 'pending' check(scan_state in('pending','clean','rejected')),
 variant_state text not null default 'pending' check(variant_state in('pending','ready','failed','removed')),
 width integer,height integer,created_by uuid not null references core.profiles(id),created_at timestamptz not null default now(),
 ready_at timestamptz,removed_at timestamptz,revision bigint not null default 1 check(revision>0),
 unique(id,club_id),check(source_object_key~'^[A-Za-z0-9/_-]+\.[A-Za-z0-9]+$' and length(source_object_key)<=500),
 check((variant_state='ready')=(ready_at is not null) or variant_state<>'ready'),
 check((variant_state='removed')=(removed_at is not null) or variant_state<>'removed'),
 check(width is null or width between 1 and 4096),check(height is null or height between 1 and 4096)
);
create index public_media_assets_club_state_idx on core.public_media_assets(club_id,variant_state,created_at desc);

create table core.public_partners(
 id uuid primary key default gen_random_uuid(),club_id uuid not null references core.clubs(id),
 name text not null,website_url text,logo_asset_id uuid,state text not null default 'draft'
  check(state in('draft','published','unpublished')),
 sort_order integer not null default 0 check(sort_order between 0 and 10000),
 created_by uuid not null references core.profiles(id),updated_by uuid not null references core.profiles(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 published_at timestamptz,unpublished_at timestamptz,revision bigint not null default 1 check(revision>0),
 unique(id,club_id),foreign key(logo_asset_id,club_id) references core.public_media_assets(id,club_id),
 check(length(btrim(name)) between 1 and 120),
 check(website_url is null or(website_url~'^https://[A-Za-z0-9]' and length(website_url)<=1000)),
 check((state='published')=(published_at is not null) or state<>'published')
);
create index public_partners_club_state_idx on core.public_partners(club_id,state,sort_order,id);

create table core.event_publication_settings(
 event_id uuid primary key,club_id uuid not null,team_id uuid not null,
 state text not null default 'private' check(state in('private','published')),
 public_title text,publish_location boolean not null default false,
 changed_by uuid not null references core.profiles(id),changed_at timestamptz not null default now(),
 revision bigint not null default 1 check(revision>0),unique(event_id,club_id),
 foreign key(event_id,club_id,team_id) references core.events(id,club_id,owning_team_id),
 check(public_title is null or length(btrim(public_title)) between 1 and 160)
);
create index event_publication_settings_club_state_idx on core.event_publication_settings(club_id,state,team_id,event_id);

create table public_api.partner_projections(
 public_id uuid primary key,club_public_id uuid not null references public_api.club_projections(public_id) on delete cascade,
 name text not null,website_url text,logo_media_path text,sort_order integer not null,
 source_revision bigint not null check(source_revision>0),projected_at timestamptz not null,
 check(length(btrim(name)) between 1 and 120),
 check(website_url is null or website_url~'^https://[A-Za-z0-9]'),
 check(logo_media_path is null or logo_media_path~'^/media/public/[a-f0-9]{32}$')
);
create index partner_projections_club_idx on public_api.partner_projections(club_public_id,sort_order,public_id);

alter table core.public_media_assets enable row level security;
alter table core.public_partners enable row level security;
alter table core.event_publication_settings enable row level security;
alter table public_api.partner_projections enable row level security;
create policy public_media_assets_no_client_access on core.public_media_assets for all to authenticated using(false) with check(false);
create policy public_partners_no_client_access on core.public_partners for all to authenticated using(false) with check(false);
create policy event_publication_settings_no_client_access on core.event_publication_settings for all to authenticated using(false) with check(false);
create policy partner_projections_no_client_access on public_api.partner_projections for all to authenticated using(false) with check(false);
revoke all on table core.public_media_assets,core.public_partners,core.event_publication_settings,
 public_api.partner_projections from public,anon,authenticated;

create function internal.configure_event_publication_for_actor(target_event_id uuid,new_state text,
 new_public_title text,new_publish_location boolean,expected_revision bigint,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();event_row core.events%rowtype;setting core.event_publication_settings%rowtype;
 team_setting core.team_publication_settings%rowtype;club_setting core.club_publication_settings%rowtype;
 location_name text;existing jsonb;new_revision bigint;
begin
 select * into event_row from core.events where id=target_event_id for update;
 if actor_id is null or event_row.id is null or not internal.actor_has_capability(event_row.club_id,event_row.owning_team_id,'publication.manage')
 then raise insufficient_privilege using message='not_found';end if;
 if new_state not in('private','published') or(new_public_title is not null and length(btrim(new_public_title)) not between 1 and 160)
 then raise invalid_parameter_value using message='invalid_publication';end if;
 select result into existing from internal.command_deduplication d where d.actor_profile_id=actor_id
  and d.command_type='publication.event.configure.v1' and d.idempotency_key=configure_event_publication_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 select * into setting from core.event_publication_settings where event_id=target_event_id for update;
 if coalesce(setting.revision,0)<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 select * into team_setting from core.team_publication_settings where team_id=event_row.owning_team_id;
 select * into club_setting from core.club_publication_settings where club_id=event_row.club_id;
 if new_state='published' then
  if event_row.state not in('scheduled','completed') or team_setting.mode<>'published' or team_setting.confirmation_id is null
  then raise check_violation using message='event_not_publishable';end if;
 end if;
 insert into core.event_publication_settings(event_id,club_id,team_id,state,public_title,publish_location,changed_by)
 values(event_row.id,event_row.club_id,event_row.owning_team_id,new_state,nullif(btrim(new_public_title),''),new_publish_location,actor_id)
 on conflict(event_id) do update set state=excluded.state,public_title=excluded.public_title,
  publish_location=excluded.publish_location,changed_by=actor_id,changed_at=now(),revision=core.event_publication_settings.revision+1
 returning revision into new_revision;
 if new_state='published' then
  if new_publish_location then select name into location_name from core.event_locations where id=event_row.location_id;end if;
  insert into public_api.event_projections(public_id,team_public_id,starts_at,event_type,title,location_name,source_revision,projected_at)
  values(event_row.id,team_setting.public_id,event_row.starts_at,event_row.event_type,
   coalesce(nullif(btrim(new_public_title),''),event_row.title),location_name,new_revision,now())
  on conflict(public_id) do update set team_public_id=excluded.team_public_id,starts_at=excluded.starts_at,
   event_type=excluded.event_type,title=excluded.title,location_name=excluded.location_name,
   source_revision=excluded.source_revision,projected_at=excluded.projected_at;
 else delete from public_api.event_projections where public_id=event_row.id;end if;
 insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,requested_revision,action,affected_paths,created_by)
 values(event_row.club_id,'event',event_row.id,new_revision,'invalidate',
  case when club_setting.slug is null or team_setting.slug is null then array[]::text[]
   else array['/'||club_setting.slug,'/'||club_setting.slug||'/'||team_setting.slug] end,actor_id);
 existing:=jsonb_build_object('event_id',event_row.id,'state',new_state,'revision',new_revision,
  'published_fields',array['title','starts_at','event_type']||case when new_publish_location then array['location_name'] else array[]::text[] end);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'publication.event.configure.v1',existing);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(event_row.club_id,actor_id,'publication.event.configure.v1','event',event_row.id,new_revision,
  jsonb_build_object('state',new_state,'publish_location',new_publish_location));
 return existing;
end;$$;

create function internal.save_public_partner_for_actor(target_club_id uuid,target_partner_id uuid,new_name text,
 new_website_url text,new_logo_asset_id uuid,new_state text,new_sort_order integer,expected_revision bigint,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();partner core.public_partners%rowtype;club_setting core.club_publication_settings%rowtype;
 asset core.public_media_assets%rowtype;existing jsonb;partner_id uuid;new_revision bigint;
begin
 if actor_id is null or not internal.actor_has_capability(target_club_id,null,'publication.manage')
 then raise insufficient_privilege using message='not_found';end if;
 if length(btrim(coalesce(new_name,''))) not between 1 and 120 or new_state not in('draft','published','unpublished')
  or new_sort_order not between 0 and 10000 or(new_website_url is not null and(new_website_url!~'^https://[A-Za-z0-9]' or length(new_website_url)>1000))
 then raise invalid_parameter_value using message='invalid_partner';end if;
 select result into existing from internal.command_deduplication d where d.actor_profile_id=actor_id
  and d.command_type='publication.partner.save.v1' and d.idempotency_key=save_public_partner_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 if new_logo_asset_id is not null then
  select * into asset from core.public_media_assets where id=new_logo_asset_id and club_id=target_club_id;
  if asset.id is null or asset.purpose<>'partner_logo' or asset.scan_state<>'clean' or asset.variant_state<>'ready'
  then raise check_violation using message='media_not_publishable';end if;
 end if;
 select * into club_setting from core.club_publication_settings where club_id=target_club_id;
 if new_state='published' then
  if club_setting.mode<>'published' or club_setting.confirmation_id is null then raise check_violation using message='club_not_published';end if;
 end if;
 if target_partner_id is null then
  insert into core.public_partners(club_id,name,website_url,logo_asset_id,state,sort_order,created_by,updated_by,published_at,unpublished_at)
  values(target_club_id,btrim(new_name),nullif(btrim(new_website_url),''),new_logo_asset_id,new_state,new_sort_order,actor_id,actor_id,
   case when new_state='published' then now() end,case when new_state='unpublished' then now() end)
  returning id,revision into partner_id,new_revision;
 else
  select * into partner from core.public_partners where id=target_partner_id and club_id=target_club_id for update;
  if partner.id is null then raise insufficient_privilege using message='not_found';end if;
  if partner.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
  update core.public_partners set name=btrim(new_name),website_url=nullif(btrim(new_website_url),''),logo_asset_id=new_logo_asset_id,
   state=new_state,sort_order=new_sort_order,updated_by=actor_id,updated_at=now(),
   published_at=case when new_state='published' then coalesce(published_at,now()) else published_at end,
   unpublished_at=case when new_state='unpublished' then now() else null end,revision=revision+1 where id=partner.id
  returning id,revision into partner_id,new_revision;
 end if;
 if new_state='published' then
  insert into public_api.partner_projections(public_id,club_public_id,name,website_url,logo_media_path,sort_order,source_revision,projected_at)
  values(partner_id,club_setting.public_id,btrim(new_name),nullif(btrim(new_website_url),''),
   case when asset.id is not null then '/media/public/'||asset.public_token end,new_sort_order,new_revision,now())
  on conflict(public_id) do update set name=excluded.name,website_url=excluded.website_url,logo_media_path=excluded.logo_media_path,
   sort_order=excluded.sort_order,source_revision=excluded.source_revision,projected_at=excluded.projected_at;
 else delete from public_api.partner_projections where public_id=partner_id;end if;
 insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,requested_revision,action,affected_paths,created_by)
 values(target_club_id,'publication',partner_id,new_revision,'invalidate',
  case when club_setting.slug is null then array[]::text[] else array['/'||club_setting.slug] end,actor_id);
 existing:=jsonb_build_object('partner_id',partner_id,'state',new_state,'revision',new_revision,
  'media_status',case when asset.id is null then 'not_configured' else 'ready' end);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'publication.partner.save.v1',existing);
 return existing;
end;$$;

create function internal.register_public_media_asset(target_club_id uuid,new_purpose text,new_source_object_key text,
 new_content_type text,new_created_by uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare asset_id uuid;
begin
 if new_purpose not in('partner_logo','club_profile','team_profile','editorial_hero') then raise invalid_parameter_value;end if;
 insert into core.public_media_assets(club_id,purpose,source_object_key,content_type,created_by)
 values(target_club_id,new_purpose,new_source_object_key,new_content_type,new_created_by) returning id into asset_id;
 return asset_id;
end;$$;

create function internal.finish_public_media_variant(target_asset_id uuid,is_clean boolean,variant_ready boolean,
 new_width integer,new_height integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare asset core.public_media_assets%rowtype;
begin
 update core.public_media_assets set scan_state=case when is_clean then 'clean' else 'rejected' end,
  variant_state=case when is_clean and variant_ready then 'ready' when is_clean then 'failed' else 'removed' end,
  width=new_width,height=new_height,ready_at=case when is_clean and variant_ready then now() end,
  removed_at=case when not is_clean then now() end,revision=revision+1
 where id=target_asset_id returning * into asset;
 if asset.id is null then raise no_data_found using message='asset_not_found';end if;
 return jsonb_build_object('asset_id',asset.id,'scan_state',asset.scan_state,'variant_state',asset.variant_state);
end;$$;

create or replace function internal.public_get_club(club_slug text,ip_sha256_hex text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb;club public_api.club_projections%rowtype;result jsonb;
begin
 if not internal.public_runtime_enabled() then return jsonb_build_object('available',false);end if;
 rate:=internal.consume_public_rate_limit(ip_sha256_hex,'read',null);
 if not(rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited';end if;
 select * into club from public_api.club_projections where slug=lower(btrim(club_slug)) and visibility='published';
 if club.public_id is null then return jsonb_build_object('not_found',true);end if;
 result:=jsonb_build_object('id',club.public_id,'slug',club.slug,'name',club.name,'locality',club.locality,
  'description',club.description,'profile_media_path',club.profile_media_path,'official',club.official,
  'teams',coalesce((select jsonb_agg(jsonb_build_object('id',team.public_id,'slug',team.slug,'name',team.name,'age_class',team.age_class)
   order by lower(team.name),team.public_id) from public_api.team_projections team where team.club_public_id=club.public_id and team.visibility='published'),'[]'::jsonb),
  'partners',coalesce((select jsonb_agg(jsonb_build_object('id',partner.public_id,'name',partner.name,'website_url',partner.website_url,
   'logo_media_path',partner.logo_media_path) order by partner.sort_order,partner.public_id)
   from public_api.partner_projections partner where partner.club_public_id=club.public_id),'[]'::jsonb));
 return result;
end;$$;

create function internal.public_list_club_events(target_club_id uuid,ip_sha256_hex text,page_limit integer default 20)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb;result jsonb;
begin
 if not internal.public_runtime_enabled() then return jsonb_build_object('available',false,'items','[]'::jsonb);end if;
 if page_limit not between 1 and 20 then raise invalid_parameter_value using message='invalid_request';end if;
 rate:=internal.consume_public_rate_limit(ip_sha256_hex,'read',null);
 if not(rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',page.public_id,'team_slug',page.slug,'team_name',page.name,
  'starts_at',page.starts_at,'event_type',page.event_type,'title',page.title,'location_name',page.location_name)
  order by page.starts_at,page.public_id),'[]'::jsonb) into result
 from(select event.*,team.slug,team.name from public_api.event_projections event
  join public_api.team_projections team on team.public_id=event.team_public_id
  where team.club_public_id=target_club_id and team.visibility='published'
   and event.starts_at>=now()-interval '30 days' and event.starts_at<now()+interval '180 days'
  order by event.starts_at,event.public_id limit page_limit) page;
 return jsonb_build_object('available',true,'items',result,'cache_control','no-store');
end;$$;

create or replace function internal.public_submit_contact(target_club_public_id uuid,new_sender_name text,
 new_sender_email text,new_subject text,new_message_body text,ip_sha256_hex text,captcha_verified boolean,
 captcha_assertion_sha256_hex text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb;target_club_id uuid;submission_id uuid;
begin
 if not internal.public_runtime_enabled() then return jsonb_build_object('accepted',false,'code','unavailable');end if;
 if captcha_verified is not true or captcha_assertion_sha256_hex!~'^[0-9a-fA-F]{64}$'
  or length(btrim(coalesce(new_sender_name,''))) not between 2 and 120
  or length(coalesce(new_sender_email,'')) not between 3 and 254
  or new_sender_email!~*'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  or length(btrim(coalesce(new_subject,''))) not between 2 and 160
  or length(btrim(coalesce(new_message_body,''))) not between 2 and 2000
 then raise invalid_parameter_value using message='invalid_request';end if;
 select setting.club_id into target_club_id from core.club_publication_settings setting
  join core.publication_confirmations confirmation on confirmation.id=setting.confirmation_id
  join public_api.club_projections projection on projection.public_id=setting.public_id
  where setting.public_id=target_club_public_id and setting.mode='published'
   and confirmation.state='active' and confirmation.expires_at>now();
 -- Unknown, unpublished and expired clubs deliberately get the same accepted response.
 if target_club_id is null then return jsonb_build_object('accepted',true);end if;
 rate:=internal.consume_public_rate_limit(ip_sha256_hex,'contact',target_club_public_id);
 if not(rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited';end if;
 insert into internal.public_contact_submissions(club_id,sender_name,sender_email,subject,message_body,captcha_assertion_hash)
 values(target_club_id,btrim(new_sender_name),lower(btrim(new_sender_email)),btrim(new_subject),
  btrim(new_message_body),decode(lower(captcha_assertion_sha256_hex),'hex')) returning public_id into submission_id;
 return jsonb_build_object('accepted',true,'reference',submission_id);
end;$$;

create function api.configure_event_publication(event_id uuid,state text,public_title text,publish_location boolean,
 expected_revision bigint,idempotency_key uuid) returns jsonb language sql security invoker set search_path='' as
$$select internal.configure_event_publication_for_actor(event_id,state,public_title,publish_location,expected_revision,idempotency_key)$$;
create function api.save_public_partner(club_id uuid,partner_id uuid,name text,website_url text,logo_asset_id uuid,state text,
 sort_order integer,expected_revision bigint,idempotency_key uuid) returns jsonb language sql security invoker set search_path='' as
$$select internal.save_public_partner_for_actor(club_id,partner_id,name,website_url,logo_asset_id,state,sort_order,expected_revision,idempotency_key)$$;
create function api.public_list_club_events(club_id uuid,ip_hash text,page_limit integer default 20)
returns jsonb language sql security invoker set search_path='' as
$$select internal.public_list_club_events(club_id,ip_hash,page_limit)$$;

revoke all on function internal.configure_event_publication_for_actor(uuid,text,text,boolean,bigint,uuid),
 internal.save_public_partner_for_actor(uuid,uuid,text,text,uuid,text,integer,bigint,uuid),
 internal.register_public_media_asset(uuid,text,text,text,uuid),internal.finish_public_media_variant(uuid,boolean,boolean,integer,integer),
 internal.public_list_club_events(uuid,text,integer),internal.public_submit_contact(uuid,text,text,text,text,text,boolean,text),
 api.configure_event_publication(uuid,text,text,boolean,bigint,uuid),
 api.save_public_partner(uuid,uuid,text,text,uuid,text,integer,bigint,uuid),api.public_list_club_events(uuid,text,integer)
 from public,anon,authenticated;
grant execute on function internal.configure_event_publication_for_actor(uuid,text,text,boolean,bigint,uuid),
 internal.save_public_partner_for_actor(uuid,uuid,text,text,uuid,text,integer,bigint,uuid),
 api.configure_event_publication(uuid,text,text,boolean,bigint,uuid),
 api.save_public_partner(uuid,uuid,text,text,uuid,text,integer,bigint,uuid) to authenticated;
grant execute on function internal.register_public_media_asset(uuid,text,text,text,uuid),
 internal.finish_public_media_variant(uuid,boolean,boolean,integer,integer),
 internal.public_list_club_events(uuid,text,integer),internal.public_submit_contact(uuid,text,text,text,text,text,boolean,text),
 api.public_list_club_events(uuid,text,integer) to service_role;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827134457_pub04_events_partners_contact','greenfield','PUB-04 explicit event fields, safe partner media and contact closure');
notify pgrst,'reload schema';
