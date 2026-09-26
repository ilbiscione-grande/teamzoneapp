-- Register totals without requiring a live clock or a frozen roster.
-- Existing facts remain intact; audited deltas reconcile them with the totals.
create function internal.register_match_result_for_actor(
 p_command_id uuid,p_event_id uuid,p_expected_revision bigint,
 p_expected_event_revision bigint,p_score_us integer,p_score_opponent integer,
 p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 event_row core.events%rowtype; workspace core.match_workspaces%rowtype;
 payload_value jsonb; receipt jsonb; side_value text; delta_value integer;
 child_id uuid; fact_id uuid; minute_value integer; event_revision bigint;
 reason_value text:=nullif(btrim(p_reason),'');
begin
 perform internal.assert_match_manager(p_event_id);
 -- Match writers use this lock; event transitions also lock the event row.
 perform pg_advisory_xact_lock(hashtextextended(p_event_id::text,0));
 select * into event_row from core.events where id=p_event_id for update;
 perform internal.assert_match_manager(p_event_id);
 if event_row.archived_at is not null then
  raise insufficient_privilege using message='not_found'; end if;
 if p_score_us is null or p_score_opponent is null
  or p_score_us not between 0 and 999 or p_score_opponent not between 0 and 999
  or p_expected_revision is null or p_expected_event_revision is null
  or length(coalesce(reason_value,''))>500 then
  raise invalid_parameter_value using message='invalid_result'; end if;
 payload_value:=jsonb_build_object('score_us',p_score_us,'score_opponent',p_score_opponent,
  'event_revision',p_expected_event_revision,'reason',reason_value);
 workspace:=internal.ensure_match_workspace(p_event_id);
 if not internal.register_match_command(p_command_id,p_event_id,p_expected_revision,
  'register_result',payload_value) then
  select command.result into receipt from audit.match_commands command where command_id=p_command_id;
  return receipt;
 end if;
 if workspace.revision<>p_expected_revision or event_row.revision<>p_expected_event_revision then
  raise serialization_failure using message='stale_revision'; end if;
 if event_row.state not in('scheduled','completed') or event_row.starts_at>now() then
  raise check_violation using message='match_not_started'; end if;
 if (workspace.state='completed' or event_row.state='completed')
  and length(coalesce(reason_value,''))<3 then
  raise invalid_parameter_value using message='correction_reason_required'; end if;
 select greatest(coalesce((select sum(value) from unnest(workspace.period_minutes) value),90),
  coalesce(max(minute),0)) into minute_value from core.match_facts where event_id=p_event_id;
 foreach side_value in array array['us','opponent'] loop
  -- Use the raw sum: the projection clamps negative totals to zero.
  select (case when side_value='us' then p_score_us else p_score_opponent end)-coalesce(sum(
   case when fact_type='score_adjustment' then coalesce((detail->>'delta')::integer,0)
   when fact_type='goal' or (fact_type in('shot','penalty','free_kick','corner')
    and detail->>'result'='scored') then 1 else 0 end),0)
   into delta_value from core.match_facts where event_id=p_event_id and state='active' and side=side_value;
  if delta_value<>0 then
   child_id:=gen_random_uuid(); fact_id:=gen_random_uuid();
   insert into audit.match_commands(command_id,event_id,expected_revision,command_type,payload,result,actor_profile_id)
   values(child_id,p_event_id,p_expected_revision,'register_result_adjustment',
    jsonb_build_object('parent_command_id',p_command_id,'side',side_value,'delta',delta_value,'reason',reason_value),
    jsonb_build_object('match_event_id',fact_id),auth.uid());
   insert into core.match_facts(id,event_id,minute,fact_type,side,club_id,detail,source_command_id,created_by,updated_by)
   values(fact_id,p_event_id,minute_value,'score_adjustment',side_value,workspace.club_id,
    jsonb_build_object('delta',delta_value,'reason',reason_value,'source','registered_result'),child_id,auth.uid(),auth.uid());
   insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id,reason)
   select fact_id,p_event_id,1,to_jsonb(f),'created',auth.uid(),reason_value from core.match_facts f where f.id=fact_id;
  end if;
 end loop;
 if workspace.state<>'completed' then
  fact_id:=gen_random_uuid();
  insert into core.match_facts(id,event_id,minute,fact_type,club_id,detail,source_command_id,created_by,updated_by)
  values(fact_id,p_event_id,minute_value,'full_time',workspace.club_id,
   jsonb_build_object('source','registered_result'),p_command_id,auth.uid(),auth.uid());
  insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id,reason)
  select fact_id,p_event_id,1,to_jsonb(f),'created',auth.uid(),reason_value from core.match_facts f where f.id=fact_id;
 end if;
 update core.match_workspaces set state='completed',completed_at=coalesce(completed_at,now()),
  revision=revision+1,updated_at=now(),updated_by=auth.uid() where event_id=p_event_id;
 perform internal.recompute_match_projection(p_event_id);
 event_revision:=event_row.revision;
 if event_row.state='scheduled' then
  event_revision:=internal.transition_event_for_actor(p_event_id,'completed',event_row.revision,
   coalesce(reason_value,'Slutresultat registrerat'),gen_random_uuid());
 end if;
 receipt:=jsonb_build_object('revision',workspace.revision+1,'event_revision',event_revision,
  'score_us',p_score_us,'score_opponent',p_score_opponent,'state','completed');
 update audit.match_commands set result=receipt where command_id=p_command_id;
 return receipt;
end$$;

create function api.register_match_result(p_command_id uuid,p_event_id uuid,p_expected_revision bigint,
 p_expected_event_revision bigint,p_score_us integer,p_score_opponent integer,p_reason text default null)
returns jsonb language sql security invoker set search_path='' as $$
 select internal.register_match_result_for_actor(p_command_id,p_event_id,p_expected_revision,
  p_expected_event_revision,p_score_us,p_score_opponent,p_reason)
$$;
revoke all on function internal.register_match_result_for_actor(uuid,uuid,bigint,bigint,integer,integer,text),
 api.register_match_result(uuid,uuid,bigint,bigint,integer,integer,text) from public,anon;
grant execute on function internal.register_match_result_for_actor(uuid,uuid,bigint,bigint,integer,integer,text),
 api.register_match_result(uuid,uuid,bigint,bigint,integer,integer,text) to authenticated;
notify pgrst,'reload schema';
