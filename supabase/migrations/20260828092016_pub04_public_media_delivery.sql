-- PUB-04 private upload, fail-closed processing queue and public delivery lookup.
-- No provider, secret, schedule or live activation is configured by this migration.
alter table core.public_media_assets add column size_bytes bigint check(size_bytes between 1 and 10485760);
alter table core.public_media_assets add column processing_started_at timestamptz;
alter table core.public_media_assets add column processing_attempts integer not null default 0 check(processing_attempts between 0 and 10);
alter table core.public_media_assets add column variant_object_key text;
alter table core.public_media_assets add constraint public_media_variant_object_check check(
 variant_object_key is null or variant_object_key~'^[0-9a-f-]{36}/[a-f0-9]{32}\.webp$');
alter table core.public_media_assets add constraint public_media_ready_object_check check(
 variant_state<>'ready' or variant_object_key is not null);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values
 ('public-media-source','public-media-source',false,10485760,array['image/jpeg','image/png','image/webp']),
 ('public-media-variants','public-media-variants',false,5242880,array['image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create function internal.stage_public_media_for_actor(target_club_id uuid,new_purpose text,new_content_type text,new_size_bytes bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();asset_id uuid:=gen_random_uuid();object_key text;
begin
 if actor_id is null or not internal.actor_has_capability(target_club_id,null,'publication.manage') then
  raise insufficient_privilege using message='not_found';end if;
 if new_purpose not in('partner_logo','club_profile','team_profile','editorial_hero')
  or new_content_type not in('image/jpeg','image/png','image/webp') or new_size_bytes not between 1 and 10485760
 then raise invalid_parameter_value using message='invalid_media';end if;
 object_key:=target_club_id::text||'/'||asset_id::text||'.upload';
 insert into core.public_media_assets(id,club_id,purpose,source_object_key,content_type,size_bytes,created_by)
 values(asset_id,target_club_id,new_purpose,object_key,new_content_type,new_size_bytes,actor_id);
 return jsonb_build_object('asset_id',asset_id,'bucket_id','public-media-source','object_key',object_key,'max_size_bytes',10485760);
end;$$;

create function internal.actor_can_upload_public_media(target_bucket text,target_key text)
returns boolean language sql stable security definer set search_path='' as $$
 select target_bucket='public-media-source' and exists(select 1 from core.public_media_assets asset
  where asset.source_object_key=target_key and asset.created_by=auth.uid() and asset.scan_state='pending'
   and asset.variant_state='pending' and asset.created_at>now()-interval '24 hours'
   and internal.actor_has_capability(asset.club_id,null,'publication.manage'));
$$;

create policy public_media_source_insert on storage.objects for insert to authenticated with check(
 bucket_id='public-media-source' and owner_id=(select auth.uid()::text)
 and internal.actor_can_upload_public_media(bucket_id,name));
create policy public_media_source_staged_delete on storage.objects for delete to authenticated using(
 bucket_id='public-media-source' and owner_id=(select auth.uid()::text)
 and internal.actor_can_upload_public_media(bucket_id,name));

create function internal.claim_public_media_batch(batch_size integer default 10)
returns table(asset_id uuid,club_id uuid,source_bucket text,source_object_key text,content_type text,purpose text,public_token text)
language plpgsql security definer set search_path='' as $$
begin
 if current_user not in('service_role','postgres') then raise insufficient_privilege using message='service_role_required';end if;
 if batch_size not between 1 and 25 then raise invalid_parameter_value;end if;
 return query with claimed as(
  select asset.id from core.public_media_assets asset join storage.objects object
   on object.bucket_id='public-media-source' and object.name=asset.source_object_key
  where asset.scan_state='pending' and asset.variant_state='pending' and asset.processing_attempts<10
   and (asset.processing_started_at is null or asset.processing_started_at<now()-interval '15 minutes')
   and (object.metadata->>'size')::bigint=asset.size_bytes
  order by asset.created_at,asset.id for update of asset skip locked limit batch_size
 ),updated as(
  update core.public_media_assets asset set processing_started_at=now(),processing_attempts=processing_attempts+1
  from claimed where asset.id=claimed.id returning asset.*
 ) select updated.id,updated.club_id,'public-media-source',updated.source_object_key,updated.content_type,updated.purpose,updated.public_token from updated;
end;$$;

create function internal.finish_public_media_processing(target_asset_id uuid,new_scan_state text,new_variant_state text,
 new_variant_object_key text,new_width integer,new_height integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare asset core.public_media_assets%rowtype;
begin
 if current_user not in('service_role','postgres') then raise insufficient_privilege using message='service_role_required';end if;
 if new_scan_state not in('clean','rejected') or new_variant_state not in('ready','failed','removed')
  or (new_variant_state='ready' and (new_scan_state<>'clean' or new_variant_object_key is null)) then raise invalid_parameter_value;end if;
 if new_variant_state='ready' and not exists(select 1 from storage.objects object where object.bucket_id='public-media-variants'
  and object.name=new_variant_object_key and object.metadata->>'mimetype'='image/webp') then raise check_violation using message='variant_missing';end if;
 update core.public_media_assets set scan_state=new_scan_state,variant_state=new_variant_state,
  variant_object_key=case when new_variant_state='ready' then new_variant_object_key end,width=new_width,height=new_height,
  ready_at=case when new_variant_state='ready' then now() end,removed_at=case when new_variant_state='removed' then now() end,
  processing_started_at=null,revision=revision+1 where id=target_asset_id returning * into asset;
 if asset.id is null then raise no_data_found using message='asset_not_found';end if;
 return jsonb_build_object('asset_id',asset.id,'scan_state',asset.scan_state,'variant_state',asset.variant_state);
end;$$;

create function internal.resolve_public_media(target_public_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare asset core.public_media_assets%rowtype;
begin
 if current_user not in('service_role','postgres') then raise insufficient_privilege using message='service_role_required';end if;
 select * into asset from core.public_media_assets item where item.public_token=target_public_token
  and item.scan_state='clean' and item.variant_state='ready' and item.removed_at is null;
 if asset.id is null then return jsonb_build_object('not_found',true);end if;
 return jsonb_build_object('bucket_id','public-media-variants','object_key',asset.variant_object_key,
  'content_type','image/webp','revision',asset.revision);
end;$$;

create function api.stage_public_media(club_id uuid,purpose text,content_type text,size_bytes bigint) returns jsonb
language sql security invoker set search_path='' as $$select internal.stage_public_media_for_actor(club_id,purpose,content_type,size_bytes)$$;
create function api.claim_public_media_batch(batch_size integer default 10) returns table(asset_id uuid,club_id uuid,source_bucket text,source_object_key text,content_type text,purpose text,public_token text)
language sql security invoker set search_path='' as $$select * from internal.claim_public_media_batch(batch_size)$$;
create function api.finish_public_media_processing(asset_id uuid,scan_state text,variant_state text,variant_object_key text,width integer,height integer) returns jsonb
language sql security invoker set search_path='' as $$select internal.finish_public_media_processing(asset_id,scan_state,variant_state,variant_object_key,width,height)$$;
create function api.resolve_public_media(public_token text) returns jsonb language sql stable security invoker set search_path='' as $$select internal.resolve_public_media(public_token)$$;

revoke all on function internal.stage_public_media_for_actor(uuid,text,text,bigint),internal.actor_can_upload_public_media(text,text),
 internal.claim_public_media_batch(integer),internal.finish_public_media_processing(uuid,text,text,text,integer,integer),internal.resolve_public_media(text),
 api.stage_public_media(uuid,text,text,bigint),api.claim_public_media_batch(integer),api.finish_public_media_processing(uuid,text,text,text,integer,integer),api.resolve_public_media(text)
from public,anon,authenticated;
grant execute on function internal.stage_public_media_for_actor(uuid,text,text,bigint),internal.actor_can_upload_public_media(text,text),api.stage_public_media(uuid,text,text,bigint) to authenticated;
grant execute on function internal.claim_public_media_batch(integer),internal.finish_public_media_processing(uuid,text,text,text,integer,integer),internal.resolve_public_media(text),
 api.claim_public_media_batch(integer),api.finish_public_media_processing(uuid,text,text,text,integer,integer),api.resolve_public_media(text) to service_role;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260828092016_pub04_public_media_delivery','greenfield','PUB-04 private public-media processing and delivery boundary');
notify pgrst,'reload schema';
