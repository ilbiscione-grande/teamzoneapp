-- Local preparation only. No automatic runtime activation or public exposure of accounts.
create table core.public_channel_follows (
 user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in('club','team')),
 public_id uuid not null,
 created_at timestamptz not null default now(),
 primary key(user_id,kind,public_id)
);
alter table core.public_channel_follows enable row level security;
create policy own_public_channel_follows on core.public_channel_follows
 for select to authenticated using(user_id=(select auth.uid()));
revoke all on core.public_channel_follows from public,anon,authenticated;

create function internal.set_public_channel_follow_for_actor(target_kind text,target_id uuid,following boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); valid boolean;
begin
 if actor is null then raise insufficient_privilege using message='authentication_required';end if;
 if target_kind is null or target_kind not in('club','team') or target_id is null or following is null
 then raise invalid_parameter_value using message='invalid_request';end if;
 -- Serialize this account's writes so the bounded subscription count is race-safe.
 perform pg_advisory_xact_lock(hashtextextended(actor::text,7));
 if not following then
  delete from core.public_channel_follows where user_id=actor and kind=target_kind and public_id=target_id;
  return jsonb_build_object('following',false);
 end if;
 if not internal.public_runtime_enabled() then raise check_violation using message='public_unavailable';end if;
 if target_kind='club' then
  select exists(select 1 from public_api.club_projections where public_id=target_id and visibility='published') into valid;
 else
  select exists(select 1 from public_api.team_projections t join public_api.club_projections c on c.public_id=t.club_public_id
   where t.public_id=target_id and t.visibility='published' and c.visibility='published') into valid;
 end if;
 if not valid then raise no_data_found using message='not_found';end if;
 if not exists(select 1 from core.public_channel_follows where user_id=actor and kind=target_kind and public_id=target_id)
  and (select count(*) from core.public_channel_follows where user_id=actor)>=100 then
  raise program_limit_exceeded using message='follow_limit';
 end if;
 insert into core.public_channel_follows(user_id,kind,public_id) values(actor,target_kind,target_id) on conflict do nothing;
 return jsonb_build_object('following',true);
end;$$;

create function internal.get_personal_public_home_for_actor(before_at timestamptz default null,before_id uuid default null,before_kind text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); followed jsonb; feed jsonb; last_item jsonb; rate jsonb;
begin
 if actor is null then raise insufficient_privilege using message='authentication_required';end if;
 if not internal.public_runtime_enabled() then return jsonb_build_object('available',false,'following','[]'::jsonb,'items','[]'::jsonb);end if;
 if num_nonnulls(before_at,before_id,before_kind) not in(0,3)
  or (before_kind is not null and before_kind not in('news','result')) then
  raise invalid_parameter_value using message='invalid_cursor';
 end if;
 rate:=internal.consume_public_rate_limit(md5(actor::text)||md5(actor::text),'read',null);
 if not(rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited';end if;
 with channels as (
  select f.kind,f.public_id id,c.name,c.slug,c.locality,null::text club_slug,null::text club_name,null::text age_class
  from core.public_channel_follows f join public_api.club_projections c on c.public_id=f.public_id
  where f.user_id=actor and f.kind='club' and c.visibility='published'
  union all
  select f.kind,f.public_id,t.name,t.slug,c.locality,c.slug,c.name,t.age_class
  from core.public_channel_follows f join public_api.team_projections t on t.public_id=f.public_id
  join public_api.club_projections c on c.public_id=t.club_public_id
  where f.user_id=actor and f.kind='team' and t.visibility='published' and c.visibility='published'
 ) select coalesce(jsonb_agg(to_jsonb(channels) order by kind desc,lower(name),id),'[]'::jsonb) into followed from channels;
 with visible_teams as materialized (
  select t.public_id,t.club_public_id,t.slug,t.name from public_api.team_projections t
  join public_api.club_projections c on c.public_id=t.club_public_id
  where t.visibility='published' and c.visibility='published'
   and exists(select 1 from core.public_channel_follows f where f.user_id=actor and
    ((f.kind='team' and f.public_id=t.public_id) or(f.kind='club' and f.public_id=c.public_id)))
 ), candidate_news as (
  select p.public_id from public_api.content_projections p join core.public_channel_follows f
   on f.kind='club' and f.public_id=p.club_public_id and f.user_id=actor
  union
  select ch.content_public_id from public_api.content_team_channels ch join core.public_channel_follows f
   on f.kind='team' and f.public_id=ch.team_public_id and f.user_id=actor
 ), feed_items as (
  select p.public_id id,'news'::text kind,p.published_at happened_at,p.title,p.summary,c.slug club_slug,c.name club_name,
   p.slug article_slug,null::text team_slug,null::text team_name,null::integer score_us,null::integer score_opponent
  from candidate_news candidate join public_api.content_projections p on p.public_id=candidate.public_id
  join public_api.club_projections c on c.public_id=p.club_public_id
  where c.visibility='published' and p.content_type='news' and p.slug is not null
   and (p.club_channel or exists(select 1 from public_api.content_team_channels ch join visible_teams t on t.public_id=ch.team_public_id
     where ch.content_public_id=p.public_id and t.club_public_id=c.public_id))
   and (exists(select 1 from core.public_channel_follows f where f.user_id=actor and f.kind='club' and f.public_id=c.public_id)
    or exists(select 1 from public_api.content_team_channels ch join visible_teams t on t.public_id=ch.team_public_id
     join core.public_channel_follows f on f.public_id=t.public_id and f.kind='team' and f.user_id=actor
     where ch.content_public_id=p.public_id and t.club_public_id=c.public_id))
  union all
  select e.public_id,'result',e.starts_at,e.title,null,c.slug,c.name,null,t.slug,t.name,r.score_us,r.score_opponent
  from public_api.match_result_projections r join public_api.event_projections e on e.public_id=r.event_public_id
  join visible_teams t on t.public_id=e.team_public_id join public_api.club_projections c on c.public_id=t.club_public_id
  where exists(select 1 from core.public_channel_follows f where f.user_id=actor and
   ((f.kind='club' and f.public_id=c.public_id) or(f.kind='team' and f.public_id=t.public_id)))
 ), page as (
  select * from feed_items where before_at is null or(happened_at,id,kind)<(before_at,before_id,before_kind)
  order by happened_at desc,id desc,kind desc limit 21
 ) select coalesce(jsonb_agg(to_jsonb(page) order by happened_at desc,id desc,kind desc),'[]'::jsonb) into feed from page;
 last_item:=feed->19;
 return jsonb_build_object('available',true,'following',followed,
  'unavailable_count',(select count(*) from core.public_channel_follows where user_id=actor)-jsonb_array_length(followed),
  'items',(select coalesce(jsonb_agg(value order by ordinality),'[]'::jsonb) from jsonb_array_elements(feed) with ordinality where ordinality<=20),
  'next_cursor',case when jsonb_array_length(feed)>20 then jsonb_build_object('before_at',last_item->>'happened_at','before_id',last_item->>'id','before_kind',last_item->>'kind') end);
end;$$;
create function api.set_public_channel_follow(kind text,public_id uuid,following boolean)
returns jsonb language sql security invoker set search_path='' as $$select internal.set_public_channel_follow_for_actor(kind,public_id,following)$$;
create function api.get_personal_public_home(before_at timestamptz default null,before_id uuid default null,before_kind text default null)
returns jsonb language sql security invoker set search_path='' as $$select internal.get_personal_public_home_for_actor(before_at,before_id,before_kind)$$;
revoke all on function internal.set_public_channel_follow_for_actor(text,uuid,boolean),internal.get_personal_public_home_for_actor(timestamptz,uuid,text),
 api.set_public_channel_follow(text,uuid,boolean),api.get_personal_public_home(timestamptz,uuid,text) from public,anon,authenticated;
grant execute on function internal.set_public_channel_follow_for_actor(text,uuid,boolean),internal.get_personal_public_home_for_actor(timestamptz,uuid,text),
 api.set_public_channel_follow(text,uuid,boolean),api.get_personal_public_home(timestamptz,uuid,text) to authenticated;
notify pgrst,'reload schema';
