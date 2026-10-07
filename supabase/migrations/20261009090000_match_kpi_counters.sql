-- Live KPI counters in Matchläge (step 2 of event follow-up). A tap on +/−
-- for a counted KPI goal (shots, corners, ball wins …) is an idempotent match
-- command that adds or voids a 'kpi' match fact; the goal's value is the
-- number of active ticks, so the follow-up shows it without manual entry.
-- Values can still be corrected afterwards with api.record_event_kpi_value.

create function internal.record_match_kpi_for_actor(
 p_command_id uuid,p_event_id uuid,p_target_id uuid,p_delta integer,p_minute integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare workspace core.match_workspaces%rowtype; target_row core.event_kpi_targets%rowtype; result_value jsonb;
 new_fact_id uuid; fact core.match_facts%rowtype; first_tick boolean; tick_count integer;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_event_id::text,0));
 perform internal.ensure_match_workspace(p_event_id);
 if not internal.register_match_command(p_command_id,p_event_id,null,'record_kpi',
  jsonb_build_object('target_id',p_target_id,'delta',p_delta,'minute',p_minute)) then
  select command.result into result_value from audit.match_commands command where command.command_id=p_command_id; return result_value; end if;
 select * into workspace from core.match_workspaces where event_id=p_event_id for update;
 if workspace.state<>'live' then raise check_violation using message='match_not_live'; end if;
 select * into target_row from core.event_kpi_targets where id=p_target_id and event_id=p_event_id for update;
 if target_row.id is null or target_row.source<>'manual' or target_row.value_type<>'count' then
  raise invalid_parameter_value using message='invalid_kpi'; end if;
 if p_delta not in(-1,1) or p_minute is null or p_minute not between 0 and 300 then
  raise invalid_parameter_value using message='invalid_fact'; end if;
 first_tick:=not exists(select 1 from core.match_facts f where f.event_id=p_event_id and f.fact_type='kpi');
 if p_delta=1 then
  new_fact_id:=gen_random_uuid();
  insert into core.match_facts(id,event_id,minute,fact_type,side,club_id,detail,source_command_id,created_by,updated_by)
  values(new_fact_id,p_event_id,p_minute,'kpi','us',workspace.club_id,
   jsonb_build_object('target_id',target_row.id,'kpi_key',target_row.kpi_key),p_command_id,auth.uid(),auth.uid());
  insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id)
  values(new_fact_id,p_event_id,1,(select to_jsonb(f) from core.match_facts f where f.id=new_fact_id),'created',auth.uid());
 else
  select * into fact from core.match_facts f where f.event_id=p_event_id and f.fact_type='kpi' and f.state='active'
   and f.detail->>'target_id'=target_row.id::text order by f.created_at desc,f.id desc limit 1 for update;
  if fact.id is null then raise invalid_parameter_value using message='invalid_fact'; end if;
  update core.match_facts set state='voided',voided_at=now(),voided_by=auth.uid(),void_reason='kpi_minus',
   fact_revision=fact_revision+1,updated_at=now(),updated_by=auth.uid() where id=fact.id returning * into fact;
  insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id,reason)
  values(fact.id,p_event_id,fact.fact_revision,to_jsonb(fact),'voided',auth.uid(),'kpi_minus');
 end if;
 -- Once counters are in use, an untouched counter means zero, not "missing".
 if first_tick then
  update core.event_kpi_targets set actual_value=0,actual_recorded_at=now(),actual_recorded_by=auth.uid(),revision=revision+1,updated_at=now()
  where event_id=p_event_id and id<>target_row.id and source='manual' and value_type='count' and actual_value is null;
 end if;
 select count(*) into tick_count from core.match_facts f where f.event_id=p_event_id and f.fact_type='kpi' and f.state='active'
  and f.detail->>'target_id'=target_row.id::text;
 update core.event_kpi_targets set actual_value=tick_count,actual_recorded_at=now(),actual_recorded_by=auth.uid(),
  revision=revision+1,updated_at=now() where id=target_row.id returning * into target_row;
 return internal.finish_match_command(p_command_id,p_event_id,
  jsonb_build_object('target_id',target_row.id,'value',tick_count,'revision',target_row.revision,'match_event_id',new_fact_id));
end$$;

create function api.record_match_kpi_v2(p_command_id uuid,p_event_id uuid,p_target_id uuid,p_delta integer,p_minute integer)
returns jsonb language sql security invoker set search_path='' as
$$select internal.record_match_kpi_for_actor(p_command_id,p_event_id,p_target_id,p_delta,p_minute)$$;

revoke all on function internal.record_match_kpi_for_actor(uuid,uuid,uuid,integer,integer),
 api.record_match_kpi_v2(uuid,uuid,uuid,integer,integer) from public,anon,authenticated;
grant execute on function internal.record_match_kpi_for_actor(uuid,uuid,uuid,integer,integer),
 api.record_match_kpi_v2(uuid,uuid,uuid,integer,integer) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261009090000_match_kpi_counters','greenfield','Live KPI counters in Matchläge (event follow-up step 2)');
notify pgrst,'reload schema';
