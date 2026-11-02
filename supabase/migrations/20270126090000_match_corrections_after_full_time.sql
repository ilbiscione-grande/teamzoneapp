-- Corrections after full time (2026-11-02).
--
-- Live in the Match module says events can be corrected after full time, but
-- update_event and void_event were refused once the match was completed, so
-- correcting a shot, a substitution or a card afterwards failed. They are now
-- allowed after full time as long as the result stands: an event that counts
-- in the score (a goal, or a penalty, shot, free kick or corner that was
-- scored) cannot be voided, stop or start counting, or change side. Goals
-- keep their own correction of minute, scorer and assist, and the result is
-- changed through the reasoned result correction as before.
--
-- The command function is the one from 20260815075650 with only that block
-- changed.

-- Whether a fact counts in the score, as internal.recompute_match_projection
-- counts it.
create or replace function internal.match_fact_scores(fact_type text, detail jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select fact_type = 'goal'
    or (fact_type in ('shot', 'penalty', 'free_kick', 'corner') and coalesce(detail, '{}')->>'result' = 'scored')
$$;

create or replace function internal.apply_match_command_v2(p_command_id uuid,p_event_id uuid,p_expected_revision bigint,p_command_type text,p_payload jsonb)
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
  if workspace.state not in('live','completed') then raise check_violation using message='match_not_live'; end if;
  select * into fact from core.match_facts where id=(p_payload->>'match_event_id')::uuid and event_id=p_event_id for update;
  if fact.id is null or fact.state<>'active' or fact.fact_type in('full_time','score_adjustment') then raise invalid_parameter_value using message='invalid_fact'; end if;
  -- After full time the result stands: an event that counts in the score
  -- keeps counting for the same side, and the result itself is changed
  -- through the reasoned result correction.
  if workspace.state='completed' and (
   (p_command_type='void_event' and internal.match_fact_scores(fact.fact_type,fact.detail))
   or (p_command_type='update_event' and (
    internal.match_fact_scores(fact.fact_type,fact.detail) is distinct from internal.match_fact_scores(fact.fact_type,coalesce(p_payload->'detail','{}'))
    or (internal.match_fact_scores(fact.fact_type,fact.detail) and nullif(p_payload->>'side','') is distinct from fact.side))))
  then raise check_violation using message='result_locked'; end if;
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

revoke all on function internal.match_fact_scores(text, jsonb) from public, anon, authenticated;

notify pgrst, 'reload schema';
