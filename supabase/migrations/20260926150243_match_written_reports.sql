create table core.match_reports(
 event_id uuid primary key references core.events(id) on delete cascade,
 body text not null default '' check(length(body)<=10000),
 published boolean not null default false,
 revision bigint not null default 1 check(revision>0),
 updated_by uuid not null references core.profiles(id),
 updated_at timestamptz not null default now(),
 check(not published or length(btrim(body))>0)
);
create index match_reports_actor_idx on core.match_reports(updated_by);
alter table core.match_reports enable row level security;
create policy match_reports_no_direct_access on core.match_reports for all to authenticated using(false) with check(false);
revoke all on core.match_reports from public,anon,authenticated;
alter table public_api.match_result_projections add column report_text text;

create function internal.fill_public_match_report() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 select body into new.report_text from core.match_reports where event_id=new.event_public_id and published;
 return new;
end$$;
revoke all on function internal.fill_public_match_report() from public,anon,authenticated;
create trigger fill_public_match_report before insert or update on public_api.match_result_projections
for each row execute function internal.fill_public_match_report();

create function internal.get_match_report_for_actor(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare e core.events%rowtype; report core.match_reports%rowtype; can_publish boolean;
begin
 select * into e from core.events where id=p_event_id;
 if auth.uid() is null or e.id is null or e.event_type<>'match' or not internal.actor_can_read_event(p_event_id)
 then raise insufficient_privilege using message='not_found';end if;
 select * into report from core.match_reports where event_id=p_event_id;
 can_publish:=coalesce(internal.actor_has_capability(e.club_id,e.owning_team_id,'publication.manage'),false);
 return jsonb_build_object('body',coalesce(report.body,''),'published',coalesce(report.published,false),
  'revision',coalesce(report.revision,0),'can_publish',can_publish,
  'can_edit',e.archived_at is null and e.state in('scheduled','completed') and internal.actor_can_manage_event(p_event_id)
   and (not coalesce(report.published,false) or can_publish));
end$$;

create function internal.save_match_report_for_actor(p_command_id uuid,p_event_id uuid,
 p_expected_revision bigint,p_body text,p_publish boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare e core.events%rowtype; current_report jsonb; receipt jsonb; new_revision bigint;
 club_slug text; team_slug text; text_value text:=btrim(p_body);
begin
 perform internal.assert_match_manager(p_event_id);
 perform pg_advisory_xact_lock(hashtextextended(p_event_id::text,0));
 select * into e from core.events where id=p_event_id for update;
 current_report:=internal.get_match_report_for_actor(p_event_id);
 if not(current_report->>'can_edit')::boolean then raise insufficient_privilege using message='not_found';end if;
 if p_expected_revision is null or p_body is null or length(p_body)>10000 or p_publish is null
  or (p_publish and length(text_value)=0) then raise invalid_parameter_value using message='invalid_report';end if;
 if p_publish and not(current_report->>'can_publish')::boolean then raise insufficient_privilege using message='not_found';end if;
 if not internal.register_match_command(p_command_id,p_event_id,p_expected_revision,'save_written_report',
  jsonb_build_object('body',text_value,'published',p_publish)) then
  select command.result into receipt from audit.match_commands command where command_id=p_command_id;return receipt;
 end if;
 if (current_report->>'revision')::bigint<>p_expected_revision then raise serialization_failure using message='stale_revision';end if;
 if not exists(select 1 from core.match_workspaces where event_id=p_event_id and state='completed') then
  raise check_violation using message='completed_result_required';end if;
 insert into core.match_reports(event_id,body,published,updated_by)
 values(p_event_id,text_value,p_publish,auth.uid())
 on conflict(event_id) do update set body=excluded.body,published=excluded.published,
  revision=core.match_reports.revision+1,updated_by=excluded.updated_by,updated_at=now()
 returning revision into new_revision;
 -- The existing score remains the publication boundary. Draft text never enters the projection.
 update public_api.match_result_projections set report_text=null where event_public_id=p_event_id;
 select c.slug,t.slug into club_slug,team_slug from core.team_publication_settings s
  join public_api.team_projections t on t.public_id=s.public_id
  join public_api.club_projections c on c.public_id=t.club_public_id where s.team_id=e.owning_team_id;
 if club_slug is not null then
  insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,requested_revision,action,affected_paths,created_by)
  values(e.club_id,'event',e.id,new_revision,'invalidate',array['/'||club_slug,'/'||club_slug||'/'||team_slug],auth.uid())
  on conflict(club_id,aggregate_type,aggregate_id,requested_revision,action) do update
  set state='pending',attempts=0,completed_at=null,last_error_code=null,available_at=now();
 end if;
 receipt:=internal.get_match_report_for_actor(p_event_id);
 update audit.match_commands set result=receipt where command_id=p_command_id;
 return receipt;
end$$;

create function api.get_match_report(p_event_id uuid) returns jsonb language sql security invoker set search_path='' as $$
 select internal.get_match_report_for_actor(p_event_id)$$;
create function api.save_match_report(p_command_id uuid,p_event_id uuid,p_expected_revision bigint,p_body text,p_publish boolean)
returns jsonb language sql security invoker set search_path='' as $$
 select internal.save_match_report_for_actor(p_command_id,p_event_id,p_expected_revision,p_body,p_publish)$$;
revoke all on function internal.get_match_report_for_actor(uuid),internal.save_match_report_for_actor(uuid,uuid,bigint,text,boolean),
 api.get_match_report(uuid),api.save_match_report(uuid,uuid,bigint,text,boolean) from public,anon;
grant execute on function internal.get_match_report_for_actor(uuid),internal.save_match_report_for_actor(uuid,uuid,bigint,text,boolean),
 api.get_match_report(uuid),api.save_match_report(uuid,uuid,bigint,text,boolean) to authenticated;

-- Extend existing protected read paths; preserve their runtime, visibility and rate gates.
do $$ declare definition text; signature text;
begin
 foreach signature in array array['internal.public_list_team_results(uuid,text)',
  'internal.get_personal_dashboard_content_for_actor()'] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  if position('r.score_us,r.score_opponent' in definition)=0 then raise exception 'report_read_contract_changed';end if;
  execute replace(definition,'r.score_us,r.score_opponent','r.score_us,r.score_opponent,r.report_text');
 end loop;
end$$;
notify pgrst,'reload schema';
