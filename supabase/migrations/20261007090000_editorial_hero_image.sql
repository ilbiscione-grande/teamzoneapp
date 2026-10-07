-- One hero image per news article, uploaded through the existing private
-- public-media pipeline (purpose 'editorial_hero'). The image is only public
-- once public-media-worker has decoded it, removed all metadata (such as GPS
-- position), scaled it to at most 2048 px and stored a new WebP variant.
-- The article keeps a reference and an alt text; the public projection gets
-- the opaque /media/public/<token> path when the variant is ready, also if
-- processing finishes after the article was published.

alter table core.editorial_articles
 add column if not exists hero_asset_id uuid,
 add column if not exists hero_alt text
  check(hero_alt is null or length(btrim(hero_alt)) between 1 and 200);
alter table core.editorial_articles
 add constraint editorial_articles_hero_asset_fk foreign key(hero_asset_id,club_id)
  references core.public_media_assets(id,club_id);
create index if not exists editorial_articles_hero_asset_idx on core.editorial_articles(hero_asset_id)
 where hero_asset_id is not null;
alter table public_api.content_projections add column if not exists media_alt text
 check(media_alt is null or length(media_alt)<=200);

-- The public address of a ready, clean hero image; null otherwise.
create or replace function internal.editorial_hero_path(target_article_id uuid)
returns text language sql stable security definer set search_path='' as $$
 select '/media/public/'||asset.public_token from core.editorial_articles article
 join core.public_media_assets asset on asset.id=article.hero_asset_id and asset.club_id=article.club_id
 where article.id=target_article_id and asset.scan_state='clean' and asset.variant_state='ready'
  and asset.removed_at is null
$$;

create or replace function internal.editorial_hero_state(target_asset_id uuid)
returns text language sql stable security definer set search_path='' as $$
 select case
  when target_asset_id is null then 'none'
  when asset.removed_at is not null or asset.variant_state='removed' or asset.scan_state='rejected' then 'rejected'
  when asset.variant_state='ready' and asset.scan_state='clean' then 'ready'
  when asset.variant_state='failed' then 'failed'
  else 'pending' end
 from (select 1) one left join core.public_media_assets asset on asset.id=target_asset_id
$$;

-- media_status now reports the hero image (none, pending, ready, failed,
-- rejected) instead of the fixed 'not_configured'.
create or replace function internal.editorial_snapshot(article core.editorial_articles)
returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('id',article.id,'slug',article.slug,'title',article.title,
  'summary',article.summary,'body_blocks',article.body_blocks,'state',article.state,
  'publish_at',article.publish_at,'published_at',article.published_at,
  'author_label',article.author_label,'publish_to_club',article.publish_to_club,
  'media_status',internal.editorial_hero_state(article.hero_asset_id),
  'hero_asset_id',article.hero_asset_id,'hero_alt',article.hero_alt,
  'hero_path',internal.editorial_hero_path(article.id),'revision',article.revision)
$$;

create or replace function internal.set_editorial_article_hero_for_actor(target_article_id uuid,new_asset_id uuid,
 new_alt text,expected_revision bigint,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();article core.editorial_articles%rowtype;asset core.public_media_assets%rowtype;
 existing jsonb;new_revision bigint;alt_value text:=nullif(btrim(new_alt),'');
begin
 if actor_id is null then raise insufficient_privilege using message='not_found';end if;
 select * into article from core.editorial_articles where id=target_article_id for update;
 if article.id is null or not internal.actor_has_capability(article.club_id,null,'publication.manage')
 then raise insufficient_privilege using message='not_found';end if;
 select result into existing from internal.command_deduplication dedupe where dedupe.actor_profile_id=actor_id
  and dedupe.command_type='publication.article.hero.v1'
  and dedupe.idempotency_key=set_editorial_article_hero_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 if article.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 if article.state='published' then raise check_violation using message='unpublish_before_edit';end if;
 if alt_value is not null and length(alt_value)>200 then raise invalid_parameter_value using message='invalid_alt';end if;
 if new_asset_id is not null then
  select * into asset from core.public_media_assets where id=new_asset_id and club_id=article.club_id;
  if asset.id is null or asset.purpose<>'editorial_hero' or asset.removed_at is not null
   or asset.scan_state='rejected' or asset.variant_state in('failed','removed')
  then raise invalid_parameter_value using message='invalid_media';end if;
 end if;
 -- A replaced or removed hero stops being served, unless another article uses it.
 if article.hero_asset_id is not null and article.hero_asset_id is distinct from new_asset_id
  and not exists(select 1 from core.editorial_articles other where other.hero_asset_id=article.hero_asset_id and other.id<>article.id)
 then
  update core.public_media_assets set variant_state='removed',removed_at=now(),revision=revision+1
  where id=article.hero_asset_id and removed_at is null;
 end if;
 update core.editorial_articles set hero_asset_id=new_asset_id,hero_alt=case when new_asset_id is null then null else alt_value end,
  updated_by=actor_id,updated_at=now(),revision=revision+1 where id=article.id returning * into article;
 new_revision:=article.revision;
 insert into core.editorial_article_revisions(article_id,club_id,article_revision,action,snapshot,actor_profile_id)
 values(article.id,article.club_id,new_revision,'saved',internal.editorial_snapshot(article),actor_id);
 existing:=jsonb_build_object('article_id',article.id,'revision',new_revision,
  'media_status',internal.editorial_hero_state(article.hero_asset_id));
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'publication.article.hero.v1',existing);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(article.club_id,actor_id,'publication.article.hero.v1','publication',article.id,new_revision,
  jsonb_build_object('hero_asset_id',new_asset_id));
 return existing;
end;$$;

create or replace function api.set_editorial_article_hero(article_id uuid,asset_id uuid,alt text,expected_revision bigint,idempotency_key uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select internal.set_editorial_article_hero_for_actor(article_id,asset_id,alt,expected_revision,idempotency_key)
$$;

-- Publishing projects the hero path along with the article.
do $migration$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.transition_editorial_article_for_actor(uuid,text,timestamptz,bigint,uuid)'::regprocedure);
 patched:=replace(definition,
  'values(article.id,club_setting.public_id,null,''news'',article.title,article.summary,null,',
  'values(article.id,club_setting.public_id,null,''news'',article.title,article.summary,internal.editorial_hero_path(article.id),');
 if patched=definition then raise exception 'article projection insert contract changed';end if;
 definition:=patched;
 patched:=replace(definition,
  'summary,media_path,published_at,source_revision,projected_at,slug,body_blocks,author_label,club_channel)',
  'summary,media_path,published_at,source_revision,projected_at,slug,body_blocks,author_label,club_channel,media_alt)');
 if patched=definition then raise exception 'article projection columns contract changed';end if;
 definition:=patched;
 patched:=replace(definition,
  'article.published_at,article.revision,now_value,article.slug,article.body_blocks,article.author_label,article.publish_to_club)',
  'article.published_at,article.revision,now_value,article.slug,article.body_blocks,article.author_label,article.publish_to_club,
   case when internal.editorial_hero_path(article.id) is not null then article.hero_alt end)');
 if patched=definition then raise exception 'article projection insert contract changed';end if;
 definition:=patched;
 patched:=replace(definition,
  'on conflict(public_id) do update set title=excluded.title,summary=excluded.summary,',
  'on conflict(public_id) do update set title=excluded.title,summary=excluded.summary,media_path=excluded.media_path,media_alt=excluded.media_alt,');
 if patched=definition then raise exception 'article projection update contract changed';end if;
 execute patched;
end;
$migration$;

-- The public article page receives the image and its description.
do $migration$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.public_get_article(text,text,text)'::regprocedure);
 patched:=replace(definition,
  '''author_label'',content.author_label) into result',
  '''author_label'',content.author_label,''media_path'',content.media_path,''media_alt'',content.media_alt) into result');
 if patched=definition then raise exception 'public article contract changed';end if;
 execute patched;
end;
$migration$;

-- A hero that becomes ready (or is removed) after publishing updates the
-- published article and asks the site to refresh its cached pages.
create or replace function internal.sync_editorial_hero_projection()
returns trigger language plpgsql security definer set search_path='' as $$
declare article record;
begin
 if new.purpose<>'editorial_hero' or (old.variant_state is not distinct from new.variant_state
  and old.removed_at is not distinct from new.removed_at) then return null;end if;
 for article in
  select a.id,a.club_id,a.slug,a.revision,a.hero_alt,setting.slug club_slug from core.editorial_articles a
  join core.club_publication_settings setting on setting.club_id=a.club_id
  where a.hero_asset_id=new.id and a.state='published'
 loop
  update public_api.content_projections set media_path=internal.editorial_hero_path(article.id),
   media_alt=case when internal.editorial_hero_path(article.id) is not null then article.hero_alt end,projected_at=now()
  where public_id=article.id;
  insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,requested_revision,action,affected_paths,created_by)
  values(article.club_id,'publication',article.id,article.revision,'invalidate',
   array['/'||article.club_slug,'/'||article.club_slug||'/nyheter/'||article.slug],new.created_by)
  on conflict do nothing;
 end loop;
 return null;
end;$$;
drop trigger if exists editorial_hero_projection on core.public_media_assets;
create trigger editorial_hero_projection after update of variant_state,removed_at on core.public_media_assets
 for each row execute function internal.sync_editorial_hero_projection();

revoke all on function internal.editorial_hero_path(uuid),internal.editorial_hero_state(uuid),
 internal.set_editorial_article_hero_for_actor(uuid,uuid,text,bigint,uuid),internal.sync_editorial_hero_projection(),
 api.set_editorial_article_hero(uuid,uuid,text,bigint,uuid) from public,anon,authenticated;
grant execute on function internal.editorial_hero_path(uuid),internal.editorial_hero_state(uuid),
 internal.set_editorial_article_hero_for_actor(uuid,uuid,text,bigint,uuid),
 api.set_editorial_article_hero(uuid,uuid,text,bigint,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261007090000_editorial_hero_image','greenfield',
 'One processed hero image per news article through the private public-media pipeline');
notify pgrst,'reload schema';
