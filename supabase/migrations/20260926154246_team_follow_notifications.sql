-- In-app only: no delivery outbox entries, email, SMS or push jobs.
create table internal.team_updates(
 id uuid primary key default gen_random_uuid(),
 team_id uuid not null references core.teams(id) on delete cascade,
 subject_id uuid not null, kind text not null check(kind in('news','result','report','schedule')),
 source_revision bigint not null default 0, created_at timestamptz not null default now(),
 unique(team_id,subject_id,kind,source_revision)
);
create index team_updates_team_time_idx on internal.team_updates(team_id,created_at desc);
create table core.team_notification_preferences(
 user_id uuid not null references auth.users(id) on delete cascade,
 team_id uuid not null references core.teams(id) on delete cascade,
 news boolean not null default true, results boolean not null default true,
 reports boolean not null default true, schedule boolean not null default true,
 revision bigint not null default 1, primary key(user_id,team_id)
);
create index team_notification_preferences_team_idx on core.team_notification_preferences(team_id);
create table core.team_notification_receipts(
 notification_id uuid not null references internal.team_updates(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 state text not null check(state in('read','dismissed')), primary key(notification_id,user_id)
);
create index team_notification_receipts_user_idx on core.team_notification_receipts(user_id);
alter table internal.team_updates enable row level security;
alter table core.team_notification_preferences enable row level security;
alter table core.team_notification_receipts enable row level security;
create policy team_updates_no_direct_access on internal.team_updates for all to authenticated using(false) with check(false);
create policy team_notification_preferences_no_direct_access on core.team_notification_preferences for all to authenticated using(false) with check(false);
create policy team_notification_receipts_no_direct_access on core.team_notification_receipts for all to authenticated using(false) with check(false);
revoke all on internal.team_updates,core.team_notification_preferences,core.team_notification_receipts from public,anon,authenticated;

create function internal.capture_team_update() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='content_team_channels' then
  insert into internal.team_updates(team_id,subject_id,kind)
  select s.team_id,new.content_public_id,'news' from core.team_publication_settings s
   join public_api.content_projections p on p.public_id=new.content_public_id
   where s.public_id=new.team_public_id and p.content_type='news' on conflict do nothing;
 elsif tg_table_name='match_result_projections' then
  insert into internal.team_updates(team_id,subject_id,kind)
  select s.team_id,new.event_public_id,k.kind from public_api.event_projections e
   join core.team_publication_settings s on s.public_id=e.team_public_id
   cross join (values('result'),('report')) k(kind)
   where e.public_id=new.event_public_id and (k.kind='result' or nullif(btrim(new.report_text),'') is not null)
   on conflict do nothing;
 elsif tg_table_name='events' and new.event_type in('match','training')
  and new.state='scheduled' and new.archived_at is null
  and (old.starts_at is distinct from new.starts_at or old.ends_at is distinct from new.ends_at
   or old.location_id is distinct from new.location_id) then
  insert into internal.team_updates(team_id,subject_id,kind,source_revision)
  values(new.owning_team_id,new.id,'schedule',new.revision) on conflict do nothing;
 end if;
 return null;
end$$;
create trigger team_news_update after insert on public_api.content_team_channels for each row execute function internal.capture_team_update();
create trigger team_result_update after insert or update on public_api.match_result_projections for each row execute function internal.capture_team_update();
create trigger team_schedule_update after update on core.events for each row execute function internal.capture_team_update();

-- Baseline already-published content without creating historical unread alerts.
insert into internal.team_updates(team_id,subject_id,kind,created_at)
select s.team_id,c.content_public_id,'news','-infinity'::timestamptz
from public_api.content_team_channels c join core.team_publication_settings s on s.public_id=c.team_public_id
join public_api.content_projections p on p.public_id=c.content_public_id where p.content_type='news'
on conflict do nothing;
insert into internal.team_updates(team_id,subject_id,kind,created_at)
select s.team_id,r.event_public_id,k.kind,'-infinity'::timestamptz
from public_api.match_result_projections r join public_api.event_projections e on e.public_id=r.event_public_id
join core.team_publication_settings s on s.public_id=e.team_public_id cross join (values('result'),('report')) k(kind)
where k.kind='result' or nullif(btrim(r.report_text),'') is not null on conflict do nothing;

create function internal.team_notification_channels_for_actor()
returns table(team_id uuid,name text,is_own boolean,follow_since timestamptz,public_id uuid,club_slug text,team_slug text)
language sql stable security definer set search_path='' as $$
 with own as (select distinct team_id from internal.get_my_contexts_for_actor() where team_id is not null),
 followed as (
  select s.team_id,min(f.created_at) since,t.public_id,c.slug club_slug,t.slug team_slug
  from core.public_channel_follows f
  join public_api.team_projections t on (f.kind='team' and f.public_id=t.public_id) or(f.kind='club' and f.public_id=t.club_public_id)
  join public_api.club_projections c on c.public_id=t.club_public_id
  join core.team_publication_settings s on s.public_id=t.public_id
  where f.user_id=auth.uid() and t.visibility='published' and c.visibility='published'
  group by s.team_id,t.public_id,c.slug,t.slug
 )
 select t.id,t.name,o.team_id is not null,case when o.team_id is not null then '-infinity'::timestamptz else f.since end,
  f.public_id,f.club_slug,f.team_slug
 from core.teams t left join own o on o.team_id=t.id left join followed f on f.team_id=t.id
 where auth.uid() is not null and (o.team_id is not null or f.team_id is not null)
$$;

create function internal.team_notification_items_for_actor()
returns table(id uuid,event_type text,category text,canonical_key text,priority integer,title text,preview text,
 deep_link text,web_link text,unread boolean,created_at timestamptz,receipt_state text,team_id uuid)
language sql stable security definer set search_path='' as $$
 select u.id,'team.'||u.kind||'.v1','general','team-update:'||u.id::text,50,
  case u.kind when 'news' then 'Nyhet från ' when 'result' then 'Slutresultat från '
   when 'report' then 'Matchrapport från ' else 'Ändrad tid eller plats · ' end||ch.name,
  coalesce(case when u.kind='news' then article.title when u.kind='schedule' then event.title else public_event.title end,''),
  case when u.kind='schedule' then '/calendar/event/'||u.subject_id::text
   else 'https://public.teamzoneapp.se/'||club.slug||'/'||team.slug||case when u.kind='news' then '#nyheter' else '#resultat' end end,
  case when u.kind='schedule' then '/#dashboard-calendar'
   else '/'||club.slug||'/'||team.slug||case when u.kind='news' then '#nyheter' else '#resultat' end end,
  receipt.notification_id is null,u.created_at,receipt.state,u.team_id
 from internal.team_updates u
 join internal.team_notification_channels_for_actor() ch on ch.team_id=u.team_id
 left join core.team_notification_preferences pref on pref.user_id=auth.uid() and pref.team_id=u.team_id
 left join core.team_notification_receipts receipt on receipt.notification_id=u.id and receipt.user_id=auth.uid()
 left join core.team_publication_settings setting on setting.team_id=u.team_id
 left join public_api.team_projections team on team.public_id=setting.public_id
 left join public_api.club_projections club on club.public_id=team.club_public_id
 left join public_api.content_projections article on article.public_id=u.subject_id and u.kind='news'
 left join public_api.event_projections public_event on public_event.public_id=u.subject_id and public_event.team_public_id=team.public_id
 left join public_api.match_result_projections score on score.event_public_id=public_event.public_id
 left join core.events event on event.id=u.subject_id and u.kind='schedule'
 where auth.uid() is not null and u.created_at>=now()-interval '30 days' and u.created_at>=ch.follow_since
 and case u.kind when 'news' then coalesce(pref.news,true) when 'result' then coalesce(pref.results,true)
  when 'report' then coalesce(pref.reports,true) else coalesce(pref.schedule,true) end
 and ((u.kind='schedule' and ch.is_own and event.owning_team_id=u.team_id
   and event.archived_at is null and event.state='scheduled' and internal.actor_can_read_event(event.id))
  or(u.kind<>'schedule' and internal.public_runtime_enabled() and team.visibility='published' and club.visibility='published'
   and ((u.kind='news' and article.content_type='news' and article.club_public_id=club.public_id
    and exists(select 1 from public_api.content_team_channels channel where channel.content_public_id=article.public_id and channel.team_public_id=team.public_id))
    or(u.kind='result' and score.event_public_id is not null)
    or(u.kind='report' and nullif(btrim(score.report_text),'') is not null))))
$$;

create function internal.get_team_notifications_for_actor()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select jsonb_build_object('unread_count',(select count(*) from internal.team_notification_items_for_actor() where unread),
  'items',coalesce((select jsonb_agg(to_jsonb(items) order by created_at desc,id) from
   (select * from internal.team_notification_items_for_actor() where receipt_state is distinct from 'dismissed' order by created_at desc,id limit 100) items),'[]'::jsonb),
  'teams',coalesce((select jsonb_agg(jsonb_build_object('id',ch.team_id,'name',ch.name,'is_own',ch.is_own,
   'news',coalesce(p.news,true),'results',coalesce(p.results,true),'reports',coalesce(p.reports,true),
   'schedule',coalesce(p.schedule,true),'revision',coalesce(p.revision,0)) order by ch.name)
   from internal.team_notification_channels_for_actor() ch left join core.team_notification_preferences p
   on p.team_id=ch.team_id and p.user_id=auth.uid()),'[]'::jsonb)) into result;
 return result;
end$$;
create function internal.set_team_notification_preferences_for_actor(p_team_id uuid,p_news boolean,p_results boolean,
 p_reports boolean,p_schedule boolean,p_expected_revision bigint)
returns bigint language plpgsql security definer set search_path='' as $$
declare revision_value bigint;
begin
 if auth.uid() is null or not exists(select 1 from internal.team_notification_channels_for_actor() where team_id=p_team_id)
 then raise insufficient_privilege using message='not_found';end if;
 if num_nonnulls(p_news,p_results,p_reports,p_schedule,p_expected_revision)<>5 then raise invalid_parameter_value;end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_team_id::text,9));
 select revision into revision_value from core.team_notification_preferences where user_id=auth.uid() and team_id=p_team_id;
 if coalesce(revision_value,0)<>p_expected_revision then raise serialization_failure using message='stale_revision';end if;
 insert into core.team_notification_preferences(user_id,team_id,news,results,reports,schedule)
 values(auth.uid(),p_team_id,p_news,p_results,p_reports,p_schedule)
 on conflict(user_id,team_id) do update set news=excluded.news,results=excluded.results,reports=excluded.reports,
  schedule=excluded.schedule,revision=core.team_notification_preferences.revision+1 returning revision into revision_value;
 return revision_value;
end$$;

-- Keep existing message/callup logic intact; add team entries to its account-scoped interface.
alter function internal.list_notification_center_for_actor(timestamptz,integer) rename to list_notification_center_before_team_updates;
create function internal.list_notification_center_for_actor(page_before timestamptz default null,page_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare base jsonb; rows_value jsonb; extra_count bigint;
begin
 base:=internal.list_notification_center_before_team_updates(page_before,page_limit);
 select count(*) into extra_count from internal.team_notification_items_for_actor() where unread;
 select coalesce(jsonb_agg(item order by (item->>'priority')::int,(item->>'created_at')::timestamptz desc,item->>'id'),'[]') into rows_value from(
  select item from (
   select value item from jsonb_array_elements(base->'items')
   union all select to_jsonb(n) from internal.team_notification_items_for_actor() n
    where n.receipt_state is distinct from 'dismissed' and(page_before is null or n.created_at<page_before)
  ) combined order by (item->>'priority')::int,(item->>'created_at')::timestamptz desc,item->>'id'
  limit greatest(1,least(page_limit,100))) limited;
 return base||jsonb_build_object('items',rows_value,'unread_count',(base->>'unread_count')::bigint+extra_count);
end$$;
alter function internal.set_notification_state_for_actor(uuid,text,uuid) rename to set_notification_state_before_team_updates;
create function internal.set_notification_state_for_actor(target_notification_id uuid,new_state text,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from internal.team_updates where id=target_notification_id) then
  if auth.uid() is null or new_state is null or new_state not in('read','dismissed')
   or not exists(select 1 from internal.team_notification_items_for_actor() where id=target_notification_id)
  then raise insufficient_privilege using message='not_found';end if;
  insert into core.team_notification_receipts(notification_id,user_id,state) values(target_notification_id,auth.uid(),new_state)
  on conflict(notification_id,user_id) do update set state=excluded.state;
  return 1;
 end if;
 return internal.set_notification_state_before_team_updates(target_notification_id,new_state,idempotency_key);
end$$;
alter function internal.mark_all_notifications_read_for_actor(uuid) rename to mark_all_notifications_read_before_team_updates;
create function internal.mark_team_notifications_read_for_actor(idempotency_key uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare added integer; existing jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if idempotency_key is null then raise invalid_parameter_value;end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||idempotency_key::text,10));
 select d.result into existing from internal.command_deduplication d where d.actor_profile_id=auth.uid()
  and d.command_type='team.notifications.read_all.v1' and d.idempotency_key=mark_team_notifications_read_for_actor.idempotency_key;
 if existing is not null then return(existing->>'affected')::integer;end if;
 insert into core.team_notification_receipts(notification_id,user_id,state)
 select id,auth.uid(),'read' from internal.team_notification_items_for_actor() where unread on conflict do nothing;
 get diagnostics added=row_count;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(auth.uid(),idempotency_key,'team.notifications.read_all.v1',jsonb_build_object('affected',added));
 return added;
end$$;
create function internal.mark_all_notifications_read_for_actor(idempotency_key uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare previous integer; added integer;
begin
 previous:=internal.mark_all_notifications_read_before_team_updates(idempotency_key);
 added:=internal.mark_team_notifications_read_for_actor(idempotency_key);return previous+added;
end$$;

create function api.get_team_notifications() returns jsonb language sql stable security invoker set search_path='' as $$select internal.get_team_notifications_for_actor()$$;
create function api.mark_team_notifications_read(idempotency_key uuid) returns integer language sql security invoker set search_path='' as $$select internal.mark_team_notifications_read_for_actor(idempotency_key)$$;
create function api.set_team_notification_preferences(p_team_id uuid,p_news boolean,p_results boolean,p_reports boolean,p_schedule boolean,p_expected_revision bigint)
returns bigint language sql security invoker set search_path='' as $$select internal.set_team_notification_preferences_for_actor(p_team_id,p_news,p_results,p_reports,p_schedule,p_expected_revision)$$;
create or replace function api.list_notification_center(page_before timestamptz default null,page_limit integer default 50)
returns jsonb language sql stable security invoker set search_path='' as $$select internal.list_notification_center_for_actor(page_before,page_limit)$$;
create or replace function api.set_notification_state(notification_id uuid,state text,idempotency_key uuid)
returns bigint language sql security invoker set search_path='' as $$select internal.set_notification_state_for_actor(notification_id,state,idempotency_key)$$;
create or replace function api.mark_all_notifications_read(idempotency_key uuid)
returns integer language sql security invoker set search_path='' as $$select internal.mark_all_notifications_read_for_actor(idempotency_key)$$;
revoke all on function internal.capture_team_update(),internal.team_notification_channels_for_actor(),internal.team_notification_items_for_actor(),
 internal.get_team_notifications_for_actor(),internal.set_team_notification_preferences_for_actor(uuid,boolean,boolean,boolean,boolean,bigint),
 internal.list_notification_center_for_actor(timestamptz,integer),internal.set_notification_state_for_actor(uuid,text,uuid),internal.mark_all_notifications_read_for_actor(uuid),
 internal.mark_team_notifications_read_for_actor(uuid),api.mark_team_notifications_read(uuid),
 api.list_notification_center(timestamptz,integer),api.set_notification_state(uuid,text,uuid),api.mark_all_notifications_read(uuid),
 api.get_team_notifications(),api.set_team_notification_preferences(uuid,boolean,boolean,boolean,boolean,bigint) from public,anon,authenticated;
grant execute on function internal.get_team_notifications_for_actor(),internal.set_team_notification_preferences_for_actor(uuid,boolean,boolean,boolean,boolean,bigint),
 internal.list_notification_center_for_actor(timestamptz,integer),internal.set_notification_state_for_actor(uuid,text,uuid),internal.mark_all_notifications_read_for_actor(uuid),
 internal.mark_team_notifications_read_for_actor(uuid),api.mark_team_notifications_read(uuid),
 api.list_notification_center(timestamptz,integer),api.set_notification_state(uuid,text,uuid),api.mark_all_notifications_read(uuid),
 api.get_team_notifications(),api.set_team_notification_preferences(uuid,boolean,boolean,boolean,boolean,bigint) to authenticated;
notify pgrst,'reload schema';
