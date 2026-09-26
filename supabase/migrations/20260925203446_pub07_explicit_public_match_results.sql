-- Explicit snapshots of completed scores. No players, statistics or live scores.
create table public_api.match_result_projections(
 event_public_id uuid primary key references public_api.event_projections(public_id) on delete cascade,
 score_us integer not null check(score_us>=0),score_opponent integer not null check(score_opponent>=0),
 source_match_revision bigint not null,published_at timestamptz not null default now()
);
alter table public_api.match_result_projections enable row level security;
create policy match_result_no_client_access on public_api.match_result_projections for all to authenticated using(false) with check(false);
revoke all on public_api.match_result_projections from public,anon,authenticated;

create function internal.clear_public_match_result() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_schema='public_api' then delete from public_api.match_result_projections where event_public_id=old.public_id;
 elsif tg_table_name='events' then delete from public_api.match_result_projections where event_public_id=old.id;
 else delete from public_api.match_result_projections where event_public_id=old.event_id;end if;
 return new;
end;$$;
revoke all on function internal.clear_public_match_result() from public,anon,authenticated;
create trigger clear_result_on_event_projection_update after update on public_api.event_projections for each row execute function internal.clear_public_match_result();
create trigger clear_result_on_score_correction after update on core.match_projections for each row
 when(old.score_us is distinct from new.score_us or old.score_opponent is distinct from new.score_opponent or old.revision is distinct from new.revision)
 execute function internal.clear_public_match_result();
create trigger clear_result_on_match_reopen after update on core.match_workspaces for each row
 when(new.state<>'completed') execute function internal.clear_public_match_result();
create trigger clear_result_on_event_cancel after update on core.events for each row
 when(new.state not in('scheduled','completed')) execute function internal.clear_public_match_result();
create trigger clear_result_on_score_delete after delete on core.match_projections for each row execute function internal.clear_public_match_result();
create trigger clear_result_on_workspace_delete after delete on core.match_workspaces for each row execute function internal.clear_public_match_result();
create trigger clear_result_on_source_event_delete after delete on core.events for each row execute function internal.clear_public_match_result();

create function internal.configure_event_publication_with_result_for_actor(target_event_id uuid,new_state text,
 new_public_title text,new_publish_location boolean,expected_revision bigint,idempotency_key uuid,new_publish_result boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();event_row core.events%rowtype;setting core.event_publication_settings%rowtype;
 team_setting core.team_publication_settings%rowtype;club_setting core.club_publication_settings%rowtype;
 location_name text;existing jsonb;new_revision bigint;score core.match_projections%rowtype;
begin
 select * into event_row from core.events where id=target_event_id for update;
 if actor_id is null or event_row.id is null or not internal.actor_has_capability(event_row.club_id,event_row.owning_team_id,'publication.manage')
 then raise insufficient_privilege using message='not_found';end if;
 if new_state is null or new_publish_result is null or new_state not in('private','published') or(new_public_title is not null and length(btrim(new_public_title)) not between 1 and 160)
 then raise invalid_parameter_value using message='invalid_publication';end if;
 select result into existing from internal.command_deduplication d where d.actor_profile_id=actor_id
  and d.command_type='publication.event.configure.v2' and d.idempotency_key=configure_event_publication_with_result_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 select * into setting from core.event_publication_settings where event_id=target_event_id for update;
 if coalesce(setting.revision,0)<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 select * into team_setting from core.team_publication_settings where team_id=event_row.owning_team_id;
 select * into club_setting from core.club_publication_settings where club_id=event_row.club_id;
 if new_state='published' and new_publish_result then
  select p.* into score from core.match_projections p join core.match_workspaces w on w.event_id=p.event_id
   where p.event_id=target_event_id and w.state='completed' and event_row.event_type='match' for share of p,w;
  if score.event_id is null then raise check_violation using message='completed_result_required';end if;
 end if;
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
 if new_state='published' and new_publish_result then
  insert into public_api.match_result_projections(event_public_id,score_us,score_opponent,source_match_revision)
  values(event_row.id,score.score_us,score.score_opponent,score.revision)
  on conflict(event_public_id) do update set score_us=excluded.score_us,score_opponent=excluded.score_opponent,source_match_revision=excluded.source_match_revision,published_at=now();
 end if;
 insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,requested_revision,action,affected_paths,created_by)
 values(event_row.club_id,'event',event_row.id,new_revision,'invalidate',
  case when club_setting.slug is null or team_setting.slug is null then array[]::text[]
   else array['/'||club_setting.slug,'/'||club_setting.slug||'/'||team_setting.slug] end,actor_id);
 existing:=jsonb_build_object('event_id',event_row.id,'state',new_state,'revision',new_revision,
  'publish_result',new_state='published' and new_publish_result,
  'published_fields',case when new_state='published' and new_publish_result then array['score_us','score_opponent'] else array[]::text[] end||array['title','starts_at','event_type']||case when new_publish_location then array['location_name'] else array[]::text[] end);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'publication.event.configure.v2',existing);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(event_row.club_id,actor_id,'publication.event.configure.v2','event',event_row.id,new_revision,
  jsonb_build_object('state',new_state,'publish_location',new_publish_location,'publish_result',new_state='published' and new_publish_result));
 return existing;
end;$$;


drop function api.configure_event_publication(uuid,text,text,boolean,bigint,uuid);
create function api.configure_event_publication(event_id uuid,state text,public_title text,publish_location boolean,
 expected_revision bigint,idempotency_key uuid,publish_result boolean default false)
returns jsonb language sql security invoker set search_path='' as $$
select internal.configure_event_publication_with_result_for_actor(event_id,state,public_title,publish_location,expected_revision,idempotency_key,publish_result)$$;
revoke all on function internal.configure_event_publication_with_result_for_actor(uuid,text,text,boolean,bigint,uuid,boolean),
 api.configure_event_publication(uuid,text,text,boolean,bigint,uuid,boolean) from public,anon,authenticated;
grant execute on function internal.configure_event_publication_with_result_for_actor(uuid,text,text,boolean,bigint,uuid,boolean),
 api.configure_event_publication(uuid,text,text,boolean,bigint,uuid,boolean) to authenticated;
create or replace function internal.get_publication_management_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); can_manage_club boolean; can_manage_team boolean; result jsonb;
begin
  can_manage_club:=actor_id is not null and internal.actor_has_capability(target_club_id,null,'publication.manage');
  select exists(
    select 1 from core.teams team
    where team.club_id=target_club_id
      and internal.actor_has_capability(target_club_id,team.id,'publication.manage')
  ) into can_manage_team;
  if actor_id is null or not (can_manage_club or can_manage_team) then
    raise insufficient_privilege using message='not_found';
  end if;
  select jsonb_build_object(
    'events',coalesce((select jsonb_agg(jsonb_build_object(
      'id',event_row.id,'team_id',event_row.owning_team_id,'team_name',team.name,
      'title',event_row.title,'event_type',event_row.event_type,'starts_at',event_row.starts_at,
      'event_state',event_row.state,'publication_state',coalesce(setting.state,'private'),
      'public_title',setting.public_title,'publish_location',coalesce(setting.publish_location,false),
      'publish_result',exists(select 1 from public_api.match_result_projections r where r.event_public_id=event_row.id),
      'result_available',exists(select 1 from core.match_workspaces w join core.match_projections p on p.event_id=w.event_id where w.event_id=event_row.id and w.state='completed' and event_row.event_type='match'),
      'score_us',(select p.score_us from core.match_projections p join core.match_workspaces w on w.event_id=p.event_id where p.event_id=event_row.id and w.state='completed'),
      'score_opponent',(select p.score_opponent from core.match_projections p join core.match_workspaces w on w.event_id=p.event_id where p.event_id=event_row.id and w.state='completed'),
      'revision',coalesce(setting.revision,0)
    ) order by event_row.starts_at,event_row.id)
      from core.events event_row join core.teams team on team.id=event_row.owning_team_id and team.club_id=event_row.club_id
      left join core.event_publication_settings setting on setting.event_id=event_row.id
      where event_row.club_id=target_club_id and event_row.state in('scheduled','completed')
        and event_row.starts_at between now()-interval '90 days' and now()+interval '365 days'
        and internal.actor_has_capability(target_club_id,event_row.owning_team_id,'publication.manage')),'[]'::jsonb),
    'partners',case when can_manage_club then coalesce((select jsonb_agg(jsonb_build_object(
      'id',partner.id,'name',partner.name,'website_url',partner.website_url,'state',partner.state,
      'sort_order',partner.sort_order,'revision',partner.revision,
      'media_status',case when asset.id is null then 'not_configured' else asset.variant_state end
    ) order by partner.sort_order,partner.id)
      from core.public_partners partner left join core.public_media_assets asset on asset.id=partner.logo_asset_id
      where partner.club_id=target_club_id),'[]'::jsonb) else '[]'::jsonb end,
    'can_manage_partners',can_manage_club,
    'media_upload_status','not_configured'
  ) into result;
  return result;
end;$$;


notify pgrst,'reload schema';

create function internal.public_list_team_results(target_team_id uuid,ip_sha256_hex text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb;items jsonb;
begin
 if not internal.public_runtime_enabled() then return jsonb_build_object('available',false,'items','[]'::jsonb);end if;
 rate:=internal.consume_public_rate_limit(ip_sha256_hex,'read',null);
 if not(rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited';end if;
 select coalesce(jsonb_agg(to_jsonb(page) order by starts_at desc,id desc),'[]'::jsonb) into items from(
  select e.public_id id,e.title,e.starts_at,r.score_us,r.score_opponent
  from public_api.match_result_projections r join public_api.event_projections e on e.public_id=r.event_public_id
  join public_api.team_projections t on t.public_id=e.team_public_id join public_api.club_projections c on c.public_id=t.club_public_id
  where t.public_id=target_team_id and t.visibility='published' and c.visibility='published'
  order by e.starts_at desc,e.public_id desc limit 10
 ) page;
 return jsonb_build_object('available',true,'items',items);
end;$$;
create function api.public_list_team_results(team_id uuid,ip_hash text)
returns jsonb language sql security invoker set search_path='' as $$select internal.public_list_team_results(team_id,ip_hash)$$;
revoke all on function internal.public_list_team_results(uuid,text),api.public_list_team_results(uuid,text) from public,anon,authenticated;
grant execute on function internal.public_list_team_results(uuid,text),api.public_list_team_results(uuid,text) to service_role;
notify pgrst,'reload schema';
