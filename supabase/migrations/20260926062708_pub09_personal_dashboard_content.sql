-- Read-only dashboard: own membership is resolved on the server. Following
-- exposes only already-published projections, never private calendar rows.
create function internal.get_personal_dashboard_content_for_actor()
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); result jsonb; rate jsonb;
begin
 if actor is null then raise insufficient_privilege using message='authentication_required';end if;
 if not internal.public_runtime_enabled() then return jsonb_build_object('available',false,'own_teams','[]'::jsonb,'news','[]'::jsonb,'results','[]'::jsonb,'events','[]'::jsonb);end if;
 rate:=internal.consume_public_rate_limit(md5(actor::text)||md5(actor::text),'read',null);
 if not(rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited';end if;
 with own as materialized (
  select distinct team_id,team_name,club_id,club_name from internal.get_my_contexts_for_actor() where team_id is not null
 ), visible as materialized (
  select t.*,s.team_id,c.name club_name,
   exists(select 1 from own o where o.team_id=s.team_id) is_own
  from public_api.team_projections t join public_api.club_projections c on c.public_id=t.club_public_id
  join core.team_publication_settings s on s.public_id=t.public_id
  where t.visibility='published' and c.visibility='published'
 ), channels as materialized (
  select v.* from visible v where v.is_own or exists(select 1 from core.public_channel_follows f where f.user_id=actor
   and ((f.kind='team' and f.public_id=v.public_id) or(f.kind='club' and f.public_id=v.club_public_id)))
 ), clubs as materialized (
  select c.*,exists(select 1 from own o join core.club_publication_settings s on s.club_id=o.club_id where s.public_id=c.public_id) is_own
  from public_api.club_projections c where c.visibility='published'
 ), relevant_clubs as materialized (
  select c.* from clubs c where c.is_own or exists(select 1 from core.public_channel_follows f where f.user_id=actor and f.kind='club' and f.public_id=c.public_id)
 ), news_candidates as (
  select p.public_id id,'news'::text kind,p.published_at happened_at,p.title,p.summary,p.slug article_slug,c.slug club_slug,c.name club_name,
   ((p.club_channel and c.is_own) or exists(select 1 from public_api.content_team_channels ch join channels t on t.public_id=ch.team_public_id where ch.content_public_id=p.public_id and t.is_own)) is_own
  from public_api.content_projections p join clubs c on c.public_id=p.club_public_id
  where p.content_type='news' and p.slug is not null and (
   (p.club_channel and exists(select 1 from relevant_clubs rc where rc.public_id=p.club_public_id)) or
   exists(select 1 from public_api.content_team_channels ch join channels t on t.public_id=ch.team_public_id where ch.content_public_id=p.public_id and t.club_public_id=p.club_public_id))
 ), news_ranked as (
  select *,row_number() over(partition by is_own order by happened_at desc,id desc) position from news_candidates
 ), result_candidates as (
  select e.public_id id,'result'::text kind,e.starts_at happened_at,e.title,t.club_slug,t.club_name,t.slug team_slug,t.name team_name,
   r.score_us,r.score_opponent,t.is_own
  from public_api.match_result_projections r join public_api.event_projections e on e.public_id=r.event_public_id
  join channels t on t.public_id=e.team_public_id
 ), results_ranked as (
  select *,row_number() over(partition by is_own order by happened_at desc,id desc) position from result_candidates
 ), calendar as (
  select e.public_id event_id,e.title,e.starts_at,e.event_type,e.location_name,t.name team_name,t.team_id owning_team_id,t.club_slug,t.slug team_slug,t.is_own
  from public_api.event_projections e join channels t on t.public_id=e.team_public_id
  where e.event_type in('match','training') and e.starts_at>=now() and e.starts_at<now()+interval '90 days'
  order by e.starts_at,e.public_id limit 201
 ) select jsonb_build_object('available',true,
  'own_teams',(select coalesce(jsonb_agg(jsonb_build_object('id',o.team_id,'name',o.team_name,'club_name',o.club_name,'href',case when v.public_id is not null then '/'||v.club_slug||'/'||v.slug end) order by o.club_name,o.team_name),'[]'::jsonb) from own o left join visible v on v.team_id=o.team_id),
  'news',(select coalesce(jsonb_agg(to_jsonb(n)-'position' order by happened_at desc,id desc),'[]'::jsonb) from news_ranked n where position<=12),
  'results',(select coalesce(jsonb_agg(to_jsonb(r)-'position' order by happened_at desc,id desc),'[]'::jsonb) from results_ranked r where position<=12),
  'events',(select coalesce(jsonb_agg(to_jsonb(e) order by starts_at,event_id),'[]'::jsonb) from(select * from calendar limit 200)e),
  'calendar_truncated',(select count(*)>200 from calendar)) into result;
 return result;
end;$$;
create function api.get_personal_dashboard_content() returns jsonb language sql security invoker set search_path='' as $$select internal.get_personal_dashboard_content_for_actor()$$;
revoke all on function internal.get_personal_dashboard_content_for_actor(),api.get_personal_dashboard_content() from public,anon,authenticated;
grant execute on function internal.get_personal_dashboard_content_for_actor(),api.get_personal_dashboard_content() to authenticated;
notify pgrst,'reload schema';
