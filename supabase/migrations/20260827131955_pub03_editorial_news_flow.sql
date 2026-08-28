-- PUB-03 structured editorial news. No free HTML and no runtime activation.

create table core.editorial_articles(
 id uuid primary key default gen_random_uuid(),club_id uuid not null references core.clubs(id),
 slug text not null,title text not null,summary text,body_blocks jsonb not null default '[]'::jsonb,
 state text not null default 'draft' check(state in('draft','scheduled','published','unpublished')),
 publish_at timestamptz,published_at timestamptz,unpublished_at timestamptz,
 author_label text,publish_to_club boolean not null default true,
 created_by uuid not null references core.profiles(id),updated_by uuid not null references core.profiles(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 revision bigint not null default 1 check(revision>0),
 unique(club_id,slug),unique(id,club_id),
 check(slug=lower(slug) and slug~'^[a-z0-9]+(?:-[a-z0-9]+)*$' and length(slug) between 2 and 100),
 check(length(btrim(title)) between 1 and 160),
 check(summary is null or length(summary)<=1000),
 check(author_label is null or length(btrim(author_label)) between 1 and 120),
 check((state='scheduled' and publish_at is not null and published_at is null)
  or(state='published' and published_at is not null and unpublished_at is null)
  or(state='unpublished' and unpublished_at is not null)
  or(state='draft' and published_at is null and unpublished_at is null))
);
create index editorial_articles_state_schedule_idx on core.editorial_articles(state,publish_at,id)
 where state='scheduled';
create index editorial_articles_club_updated_idx on core.editorial_articles(club_id,updated_at desc,id);

create table core.editorial_article_channels(
 article_id uuid not null,club_id uuid not null,team_id uuid,
 primary key(article_id,team_id),foreign key(article_id,club_id) references core.editorial_articles(id,club_id) on delete cascade,
 foreign key(team_id,club_id) references core.teams(id,club_id),
 check(team_id is not null)
);
create unique index editorial_article_club_channel_idx on core.editorial_article_channels(article_id)
 where team_id is null;

create table core.editorial_article_revisions(
 id uuid primary key default gen_random_uuid(),article_id uuid not null,club_id uuid not null,
 article_revision bigint not null,action text not null check(action in('created','saved','scheduled','published','unpublished')),
 snapshot jsonb not null,actor_profile_id uuid not null references core.profiles(id),created_at timestamptz not null default now(),
 unique(article_id,article_revision),foreign key(article_id,club_id) references core.editorial_articles(id,club_id)
);
create index editorial_article_revisions_actor_idx on core.editorial_article_revisions(actor_profile_id,created_at desc);

alter table core.editorial_articles enable row level security;
alter table core.editorial_article_channels enable row level security;
alter table core.editorial_article_revisions enable row level security;
create policy editorial_articles_no_client_access on core.editorial_articles for all to authenticated using(false) with check(false);
create policy editorial_article_channels_no_client_access on core.editorial_article_channels for all to authenticated using(false) with check(false);
create policy editorial_article_revisions_no_client_access on core.editorial_article_revisions for all to authenticated using(false) with check(false);
revoke all on table core.editorial_articles,core.editorial_article_channels,core.editorial_article_revisions from public,anon,authenticated;

alter table public_api.content_projections add column slug text,
 add column body_blocks jsonb not null default '[]'::jsonb,add column author_label text,
 add column club_channel boolean not null default true;
alter table public_api.content_projections add constraint content_projection_slug_check
 check(slug is null or(slug=lower(slug) and slug~'^[a-z0-9]+(?:-[a-z0-9]+)*$'));
create unique index content_projections_club_slug_idx on public_api.content_projections(club_public_id,slug)
 where content_type='news' and slug is not null;
create table public_api.content_team_channels(
 content_public_id uuid not null references public_api.content_projections(public_id) on delete cascade,
 team_public_id uuid not null references public_api.team_projections(public_id) on delete cascade,
 primary key(content_public_id,team_public_id)
);
alter table public_api.content_team_channels enable row level security;
create policy content_team_channels_no_client_access on public_api.content_team_channels
 for all to authenticated using(false) with check(false);
revoke all on table public_api.content_team_channels from public,anon,authenticated;

create function internal.editorial_blocks_valid(blocks jsonb)
returns boolean language sql immutable set search_path='' as $$
 select jsonb_typeof(blocks)='array' and jsonb_array_length(blocks) between 1 and 50
  and not exists(select 1 from jsonb_array_elements(blocks) block
   where jsonb_typeof(block)<>'object' or block->>'type' not in('heading','paragraph','link')
    or exists(select 1 from jsonb_object_keys(block) key where key not in('type','text','href'))
    or length(btrim(coalesce(block->>'text',''))) not between 1 and 4000
    or(block->>'type'='heading' and length(block->>'text')>160)
    or(block->>'type'='link' and coalesce(block->>'href','')!~'^https://[A-Za-z0-9]'))
$$;

create function internal.editorial_snapshot(article core.editorial_articles)
returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('id',article.id,'slug',article.slug,'title',article.title,
  'summary',article.summary,'body_blocks',article.body_blocks,'state',article.state,
  'publish_at',article.publish_at,'published_at',article.published_at,
  'author_label',article.author_label,'publish_to_club',article.publish_to_club,
  'media_status','not_configured','revision',article.revision)
$$;

create function internal.save_editorial_article_for_actor(target_club_id uuid,target_article_id uuid,
 new_slug text,new_title text,new_summary text,new_blocks jsonb,new_author_label text,
 new_publish_to_club boolean,new_team_ids uuid[],expected_revision bigint,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();article core.editorial_articles%rowtype;existing jsonb;article_id uuid;new_revision bigint;
begin
 if actor_id is null or not internal.actor_has_capability(target_club_id,null,'publication.manage')
 then raise insufficient_privilege using message='not_found';end if;
 if lower(btrim(coalesce(new_slug,'')))!~'^[a-z0-9]+(?:-[a-z0-9]+)*$'
  or length(btrim(new_slug)) not between 2 and 100 or length(btrim(new_title)) not between 1 and 160
  or(new_summary is not null and length(new_summary)>1000)
  or not internal.editorial_blocks_valid(new_blocks) or cardinality(coalesce(new_team_ids,array[]::uuid[]))>20
  or(not new_publish_to_club and cardinality(coalesce(new_team_ids,array[]::uuid[]))=0)
 then raise invalid_parameter_value using message='invalid_article';end if;
 if exists(select 1 from unnest(coalesce(new_team_ids,array[]::uuid[])) team_id
  where not exists(select 1 from core.teams team where team.id=team_id and team.club_id=target_club_id and team.status='active'))
 then raise insufficient_privilege using message='not_found';end if;
 select result into existing from internal.command_deduplication dedupe where dedupe.actor_profile_id=actor_id
  and dedupe.command_type='publication.article.save.v1' and dedupe.idempotency_key=save_editorial_article_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 if target_article_id is null then
  insert into core.editorial_articles(club_id,slug,title,summary,body_blocks,author_label,publish_to_club,created_by,updated_by)
  values(target_club_id,lower(btrim(new_slug)),btrim(new_title),nullif(btrim(new_summary),''),new_blocks,
   nullif(btrim(new_author_label),''),new_publish_to_club,actor_id,actor_id) returning id,revision into article_id,new_revision;
 else
  select * into article from core.editorial_articles where id=target_article_id and club_id=target_club_id for update;
  if article.id is null then raise insufficient_privilege using message='not_found';end if;
  if article.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
  if article.state='published' then raise check_violation using message='unpublish_before_edit';end if;
  update core.editorial_articles set slug=lower(btrim(new_slug)),title=btrim(new_title),summary=nullif(btrim(new_summary),''),
   body_blocks=new_blocks,author_label=nullif(btrim(new_author_label),''),publish_to_club=new_publish_to_club,
   updated_by=actor_id,updated_at=now(),revision=revision+1
   where id=article.id returning id,revision into article_id,new_revision;
 end if;
 delete from core.editorial_article_channels where article_id=save_editorial_article_for_actor.target_article_id;
 insert into core.editorial_article_channels(article_id,club_id,team_id)
 select article_id,target_club_id,team_id from unnest(coalesce(new_team_ids,array[]::uuid[])) team_id;
 select * into article from core.editorial_articles where id=article_id;
 insert into core.editorial_article_revisions(article_id,club_id,article_revision,action,snapshot,actor_profile_id)
 values(article_id,target_club_id,new_revision,case when new_revision=1 then 'created' else 'saved' end,
  internal.editorial_snapshot(article),actor_id);
 existing:=jsonb_build_object('article_id',article_id,'state',article.state,'revision',new_revision);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'publication.article.save.v1',existing);
 return existing;
end;$$;

create function internal.transition_editorial_article_for_actor(target_article_id uuid,new_state text,
 new_publish_at timestamptz,expected_revision bigint,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();article core.editorial_articles%rowtype;club_setting core.club_publication_settings%rowtype;
 existing jsonb;new_revision bigint;now_value timestamptz:=now();worker_call boolean:=false;
begin
 select * into article from core.editorial_articles where id=target_article_id for update;
 if article.id is null then raise insufficient_privilege using message='not_found';end if;
 if actor_id is null then actor_id:=article.updated_by;worker_call:=true;end if;
 if actor_id is null or(not worker_call
   and not internal.actor_has_capability(article.club_id,null,'publication.manage'))
 then raise insufficient_privilege using message='not_found';end if;
 select result into existing from internal.command_deduplication dedupe where dedupe.actor_profile_id=actor_id
  and dedupe.command_type='publication.article.transition.v1'
  and dedupe.idempotency_key=transition_editorial_article_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 if article.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 if new_state not in('scheduled','published','unpublished')
  or(new_state='scheduled' and(new_publish_at is null or new_publish_at<=now_value))
  or(new_state='published' and article.state not in('draft','scheduled','unpublished'))
  or(new_state='unpublished' and article.state<>'published')
 then raise check_violation using message='invalid_transition';end if;
 select * into club_setting from core.club_publication_settings where club_id=article.club_id;
 if new_state in('scheduled','published') and(club_setting.mode<>'published' or club_setting.confirmation_id is null)
 then raise check_violation using message='club_not_published';end if;
 update core.editorial_articles set state=new_state,
  publish_at=case when new_state='scheduled' then new_publish_at else publish_at end,
  published_at=case when new_state='published' then now_value else published_at end,
  unpublished_at=case when new_state='unpublished' then now_value else null end,
  updated_by=actor_id,updated_at=now_value,revision=revision+1 where id=article.id
  returning * into article;new_revision:=article.revision;
 if new_state='published' then
 insert into public_api.content_projections(public_id,club_public_id,team_public_id,content_type,title,
   summary,media_path,published_at,source_revision,projected_at,slug,body_blocks,author_label,club_channel)
  values(article.id,club_setting.public_id,null,'news',article.title,article.summary,null,
   article.published_at,article.revision,now_value,article.slug,article.body_blocks,article.author_label,article.publish_to_club)
  on conflict(public_id) do update set title=excluded.title,summary=excluded.summary,published_at=excluded.published_at,
   source_revision=excluded.source_revision,projected_at=excluded.projected_at,slug=excluded.slug,
   body_blocks=excluded.body_blocks,author_label=excluded.author_label;
  delete from public_api.content_team_channels where content_public_id=article.id;
  insert into public_api.content_team_channels(content_public_id,team_public_id)
  select article.id,setting.public_id from core.editorial_article_channels channel
   join core.team_publication_settings setting on setting.team_id=channel.team_id
  where channel.article_id=article.id and setting.mode='published';
 else delete from public_api.content_projections where public_id=article.id;end if;
 insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,requested_revision,action,affected_paths,created_by)
 values(article.club_id,'publication',article.id,new_revision,'invalidate',
  array['/'||club_setting.slug,'/'||club_setting.slug||'/nyheter/'||article.slug],actor_id);
 insert into core.editorial_article_revisions(article_id,club_id,article_revision,action,snapshot,actor_profile_id)
 values(article.id,article.club_id,new_revision,new_state,internal.editorial_snapshot(article),actor_id);
 existing:=jsonb_build_object('article_id',article.id,'state',new_state,'revision',new_revision);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'publication.article.transition.v1',existing);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(article.club_id,actor_id,'publication.article.transition.v1','publication',article.id,new_revision,
  jsonb_build_object('state',new_state,'publish_at',new_publish_at));
 return existing;
end;$$;

create function internal.publish_due_editorial_articles(batch_size integer default 50)
returns integer language plpgsql security definer set search_path='' as $$
declare candidate record;changed integer:=0;
begin
 if current_user not in('service_role','postgres') then raise insufficient_privilege using message='service_role_required';end if;
 if batch_size not between 1 and 100 then raise invalid_parameter_value using message='invalid_batch';end if;
 for candidate in select id,revision from core.editorial_articles where state='scheduled' and publish_at<=now()
  order by publish_at,id for update skip locked limit batch_size loop
  perform internal.transition_editorial_article_for_actor(candidate.id,'published',null,candidate.revision,gen_random_uuid());
  changed:=changed+1;
 end loop;
 return changed;
end;$$;

create or replace function internal.public_list_publications(target_club_id uuid,target_team_id uuid,
 before_published_at timestamptz,before_id uuid,ip_sha256_hex text,page_limit integer default 20)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb;result jsonb;
begin
 if not internal.public_runtime_enabled() then return jsonb_build_object('available',false,'items','[]'::jsonb);end if;
 if page_limit not between 1 and 20 then raise invalid_parameter_value using message='invalid_request';end if;
 rate:=internal.consume_public_rate_limit(ip_sha256_hex,'read',null);
 if not(rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',public_id,'content_type',content_type,'slug',slug,
  'title',title,'summary',summary,'media_path',media_path,'published_at',published_at)
  order by published_at desc,public_id desc),'[]'::jsonb) into result
 from(select content.* from public_api.content_projections content
  where content.club_public_id=target_club_id
   and((target_team_id is null and content.club_channel) or(target_team_id is not null and exists(select 1 from public_api.content_team_channels channel
    where channel.content_public_id=content.public_id and channel.team_public_id=target_team_id)))
   and(before_published_at is null or(content.published_at,content.public_id)<
    (before_published_at,coalesce(before_id,'ffffffff-ffff-ffff-ffff-ffffffffffff')))
  order by content.published_at desc,content.public_id desc limit page_limit) page;
 return jsonb_build_object('available',true,'items',result,'cache_control','no-store');
end;$$;

create function internal.get_editorial_article_for_actor(target_article_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare article core.editorial_articles%rowtype;
begin
 select * into article from core.editorial_articles where id=target_article_id;
 if article.id is null or not internal.actor_has_capability(article.club_id,null,'publication.manage')
 then raise insufficient_privilege using message='not_found';end if;
 return internal.editorial_snapshot(article)||jsonb_build_object('teams',coalesce((select jsonb_agg(team_id)
  from core.editorial_article_channels where article_id=article.id),'[]'::jsonb));
end;$$;

create function internal.public_get_article(target_club_slug text,target_article_slug text,ip_sha256_hex text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb;result jsonb;
begin
 if not internal.public_runtime_enabled() then return jsonb_build_object('available',false);end if;
 rate:=internal.consume_public_rate_limit(ip_sha256_hex,'read',null);
 if not(rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited';end if;
 select jsonb_build_object('id',content.public_id,'club_slug',club.slug,'slug',content.slug,'title',content.title,
  'summary',content.summary,'body_blocks',content.body_blocks,'published_at',content.published_at,
  'author_label',content.author_label) into result from public_api.content_projections content
 join public_api.club_projections club on club.public_id=content.club_public_id
 where club.slug=lower(btrim(target_club_slug)) and content.slug=lower(btrim(target_article_slug))
  and content.content_type='news';
 return coalesce(result,jsonb_build_object('not_found',true));
end;$$;

create function api.save_editorial_article(club_id uuid,article_id uuid,slug text,title text,summary text,
 blocks jsonb,author_label text,publish_to_club boolean,team_ids uuid[],expected_revision bigint,idempotency_key uuid)
returns jsonb language sql security invoker set search_path='' as
$$select internal.save_editorial_article_for_actor(club_id,article_id,slug,title,summary,blocks,author_label,publish_to_club,team_ids,expected_revision,idempotency_key)$$;
create function api.transition_editorial_article(article_id uuid,state text,publish_at timestamptz,
 expected_revision bigint,idempotency_key uuid) returns jsonb language sql security invoker set search_path='' as
$$select internal.transition_editorial_article_for_actor(article_id,state,publish_at,expected_revision,idempotency_key)$$;
create function api.get_editorial_article(article_id uuid) returns jsonb language sql stable security invoker set search_path='' as
$$select internal.get_editorial_article_for_actor(article_id)$$;
create function api.public_get_article(club_slug text,article_slug text,ip_hash text)
returns jsonb language sql security invoker set search_path='' as
$$select internal.public_get_article(club_slug,article_slug,ip_hash)$$;
create function api.publish_due_editorial_articles(batch_size integer default 50)
returns integer language sql security invoker set search_path='' as
$$select internal.publish_due_editorial_articles(batch_size)$$;

revoke all on function internal.editorial_blocks_valid(jsonb),internal.editorial_snapshot(core.editorial_articles),
 internal.save_editorial_article_for_actor(uuid,uuid,text,text,text,jsonb,text,boolean,uuid[],bigint,uuid),
 internal.transition_editorial_article_for_actor(uuid,text,timestamptz,bigint,uuid),
 internal.get_editorial_article_for_actor(uuid),internal.public_get_article(text,text,text),
 internal.publish_due_editorial_articles(integer),
 api.save_editorial_article(uuid,uuid,text,text,text,jsonb,text,boolean,uuid[],bigint,uuid),
 api.transition_editorial_article(uuid,text,timestamptz,bigint,uuid),api.get_editorial_article(uuid),
 api.public_get_article(text,text,text),api.publish_due_editorial_articles(integer) from public,anon,authenticated;
grant execute on function internal.save_editorial_article_for_actor(uuid,uuid,text,text,text,jsonb,text,boolean,uuid[],bigint,uuid),
 internal.transition_editorial_article_for_actor(uuid,text,timestamptz,bigint,uuid),internal.get_editorial_article_for_actor(uuid),
 api.save_editorial_article(uuid,uuid,text,text,text,jsonb,text,boolean,uuid[],bigint,uuid),
 api.transition_editorial_article(uuid,text,timestamptz,bigint,uuid),api.get_editorial_article(uuid) to authenticated;
grant execute on function internal.public_get_article(text,text,text),api.public_get_article(text,text,text) to service_role;
grant execute on function internal.publish_due_editorial_articles(integer),api.publish_due_editorial_articles(integer) to service_role;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827131955_pub03_editorial_news_flow','greenfield','PUB-03 structured editorial news lifecycle');
notify pgrst,'reload schema';
