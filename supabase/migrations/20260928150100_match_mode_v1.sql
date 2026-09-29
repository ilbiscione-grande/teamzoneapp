-- Enkelt Matchläge on the existing Match Space v2 contract. No parallel
-- "simple match" model: the same workspace, frozen roster, facts, audit
-- versions and derived projection are extended with the few commands the
-- match-day view needs. Every new command is registered in
-- audit.match_commands, so a retried command id returns the stored receipt
-- instead of creating a duplicate goal.

-- Formats with a single period (e.g. 1×25 small-sided games) are valid too.
alter table core.match_workspaces drop constraint match_workspaces_period_minutes_valid;
alter table core.match_workspaces add constraint match_workspaces_period_minutes_valid
 check(cardinality(period_minutes) between 1 and 8 and 0 < all(period_minutes) and 120 >= all(period_minutes));

-- Free-text match notes ("Anteckning") are structured facts, not score events.
alter table core.match_facts drop constraint match_facts_fact_type_check;
alter table core.match_facts add constraint match_facts_fact_type_check check(fact_type in
 ('substitution','goal','card','injury','corner','free_kick','penalty','save','half_time','period_end','full_time','kpi','shot','score_adjustment','note'));

create function internal.finish_match_command(p_command_id uuid,p_event_id uuid,p_result jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare new_revision bigint; result_value jsonb;
begin
 update core.match_workspaces set revision=revision+1,updated_at=now(),updated_by=auth.uid()
 where event_id=p_event_id returning revision into new_revision;
 perform internal.recompute_match_projection(p_event_id);
 result_value:=p_result||jsonb_build_object('workspace_revision',new_revision);
 update audit.match_commands command set result=result_value where command.command_id=p_command_id;
 return result_value;
end$$;

-- The match squad is what Deltagare shows as coming: accepted callups plus
-- people whose attendance was registered without a callup. Teams that do not
-- use callups can still run the match (an empty roster only allows goals by
-- an unknown scorer).
create or replace function internal.freeze_match_roster_for_actor(
 p_command_id uuid,p_event_id uuid,p_reason_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare is_new boolean; next_revision bigint; new_roster uuid:=gen_random_uuid(); member_count integer; result_value jsonb; source_squad uuid; walk_ins integer;
begin
 if p_reason_code not in('initial','late_callup','manual_correction') then raise invalid_parameter_value using message='invalid_reason'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_event_id::text,0));
 is_new:=internal.register_match_command(p_command_id,p_event_id,null,'freeze_roster',jsonb_build_object('reason_code',p_reason_code));
 if not is_new then select command.result into result_value from audit.match_commands command where command_id=p_command_id; return result_value; end if;
 select coalesce(max(revision),0)+1 into next_revision from core.match_roster_revisions where event_id=p_event_id;
 select squad_revision_id into source_squad from core.callups where event_id=p_event_id and state='accepted' order by sent_at desc limit 1;
 update core.match_roster_revisions set state='superseded' where event_id=p_event_id and state='frozen';
 insert into core.match_roster_revisions(id,event_id,revision,reason_code,source_squad_revision_id,created_by)
 values(new_roster,p_event_id,next_revision,p_reason_code,source_squad,auth.uid());
 insert into core.match_roster_members(roster_revision_id,club_person_id,club_id,source_callup_id,source_state)
 select new_roster,callup.club_person_id,callup.club_id,callup.id,'accepted'
 from core.callups callup where callup.event_id=p_event_id and callup.state='accepted';
 get diagnostics member_count=row_count;
 insert into core.match_roster_members(roster_revision_id,club_person_id,club_id,source_callup_id,source_state)
 select new_roster,fact.club_person_id,fact.club_id,null,'leader_added'
 from core.attendance_facts fact where fact.event_id=p_event_id and fact.status in('present','late','partial')
  and not exists(select 1 from core.match_roster_members member where member.roster_revision_id=new_roster and member.club_person_id=fact.club_person_id);
 get diagnostics walk_ins=row_count;
 update core.match_workspaces set roster_revision=next_revision,revision=revision+1,updated_at=now(),updated_by=auth.uid() where event_id=p_event_id;
 perform internal.recompute_match_projection(p_event_id);
 result_value:=jsonb_build_object('roster_revision_id',new_roster,'revision',next_revision,'member_count',member_count+walk_ins);
 update audit.match_commands command set result=result_value where command.command_id=p_command_id;
 return result_value;
end$$;

create function internal.configure_match_periods_for_actor(p_command_id uuid,p_event_id uuid,p_period_minutes integer[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare workspace core.match_workspaces%rowtype; result_value jsonb;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_event_id::text,0));
 perform internal.ensure_match_workspace(p_event_id);
 if not internal.register_match_command(p_command_id,p_event_id,null,'configure_periods',
  jsonb_build_object('period_minutes',to_jsonb(p_period_minutes))) then
  select command.result into result_value from audit.match_commands command where command.command_id=p_command_id; return result_value; end if;
 select * into workspace from core.match_workspaces where event_id=p_event_id for update;
 if p_period_minutes is null or cardinality(p_period_minutes) not between 1 and 8 or array_position(p_period_minutes,null) is not null
  or exists(select 1 from unnest(p_period_minutes) value where value not between 1 and 120) then
  raise invalid_parameter_value using message='invalid_periods'; end if;
 if workspace.state='completed' or cardinality(p_period_minutes)<workspace.current_period then
  raise check_violation using message='invalid_transition'; end if;
 update core.match_workspaces set period_minutes=p_period_minutes where event_id=p_event_id;
 return internal.finish_match_command(p_command_id,p_event_id,jsonb_build_object('ok',true));
end$$;

-- The clock is a projection of started_at/paused_seconds, never a device
-- timer. A correction moves the start anchor so the displayed time equals
-- the requested value, using the same period anchor offset as the client.
create function internal.adjust_match_clock_for_actor(p_command_id uuid,p_event_id uuid,p_elapsed_seconds integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare workspace core.match_workspaces%rowtype; result_value jsonb; anchor jsonb; anchor_offset integer:=0; raw_seconds integer;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_event_id::text,0));
 perform internal.ensure_match_workspace(p_event_id);
 if not internal.register_match_command(p_command_id,p_event_id,null,'clock_adjust',
  jsonb_build_object('elapsed_seconds',p_elapsed_seconds)) then
  select command.result into result_value from audit.match_commands command where command.command_id=p_command_id; return result_value; end if;
 select * into workspace from core.match_workspaces where event_id=p_event_id for update;
 if p_elapsed_seconds is null or p_elapsed_seconds not between 0 and 43200 then raise invalid_parameter_value using message='invalid_clock'; end if;
 if workspace.state<>'live' or workspace.match_started_at is null then raise check_violation using message='invalid_transition'; end if;
 select fact.detail into anchor from core.match_facts fact where fact.event_id=p_event_id and fact.state='active'
  and fact.fact_type='period_end' order by fact.minute desc,fact.created_at desc,fact.id desc limit 1;
 if anchor is not null then
  anchor_offset:=greatest(0,coalesce((anchor->>'scheduled_minute')::integer,0)*60-coalesce((anchor->>'elapsed_seconds')::integer,0));
 end if;
 raw_seconds:=greatest(0,p_elapsed_seconds-anchor_offset);
 update core.match_workspaces set match_started_at=coalesce(match_paused_at,now())-make_interval(secs=>raw_seconds+paused_seconds)
 where event_id=p_event_id;
 return internal.finish_match_command(p_command_id,p_event_id,jsonb_build_object('ok',true));
end$$;

create function internal.record_match_note_for_actor(p_command_id uuid,p_event_id uuid,p_minute integer,p_text text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare workspace core.match_workspaces%rowtype; result_value jsonb; new_fact_id uuid:=gen_random_uuid(); clean text:=btrim(coalesce(p_text,''));
begin
 perform pg_advisory_xact_lock(hashtextextended(p_event_id::text,0));
 perform internal.ensure_match_workspace(p_event_id);
 if not internal.register_match_command(p_command_id,p_event_id,null,'record_note',
  jsonb_build_object('minute',p_minute,'text',clean)) then
  select command.result into result_value from audit.match_commands command where command.command_id=p_command_id; return result_value; end if;
 select * into workspace from core.match_workspaces where event_id=p_event_id for update;
 if workspace.state<>'live' then raise check_violation using message='match_not_live'; end if;
 if p_minute is null or p_minute not between 0 and 300 or length(clean) not between 1 and 500 then
  raise invalid_parameter_value using message='invalid_fact'; end if;
 insert into core.match_facts(id,event_id,minute,fact_type,club_id,detail,source_command_id,created_by,updated_by)
 values(new_fact_id,p_event_id,p_minute,'note',workspace.club_id,jsonb_build_object('text',clean),p_command_id,auth.uid(),auth.uid());
 insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id)
 values(new_fact_id,p_event_id,1,(select to_jsonb(f) from core.match_facts f where f.id=new_fact_id),'created',auth.uid());
 return internal.finish_match_command(p_command_id,p_event_id,jsonb_build_object('match_event_id',new_fact_id));
end$$;

-- Corrects minute/scorer/assist (or note text) of an active goal or note.
-- Side and type never change, so the derived score stays consistent; this
-- is also allowed after full time, when voiding (which would change the
-- confirmed result) still goes through the reasoned result correction.
create function internal.correct_match_event_for_actor(p_command_id uuid,p_match_event_id uuid,p_minute integer,
 p_player_id uuid,p_secondary_player_id uuid,p_text text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare target_event uuid; workspace core.match_workspaces%rowtype; fact core.match_facts%rowtype; result_value jsonb; clean text:=btrim(coalesce(p_text,''));
begin
 select event_id into target_event from core.match_facts where id=p_match_event_id;
 if target_event is null then raise insufficient_privilege using message='not_found'; end if;
 perform pg_advisory_xact_lock(hashtextextended(target_event::text,0));
 perform internal.ensure_match_workspace(target_event);
 if not internal.register_match_command(p_command_id,target_event,null,'correct_event',jsonb_build_object(
  'match_event_id',p_match_event_id,'minute',p_minute,'player_id',p_player_id,'secondary_player_id',p_secondary_player_id,'text',clean)) then
  select command.result into result_value from audit.match_commands command where command.command_id=p_command_id; return result_value; end if;
 select * into workspace from core.match_workspaces where event_id=target_event for update;
 select * into fact from core.match_facts where id=p_match_event_id for update;
 if workspace.state not in('live','completed') then raise check_violation using message='match_not_live'; end if;
 if fact.state<>'active' or fact.fact_type not in('goal','note') or p_minute is null or p_minute not between 0 and 300
  or (p_player_id is not null and p_player_id=p_secondary_player_id)
  or ((fact.side is distinct from 'us' or fact.fact_type='note') and (p_player_id is not null or p_secondary_player_id is not null))
  or (fact.fact_type='note' and length(clean) not between 1 and 500) then
  raise invalid_parameter_value using message='invalid_fact'; end if;
 if p_player_id is distinct from fact.club_person_id then perform internal.assert_frozen_match_member(target_event,p_player_id); end if;
 if p_secondary_player_id is distinct from fact.secondary_club_person_id then
  perform internal.assert_frozen_match_member(target_event,p_secondary_player_id); end if;
 update core.match_facts set minute=p_minute,club_person_id=p_player_id,secondary_club_person_id=p_secondary_player_id,
  detail=case when fact_type='note' then detail||jsonb_build_object('text',clean) else detail end,
  fact_revision=fact_revision+1,updated_at=now(),updated_by=auth.uid()
 where id=fact.id returning * into fact;
 insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id)
 values(fact.id,target_event,fact.fact_revision,to_jsonb(fact),'edited',auth.uid());
 return internal.finish_match_command(p_command_id,target_event,jsonb_build_object('ok',true));
end$$;

-- The snapshot now also carries the frozen squad and the names of people in
-- facts, so the match-day view never needs its own copy of the squad.
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
  'roster',coalesce((select jsonb_agg(jsonb_build_object('person_id',member.club_person_id,'name',person.display_name,'source_state',member.source_state) order by person.display_name,member.club_person_id)
   from core.match_roster_revisions roster join core.match_roster_members member on member.roster_revision_id=roster.id
   join core.club_people person on person.id=member.club_person_id
   where roster.event_id=p_event_id and roster.state='frozen'),'[]'::jsonb),
  'people',coalesce((select jsonb_object_agg(person.id,person.display_name) from core.club_people person
   where person.id in(select fact.club_person_id from core.match_facts fact where fact.event_id=p_event_id
    union select fact.secondary_club_person_id from core.match_facts fact where fact.event_id=p_event_id)),'{}'::jsonb),
  'can_manage',internal.actor_can_manage_event(p_event_id),
  'cursor',coalesce((select command.created_at::text||'/'||command.command_id::text from audit.match_commands command where command.event_id=p_event_id order by command.created_at desc,command.command_id desc limit 1),'0')) into value
 from core.match_workspaces workspace left join core.match_plans plan on plan.event_id=workspace.event_id left join core.match_projections projection on projection.event_id=workspace.event_id where workspace.event_id=p_event_id;
 return value;
end$$;

create function api.configure_match_periods_v2(p_command_id uuid,p_event_id uuid,p_period_minutes integer[])
returns jsonb language sql security invoker set search_path='' as $$select internal.configure_match_periods_for_actor(p_command_id,p_event_id,p_period_minutes)$$;
create function api.adjust_match_clock_v2(p_command_id uuid,p_event_id uuid,p_elapsed_seconds integer)
returns jsonb language sql security invoker set search_path='' as $$select internal.adjust_match_clock_for_actor(p_command_id,p_event_id,p_elapsed_seconds)$$;
create function api.record_match_note_v2(p_command_id uuid,p_event_id uuid,p_minute integer,p_text text)
returns jsonb language sql security invoker set search_path='' as $$select internal.record_match_note_for_actor(p_command_id,p_event_id,p_minute,p_text)$$;
create function api.correct_match_event_v2(p_command_id uuid,p_match_event_id uuid,p_minute integer,p_player_id uuid,p_secondary_player_id uuid,p_text text)
returns jsonb language sql security invoker set search_path='' as $$select internal.correct_match_event_for_actor(p_command_id,p_match_event_id,p_minute,p_player_id,p_secondary_player_id,p_text)$$;

-- Several leaders on the sideline see each other's goals and clock changes.
create trigger match_workspaces_live after insert or update on core.match_workspaces
for each row execute function internal.broadcast_event_live_invalidation();
create trigger match_facts_live after insert or update on core.match_facts
for each row execute function internal.broadcast_event_live_invalidation();

revoke all on function internal.finish_match_command(uuid,uuid,jsonb),internal.configure_match_periods_for_actor(uuid,uuid,integer[]),
 internal.adjust_match_clock_for_actor(uuid,uuid,integer),internal.record_match_note_for_actor(uuid,uuid,integer,text),
 internal.correct_match_event_for_actor(uuid,uuid,integer,uuid,uuid,text) from public,anon,authenticated;
grant execute on function internal.configure_match_periods_for_actor(uuid,uuid,integer[]),
 internal.adjust_match_clock_for_actor(uuid,uuid,integer),internal.record_match_note_for_actor(uuid,uuid,integer,text),
 internal.correct_match_event_for_actor(uuid,uuid,integer,uuid,uuid,text) to authenticated;
revoke all on function api.configure_match_periods_v2(uuid,uuid,integer[]),api.adjust_match_clock_v2(uuid,uuid,integer),
 api.record_match_note_v2(uuid,uuid,integer,text),api.correct_match_event_v2(uuid,uuid,integer,uuid,uuid,text) from public,anon;
grant execute on function api.configure_match_periods_v2(uuid,uuid,integer[]),api.adjust_match_clock_v2(uuid,uuid,integer),
 api.record_match_note_v2(uuid,uuid,integer,text),api.correct_match_event_v2(uuid,uuid,integer,uuid,uuid,text) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260928150100_match_mode_v1','greenfield','Enkelt Matchläge on Match Space v2: format, clock correction, notes, corrections, squad snapshot');
notify pgrst,'reload schema';
