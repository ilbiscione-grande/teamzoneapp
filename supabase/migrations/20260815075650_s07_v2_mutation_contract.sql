create table audit.match_fact_versions(
  id uuid primary key default gen_random_uuid(),fact_id uuid not null references core.match_facts(id) on delete restrict,
  event_id uuid not null references core.match_workspaces(event_id) on delete restrict,
  fact_revision bigint not null, snapshot jsonb not null, action text not null check(action in('created','edited','voided')),
  actor_profile_id uuid not null references core.profiles(id),reason text,created_at timestamptz not null default now(),
  unique(fact_id,fact_revision)
);
alter table audit.match_fact_versions enable row level security;
create policy match_fact_versions_no_direct_read on audit.match_fact_versions for select to authenticated using(false);
revoke insert,update,delete,truncate on audit.match_fact_versions from anon,authenticated;

create function internal.assert_match_roster_json(p_event_id uuid,p_starting_xi jsonb,p_substitution_checklist jsonb)
returns void language plpgsql stable security definer set search_path='' as $$
declare item jsonb; person_id uuid;
begin
 if jsonb_typeof(coalesce(p_starting_xi,'[]'))<>'array' or jsonb_typeof(coalesce(p_substitution_checklist,'[]'))<>'array'
 then raise invalid_parameter_value using message='invalid_roster'; end if;
 if exists(select 1 from jsonb_array_elements(coalesce(p_starting_xi,'[]')) value group by value->>'member_id' having count(*)>1)
 then raise invalid_parameter_value using message='duplicate_roster_member'; end if;
 for item in select value from jsonb_array_elements(coalesce(p_starting_xi,'[]')) loop
  person_id:=nullif(item->>'member_id','')::uuid;
  if person_id is null or nullif(item->>'slot','') is null then raise invalid_parameter_value using message='invalid_roster'; end if;
  perform internal.assert_frozen_match_member(p_event_id,person_id);
 end loop;
 for item in select value from jsonb_array_elements(coalesce(p_substitution_checklist,'[]')) loop
  perform internal.assert_frozen_match_member(p_event_id,nullif(item->>'player_out_id','')::uuid);
  perform internal.assert_frozen_match_member(p_event_id,nullif(item->>'player_in_id','')::uuid);
 end loop;
end$$;

create function internal.apply_match_command_v2(p_command_id uuid,p_event_id uuid,p_expected_revision bigint,p_command_type text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare workspace core.match_workspaces%rowtype; plan core.match_plans%rowtype; fact core.match_facts%rowtype;
 is_new boolean; new_revision bigint; new_fact_id uuid:=gen_random_uuid(); result_value jsonb; current_score integer;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_event_id::text,0));
 workspace:=internal.ensure_match_workspace(p_event_id);
 is_new:=internal.register_match_command(p_command_id,p_event_id,p_expected_revision,p_command_type,p_payload);
 if not is_new then select command.result into result_value from audit.match_commands command where command_id=p_command_id; return result_value; end if;

 if p_command_type='save_plan' then
  if workspace.state<>'planning' then raise check_violation using message='match_locked'; end if;
  select * into plan from core.match_plans where event_id=p_event_id for update;
  if (plan.event_id is null and coalesce(p_expected_revision,0)<>0) or (plan.event_id is not null and p_expected_revision is distinct from plan.revision)
  then raise serialization_failure using message='stale_revision'; end if;
  perform internal.assert_match_roster_json(p_event_id,p_payload->'starting_xi',p_payload->'substitution_checklist');
  new_revision:=coalesce(plan.revision,0)+1;
  insert into core.match_plans(event_id,revision,formation,starting_xi,substitution_checklist,set_pieces_notes,tactics_notes,match_kpis,key_opponents_notes,kpi_review,board_background,board_strokes,updated_by)
  values(p_event_id,new_revision,p_payload->>'formation',coalesce(p_payload->'starting_xi','[]'),coalesce(p_payload->'substitution_checklist','[]'),coalesce(p_payload->>'set_pieces_notes',''),coalesce(p_payload->>'tactics_notes',''),coalesce(p_payload->>'match_kpis',''),coalesce(p_payload->>'key_opponents_notes',''),coalesce(p_payload->>'kpi_review',''),coalesce(p_payload->>'board_background','fullPitch'),coalesce(p_payload->'board_strokes','[]'),auth.uid())
  on conflict(event_id) do update set revision=excluded.revision,formation=excluded.formation,starting_xi=excluded.starting_xi,substitution_checklist=excluded.substitution_checklist,set_pieces_notes=excluded.set_pieces_notes,tactics_notes=excluded.tactics_notes,match_kpis=excluded.match_kpis,key_opponents_notes=excluded.key_opponents_notes,kpi_review=excluded.kpi_review,board_background=excluded.board_background,board_strokes=excluded.board_strokes,updated_at=now(),updated_by=excluded.updated_by;
  result_value:=jsonb_build_object('revision',new_revision);

 elsif p_command_type='record_event' then
  if workspace.state<>'live' then raise check_violation using message='match_not_live'; end if;
  if p_payload->>'type' not in('substitution','goal','card','injury','corner','free_kick','penalty','save','half_time','shot')
   or (p_payload->>'side' is not null and p_payload->>'side' not in('us','opponent')) then raise invalid_parameter_value using message='invalid_fact'; end if;
  perform internal.assert_frozen_match_member(p_event_id,nullif(p_payload->>'player_id','')::uuid);
  perform internal.assert_frozen_match_member(p_event_id,nullif(p_payload->>'secondary_player_id','')::uuid);
  insert into core.match_facts(id,event_id,minute,fact_type,side,club_person_id,secondary_club_person_id,club_id,detail,source_command_id,created_by,updated_by)
  values(new_fact_id,p_event_id,greatest(0,(p_payload->>'minute')::integer),p_payload->>'type',nullif(p_payload->>'side',''),nullif(p_payload->>'player_id','')::uuid,nullif(p_payload->>'secondary_player_id','')::uuid,workspace.club_id,coalesce(p_payload->'detail','{}'),p_command_id,auth.uid(),auth.uid());
  insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id) values(new_fact_id,p_event_id,1,(select to_jsonb(f) from core.match_facts f where id=new_fact_id),'created',auth.uid());
  result_value:=jsonb_build_object('match_event_id',new_fact_id);

 elsif p_command_type in('update_event','void_event') then
  if workspace.state<>'live' then raise check_violation using message='match_not_live'; end if;
  select * into fact from core.match_facts where id=(p_payload->>'match_event_id')::uuid and event_id=p_event_id for update;
  if fact.id is null or fact.state<>'active' or fact.fact_type in('full_time','score_adjustment') then raise invalid_parameter_value using message='invalid_fact'; end if;
  if p_command_type='update_event' then
   perform internal.assert_frozen_match_member(p_event_id,nullif(p_payload->>'player_id','')::uuid);
   perform internal.assert_frozen_match_member(p_event_id,nullif(p_payload->>'secondary_player_id','')::uuid);
   update core.match_facts set minute=greatest(0,(p_payload->>'minute')::integer),side=nullif(p_payload->>'side',''),club_person_id=nullif(p_payload->>'player_id','')::uuid,secondary_club_person_id=nullif(p_payload->>'secondary_player_id','')::uuid,detail=coalesce(p_payload->'detail','{}'),fact_revision=fact_revision+1,updated_at=now(),updated_by=auth.uid() where id=fact.id returning * into fact;
   insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id) values(fact.id,p_event_id,fact.fact_revision,to_jsonb(fact),'edited',auth.uid());
  else
   update core.match_facts set state='voided',voided_at=now(),voided_by=auth.uid(),void_reason='v2_void',fact_revision=fact_revision+1,updated_at=now(),updated_by=auth.uid() where id=fact.id returning * into fact;
   insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id,reason) values(fact.id,p_event_id,fact.fact_revision,to_jsonb(fact),'voided',auth.uid(),'v2_void');
  end if;
  result_value:=jsonb_build_object('ok',true);

 elsif p_command_type='adjust_score' then
  if workspace.state<>'live' or p_payload->>'side' not in('us','opponent') or (p_payload->>'delta')::integer not between -100 and 100 or (p_payload->>'delta')::integer=0 then raise invalid_parameter_value using message='invalid_score_adjustment'; end if;
  select case when p_payload->>'side'='us' then score_us else score_opponent end into current_score from core.match_projections where event_id=p_event_id;
  if current_score+(p_payload->>'delta')::integer<0 then raise invalid_parameter_value using message='negative_score'; end if;
  insert into core.match_facts(id,event_id,minute,fact_type,side,club_id,detail,source_command_id,created_by,updated_by)
  values(new_fact_id,p_event_id,greatest(0,(p_payload->>'minute')::integer),'score_adjustment',p_payload->>'side',workspace.club_id,jsonb_build_object('delta',(p_payload->>'delta')::integer),p_command_id,auth.uid(),auth.uid());
  insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id) values(new_fact_id,p_event_id,1,(select to_jsonb(f) from core.match_facts f where id=new_fact_id),'created',auth.uid());
  result_value:=jsonb_build_object('ok',true);

 elsif p_command_type='adjust_kpi' then
  if workspace.state<>'live' or nullif(btrim(p_payload->>'kpi_id'),'') is null or (p_payload->>'delta')::integer not in(-1,1) then raise invalid_parameter_value using message='invalid_kpi'; end if;
  insert into core.match_facts(id,event_id,minute,fact_type,club_id,detail,source_command_id,created_by,updated_by)
  values(new_fact_id,p_event_id,greatest(0,(p_payload->>'minute')::integer),'kpi',workspace.club_id,p_payload,p_command_id,auth.uid(),auth.uid());
  insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id) values(new_fact_id,p_event_id,1,(select to_jsonb(f) from core.match_facts f where id=new_fact_id),'created',auth.uid()); result_value:=jsonb_build_object('ok',true);

 elsif p_command_type like 'clock_%' then
  if p_command_type='clock_start' then
   if workspace.state<>'planning' or workspace.roster_revision=0 then raise check_violation using message='invalid_transition'; end if;
   update core.match_workspaces set state='live',match_started_at=now(),match_paused_at=null,paused_seconds=0 where event_id=p_event_id;
  elsif p_command_type='clock_pause' then
   if workspace.state<>'live' or workspace.match_paused_at is not null then raise check_violation using message='invalid_transition'; end if;
   update core.match_workspaces set match_paused_at=now() where event_id=p_event_id;
  elsif p_command_type='clock_resume' then
   if workspace.state<>'live' or workspace.match_paused_at is null then raise check_violation using message='invalid_transition'; end if;
   update core.match_workspaces set paused_seconds=paused_seconds+greatest(0,extract(epoch from(now()-match_paused_at))::integer),match_paused_at=null where event_id=p_event_id;
  elsif p_command_type='clock_unlock' then
   if workspace.state<>'completed' or nullif(btrim(p_payload->>'reason'),'') is null or not internal.actor_has_capability(workspace.club_id,workspace.team_id,'match.unlock') then raise insufficient_privilege using message='unlock_denied'; end if;
   update core.match_workspaces set state='live',completed_at=null,unlocked_at=now(),match_paused_at=null where event_id=p_event_id;
  else raise invalid_parameter_value using message='invalid_transition'; end if;
  result_value:=jsonb_build_object('ok',true);

 elsif p_command_type='complete_match' then
  if workspace.state<>'live' then raise check_violation using message='invalid_transition'; end if;
  insert into core.match_facts(id,event_id,minute,fact_type,club_id,detail,source_command_id,created_by,updated_by)
  values(new_fact_id,p_event_id,greatest(0,(p_payload->>'minute')::integer),'full_time',workspace.club_id,'{}',p_command_id,auth.uid(),auth.uid());
  insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id) values(new_fact_id,p_event_id,1,(select to_jsonb(f) from core.match_facts f where id=new_fact_id),'created',auth.uid());
  update core.match_workspaces set state='completed',completed_at=now(),match_paused_at=null where event_id=p_event_id; result_value:=jsonb_build_object('ok',true);

 elsif p_command_type='set_button_config' then
  select * into plan from core.match_plans where event_id=p_event_id for update;
  if plan.event_id is null or p_expected_revision is distinct from plan.revision or jsonb_typeof(coalesce(p_payload->'kpi_buttons','[]'))<>'array' then raise serialization_failure using message='stale_revision'; end if;
  new_revision:=plan.revision+1;
  update core.match_plans set revision=new_revision,kpi_buttons=coalesce(p_payload->'kpi_buttons','[]'),enabled_quick_actions=coalesce(p_payload->'enabled_quick_actions','[]'),updated_at=now(),updated_by=auth.uid() where event_id=p_event_id;
  result_value:=jsonb_build_object('revision',new_revision);

 elsif p_command_type='reset_match' then
  update core.match_facts set state='voided',voided_at=now(),voided_by=auth.uid(),void_reason='reset',fact_revision=fact_revision+1,updated_at=now(),updated_by=auth.uid() where event_id=p_event_id and state='active';
  insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id,reason)
  select fact.id,p_event_id,fact.fact_revision,to_jsonb(fact),'voided',auth.uid(),'reset' from core.match_facts fact where fact.event_id=p_event_id and fact.state='voided' and fact.void_reason='reset';
  update core.match_workspaces set state='planning',match_started_at=null,match_paused_at=null,paused_seconds=0,completed_at=null,unlocked_at=null where event_id=p_event_id;
  result_value:=jsonb_build_object('ok',true);
 else raise invalid_parameter_value using message='unknown_command'; end if;

 update core.match_workspaces set revision=revision+1,updated_at=now(),updated_by=auth.uid() where event_id=p_event_id returning revision into new_revision;
 perform internal.recompute_match_projection(p_event_id);
 result_value:=result_value||jsonb_build_object('workspace_revision',new_revision);
 update audit.match_commands command set result=result_value where command.command_id=p_command_id;
 return result_value;
end$$;

create function api.save_match_plan_v2(p_command_id uuid,p_event_id uuid,p_expected_revision bigint,p_formation text,p_starting_xi jsonb,p_substitution_checklist jsonb,p_set_pieces_notes text,p_tactics_notes text,p_match_kpis text,p_key_opponents_notes text,p_kpi_review text,p_board_background text,p_board_strokes jsonb) returns bigint language sql security invoker set search_path='' as $$select (internal.apply_match_command_v2(p_command_id,p_event_id,p_expected_revision,'save_plan',jsonb_build_object('formation',p_formation,'starting_xi',coalesce(p_starting_xi,'[]'),'substitution_checklist',coalesce(p_substitution_checklist,'[]'),'set_pieces_notes',coalesce(p_set_pieces_notes,''),'tactics_notes',coalesce(p_tactics_notes,''),'match_kpis',coalesce(p_match_kpis,''),'key_opponents_notes',coalesce(p_key_opponents_notes,''),'kpi_review',coalesce(p_kpi_review,''),'board_background',coalesce(p_board_background,'fullPitch'),'board_strokes',coalesce(p_board_strokes,'[]')))->>'revision')::bigint$$;
create function api.record_match_event_v2(p_command_id uuid,p_event_id uuid,p_minute integer,p_type text,p_side text default null,p_player_id uuid default null,p_secondary_player_id uuid default null,p_detail jsonb default '{}') returns uuid language sql security invoker set search_path='' as $$select (internal.apply_match_command_v2(p_command_id,p_event_id,null,'record_event',jsonb_build_object('minute',greatest(0,p_minute),'type',p_type,'side',p_side,'player_id',p_player_id,'secondary_player_id',p_secondary_player_id,'detail',coalesce(p_detail,'{}')))->>'match_event_id')::uuid$$;
create function api.update_match_event_v2(p_command_id uuid,p_match_event_id uuid,p_minute integer,p_side text,p_player_id uuid default null,p_secondary_player_id uuid default null,p_detail jsonb default '{}') returns void language plpgsql security definer set search_path='' as $$declare eid uuid;begin select event_id into eid from core.match_facts where id=p_match_event_id;if eid is null then raise insufficient_privilege using message='not_found';end if;perform internal.apply_match_command_v2(p_command_id,eid,null,'update_event',jsonb_build_object('match_event_id',p_match_event_id,'minute',greatest(0,p_minute),'side',p_side,'player_id',p_player_id,'secondary_player_id',p_secondary_player_id,'detail',coalesce(p_detail,'{}')));end$$;
create function api.void_match_event_v2(p_command_id uuid,p_match_event_id uuid) returns void language plpgsql security definer set search_path='' as $$declare eid uuid;begin select event_id into eid from core.match_facts where id=p_match_event_id;if eid is null then raise insufficient_privilege using message='not_found';end if;perform internal.apply_match_command_v2(p_command_id,eid,null,'void_event',jsonb_build_object('match_event_id',p_match_event_id));end$$;
create function api.adjust_match_score_v2(p_command_id uuid,p_event_id uuid,p_side text,p_delta integer,p_minute integer default 0) returns void language plpgsql security invoker set search_path='' as $$begin perform internal.apply_match_command_v2(p_command_id,p_event_id,null,'adjust_score',jsonb_build_object('side',p_side,'delta',p_delta,'minute',greatest(0,p_minute)));end$$;
create function api.adjust_match_kpi_v2(p_command_id uuid,p_event_id uuid,p_kpi_id text,p_label text,p_delta integer,p_minute integer) returns void language plpgsql security invoker set search_path='' as $$begin perform internal.apply_match_command_v2(p_command_id,p_event_id,null,'adjust_kpi',jsonb_build_object('kpi_id',p_kpi_id,'label',coalesce(p_label,''),'delta',p_delta,'minute',greatest(0,p_minute)));end$$;
create function api.transition_match_clock_v2(p_command_id uuid,p_event_id uuid,p_action text) returns void language plpgsql security invoker set search_path='' as $$begin perform internal.apply_match_command_v2(p_command_id,p_event_id,null,'clock_'||p_action,jsonb_build_object('action',p_action,'reason',case when p_action='unlock' then 'v2_compatibility_unlock' end));end$$;
create function api.complete_match_v2(p_command_id uuid,p_event_id uuid,p_minute integer) returns void language plpgsql security invoker set search_path='' as $$begin perform internal.apply_match_command_v2(p_command_id,p_event_id,null,'complete_match',jsonb_build_object('minute',greatest(0,p_minute)));end$$;
create function api.set_match_button_config_v2(p_command_id uuid,p_event_id uuid,p_expected_revision bigint,p_kpi_buttons jsonb,p_enabled_quick_actions jsonb) returns bigint language sql security invoker set search_path='' as $$select (internal.apply_match_command_v2(p_command_id,p_event_id,p_expected_revision,'set_button_config',jsonb_build_object('kpi_buttons',coalesce(p_kpi_buttons,'[]'),'enabled_quick_actions',coalesce(p_enabled_quick_actions,'[]')))->>'revision')::bigint$$;
create function api.reset_match_v2(p_command_id uuid,p_event_id uuid) returns void language plpgsql security invoker set search_path='' as $$begin perform internal.apply_match_command_v2(p_command_id,p_event_id,null,'reset_match','{}');end$$;
create function api.unlock_match_v2(p_command_id uuid,p_event_id uuid,p_reason text) returns void language plpgsql security invoker set search_path='' as $$begin perform internal.apply_match_command_v2(p_command_id,p_event_id,null,'clock_unlock',jsonb_build_object('action','unlock','reason',p_reason));end$$;

revoke all on function internal.assert_match_roster_json(uuid,jsonb,jsonb),internal.apply_match_command_v2(uuid,uuid,bigint,text,jsonb) from public,anon,authenticated;
grant execute on function internal.apply_match_command_v2(uuid,uuid,bigint,text,jsonb) to authenticated;
revoke all on function api.save_match_plan_v2(uuid,uuid,bigint,text,jsonb,jsonb,text,text,text,text,text,text,jsonb),api.record_match_event_v2(uuid,uuid,integer,text,text,uuid,uuid,jsonb),api.update_match_event_v2(uuid,uuid,integer,text,uuid,uuid,jsonb),api.void_match_event_v2(uuid,uuid),api.adjust_match_score_v2(uuid,uuid,text,integer,integer),api.adjust_match_kpi_v2(uuid,uuid,text,text,integer,integer),api.transition_match_clock_v2(uuid,uuid,text),api.complete_match_v2(uuid,uuid,integer),api.set_match_button_config_v2(uuid,uuid,bigint,jsonb,jsonb),api.reset_match_v2(uuid,uuid),api.unlock_match_v2(uuid,uuid,text) from public,anon;
grant execute on function api.save_match_plan_v2(uuid,uuid,bigint,text,jsonb,jsonb,text,text,text,text,text,text,jsonb),api.record_match_event_v2(uuid,uuid,integer,text,text,uuid,uuid,jsonb),api.update_match_event_v2(uuid,uuid,integer,text,uuid,uuid,jsonb),api.void_match_event_v2(uuid,uuid),api.adjust_match_score_v2(uuid,uuid,text,integer,integer),api.adjust_match_kpi_v2(uuid,uuid,text,text,integer,integer),api.transition_match_clock_v2(uuid,uuid,text),api.complete_match_v2(uuid,uuid,integer),api.set_match_button_config_v2(uuid,uuid,bigint,jsonb,jsonb),api.reset_match_v2(uuid,uuid),api.unlock_match_v2(uuid,uuid,text) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260815075650_s07_v2_mutation_contract','greenfield','frozen v2 RPC contract');
notify pgrst,'reload schema';
