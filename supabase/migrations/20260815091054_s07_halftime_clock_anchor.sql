alter table core.match_workspaces
  add column period_minutes integer[] not null default array[45,45],
  add column current_period integer not null default 1,
  add constraint match_workspaces_period_minutes_valid check(cardinality(period_minutes) between 2 and 8 and 0 < all(period_minutes) and 120 >= all(period_minutes)),
  add constraint match_workspaces_current_period_valid check(current_period between 1 and cardinality(period_minutes));

alter table core.match_facts drop constraint match_facts_fact_type_check;
alter table core.match_facts add constraint match_facts_fact_type_check check(fact_type in
 ('substitution','goal','card','injury','corner','free_kick','penalty','save','half_time','period_end','full_time','kpi','shot','score_adjustment'));

create function internal.transition_match_period_for_actor(p_command_id uuid,p_event_id uuid,p_action text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare workspace core.match_workspaces%rowtype; is_new boolean; command_type text;
 actual_elapsed_seconds integer; scheduled_minute integer; new_fact_id uuid:=gen_random_uuid(); result_value jsonb; new_revision bigint;
begin
 if p_action not in('end','resume') then raise invalid_parameter_value using message='invalid_period_action'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_event_id::text,0));
 workspace:=internal.ensure_match_workspace(p_event_id);
 command_type:=case p_action when 'end' then 'period_end' else 'period_resume' end;
 is_new:=internal.register_match_command(p_command_id,p_event_id,null,command_type,jsonb_build_object('action',p_action));
 if not is_new then select command.result into result_value from audit.match_commands command where command.command_id=p_command_id; return result_value; end if;
 select * into workspace from core.match_workspaces where event_id=p_event_id for update;
 if workspace.state<>'live' or workspace.match_started_at is null or workspace.current_period>=cardinality(workspace.period_minutes)
 then raise check_violation using message='invalid_transition'; end if;
 if p_action='end' then
  if workspace.match_paused_at is not null or exists(select 1 from core.match_facts fact where fact.event_id=p_event_id and fact.fact_type='period_end' and fact.state='active' and (fact.detail->>'period')::integer=workspace.current_period)
  then raise check_violation using message='invalid_transition'; end if;
  select sum(value)::integer into scheduled_minute from unnest(workspace.period_minutes) with ordinality period(value,number) where number<=workspace.current_period;
  actual_elapsed_seconds:=greatest(0,extract(epoch from(now()-workspace.match_started_at))::integer-workspace.paused_seconds);
  insert into core.match_facts(id,event_id,minute,fact_type,club_id,detail,source_command_id,created_by,updated_by)
  values(new_fact_id,p_event_id,scheduled_minute,'period_end',workspace.club_id,jsonb_build_object('period',workspace.current_period,'scheduled_minute',scheduled_minute,'elapsed_seconds',actual_elapsed_seconds),p_command_id,auth.uid(),auth.uid());
  insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id)
  values(new_fact_id,p_event_id,1,(select to_jsonb(fact) from core.match_facts fact where fact.id=new_fact_id),'created',auth.uid());
  update core.match_workspaces set match_paused_at=now() where event_id=p_event_id;
 else
  if workspace.match_paused_at is null then raise check_violation using message='invalid_transition'; end if;
  update core.match_workspaces set paused_seconds=paused_seconds+greatest(0,extract(epoch from(now()-match_paused_at))::integer),match_paused_at=null,current_period=current_period+1 where event_id=p_event_id;
 end if;
 update core.match_workspaces set revision=revision+1,updated_at=now(),updated_by=auth.uid() where event_id=p_event_id returning revision into new_revision;
 perform internal.recompute_match_projection(p_event_id);
 result_value:=jsonb_build_object('ok',true,'workspace_revision',new_revision);
 update audit.match_commands command set result=result_value where command.command_id=p_command_id;
 return result_value;
end$$;

create function api.transition_match_period_v2(p_command_id uuid,p_event_id uuid,p_action text)
returns void language plpgsql security invoker set search_path='' as $$begin perform internal.transition_match_period_for_actor(p_command_id,p_event_id,p_action); end$$;

create or replace function api.get_match_v2_snapshot(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare value jsonb;
begin
 if auth.uid() is null or not internal.actor_can_read_event(p_event_id) then raise insufficient_privilege using message='not_found'; end if;
 select jsonb_build_object('schema_version',2,'server_now',now(),'event_id',workspace.event_id,'state',workspace.state,
  'revision',workspace.revision,'roster_revision',workspace.roster_revision,
  'clock',jsonb_build_object('started_at',workspace.match_started_at,'paused_at',workspace.match_paused_at,'paused_seconds',workspace.paused_seconds,'completed_at',workspace.completed_at,'period_minutes',workspace.period_minutes,'current_period',workspace.current_period),
  'plan',to_jsonb(plan),'projection',to_jsonb(projection),
  'facts',coalesce((select jsonb_agg(to_jsonb(fact) order by fact.minute,fact.created_at,fact.id) from core.match_facts fact where fact.event_id=p_event_id),'[]'::jsonb),
  'cursor',coalesce((select command.created_at::text||'/'||command.command_id::text from audit.match_commands command where command.event_id=p_event_id order by command.created_at desc,command.command_id desc limit 1),'0')) into value
 from core.match_workspaces workspace left join core.match_plans plan on plan.event_id=workspace.event_id left join core.match_projections projection on projection.event_id=workspace.event_id where workspace.event_id=p_event_id;
 return value;
end$$;

revoke all on function internal.transition_match_period_for_actor(uuid,uuid,text),api.transition_match_period_v2(uuid,uuid,text) from public,anon;
grant execute on function internal.transition_match_period_for_actor(uuid,uuid,text),api.transition_match_period_v2(uuid,uuid,text) to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815091054_s07_halftime_clock_anchor','greenfield','S07 physical UI closure: configurable multi-period clock anchors');
notify pgrst,'reload schema';
