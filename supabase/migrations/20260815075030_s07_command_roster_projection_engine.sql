-- Permit the single result finalization used by the frozen v2 retry contract,
-- while keeping command identity, payload, actor and history immutable.
create or replace function internal.reject_match_command_mutation()
returns trigger language plpgsql set search_path='' as $$
begin
 if old.command_id=new.command_id and old.event_id=new.event_id
 and old.expected_revision is not distinct from new.expected_revision
 and old.command_type=new.command_type and old.payload=new.payload
 and old.actor_profile_id=new.actor_profile_id and old.created_at=new.created_at
 and old.result='{}'::jsonb and new.result<>'{}'::jsonb then return new; end if;
 raise check_violation using message='match_commands_append_only';
end$$;

create function internal.assert_match_manager(target_event_id uuid)
returns core.events language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or event_row.event_type<>'match' or event_row.state='cancelled'
 or not internal.actor_can_manage_event(target_event_id) then
   raise insufficient_privilege using message='not_found';
 end if;
 return event_row;
end$$;

create function internal.ensure_match_workspace(target_event_id uuid)
returns core.match_workspaces language plpgsql security definer set search_path='' as $$
declare event_row core.events%rowtype; workspace core.match_workspaces%rowtype;
begin
 event_row:=internal.assert_match_manager(target_event_id);
 insert into core.match_workspaces(event_id,club_id,team_id,updated_by)
 values(event_row.id,event_row.club_id,event_row.owning_team_id,auth.uid()) on conflict(event_id) do nothing;
 insert into core.match_projections(event_id) values(event_row.id) on conflict(event_id) do nothing;
 select * into workspace from core.match_workspaces where event_id=target_event_id;
 return workspace;
end$$;

create function internal.register_match_command(
 p_command_id uuid,p_event_id uuid,p_expected_revision bigint,p_command_type text,p_payload jsonb)
returns boolean language plpgsql security definer set search_path='' as $$
declare inserted integer; existing audit.match_commands%rowtype;
begin
 if p_command_id is null or nullif(btrim(p_command_type),'') is null then
   raise invalid_parameter_value using message='invalid_command'; end if;
 perform internal.ensure_match_workspace(p_event_id);
 insert into audit.match_commands(command_id,event_id,expected_revision,command_type,payload,actor_profile_id)
 values(p_command_id,p_event_id,p_expected_revision,p_command_type,coalesce(p_payload,'{}'::jsonb),auth.uid())
 on conflict(command_id) do nothing;
 get diagnostics inserted=row_count;
 if inserted=1 then return true; end if;
 select * into existing from audit.match_commands where command_id=p_command_id;
 if existing.event_id<>p_event_id or existing.expected_revision is distinct from p_expected_revision
 or existing.command_type<>p_command_type or existing.actor_profile_id<>auth.uid()
 or existing.payload is distinct from coalesce(p_payload,'{}'::jsonb) then
   raise unique_violation using message='command_id_reused';
 end if;
 return false;
end$$;

create function internal.assert_frozen_match_member(target_event_id uuid,target_person_id uuid)
returns void language plpgsql stable security definer set search_path='' as $$
begin
 if target_person_id is null then return; end if;
 if not exists(
   select 1 from core.match_roster_revisions roster
   join core.match_roster_members member on member.roster_revision_id=roster.id
   where roster.event_id=target_event_id and roster.state='frozen'
     and member.club_person_id=target_person_id
 ) then raise invalid_parameter_value using message='person_not_in_frozen_roster'; end if;
end$$;

create function internal.recompute_match_projection(target_event_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare us_score integer; opponent_score integer; workspace_revision bigint; stats_value jsonb;
begin
 select revision into workspace_revision from core.match_workspaces where event_id=target_event_id for update;
 select
  greatest(0,coalesce(sum(case when side='us' then case
    when fact_type='score_adjustment' then coalesce((detail->>'delta')::integer,0)
    when fact_type='goal' or (fact_type in('shot','penalty','free_kick','corner') and detail->>'result'='scored') then 1 else 0 end else 0 end),0)),
  greatest(0,coalesce(sum(case when side='opponent' then case
    when fact_type='score_adjustment' then coalesce((detail->>'delta')::integer,0)
    when fact_type='goal' or (fact_type in('shot','penalty','free_kick','corner') and detail->>'result'='scored') then 1 else 0 end else 0 end),0))
 into us_score,opponent_score from core.match_facts where event_id=target_event_id and state='active';
 select coalesce(jsonb_object_agg(person_id,summary),'{}'::jsonb) into stats_value from(
  select person_id::text person_id,jsonb_build_object(
    'goals',count(*) filter(where scoring),'assists',count(*) filter(where assisting),
    'yellow_cards',count(*) filter(where card='yellow'),'red_cards',count(*) filter(where card='red')) summary
  from(
   select club_person_id person_id,
    side='us' and (fact_type='goal' or (fact_type in('shot','penalty','free_kick','corner') and detail->>'result'='scored')) scoring,
    false assisting,case when fact_type='card' then detail->>'color' end card
   from core.match_facts where event_id=target_event_id and state='active' and club_person_id is not null
   union all
   select secondary_club_person_id,false,
    side='us' and (fact_type='goal' or (fact_type in('shot','penalty','free_kick','corner') and detail->>'result'='scored')),
    null from core.match_facts where event_id=target_event_id and state='active' and secondary_club_person_id is not null
  ) facts group by person_id
 ) summaries;
 insert into core.match_projections(event_id,revision,score_us,score_opponent,stats,updated_at)
 values(target_event_id,workspace_revision,us_score,opponent_score,stats_value,now())
 on conflict(event_id) do update set revision=excluded.revision,score_us=excluded.score_us,
 score_opponent=excluded.score_opponent,stats=excluded.stats,updated_at=excluded.updated_at;
end$$;

create function internal.freeze_match_roster_for_actor(
 p_command_id uuid,p_event_id uuid,p_reason_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare is_new boolean; next_revision bigint; new_roster uuid:=gen_random_uuid(); member_count integer; result jsonb; source_squad uuid;
begin
 if p_reason_code not in('initial','late_callup','manual_correction') then raise invalid_parameter_value using message='invalid_reason'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_event_id::text,0));
 is_new:=internal.register_match_command(p_command_id,p_event_id,null,'freeze_roster',jsonb_build_object('reason_code',p_reason_code));
 if not is_new then select command.result into result from audit.match_commands command where command_id=p_command_id; return result; end if;
 select coalesce(max(revision),0)+1 into next_revision from core.match_roster_revisions where event_id=p_event_id;
 select squad_revision_id into source_squad from core.callups where event_id=p_event_id and state='accepted' order by sent_at desc limit 1;
 if source_squad is null then raise check_violation using message='accepted_callups_required'; end if;
 update core.match_roster_revisions set state='superseded' where event_id=p_event_id and state='frozen';
 insert into core.match_roster_revisions(id,event_id,revision,reason_code,source_squad_revision_id,created_by)
 values(new_roster,p_event_id,next_revision,p_reason_code,source_squad,auth.uid());
 insert into core.match_roster_members(roster_revision_id,club_person_id,club_id,source_callup_id,source_state)
 select new_roster,callup.club_person_id,callup.club_id,callup.id,'accepted'
 from core.callups callup where callup.event_id=p_event_id and callup.state='accepted';
 get diagnostics member_count=row_count;
 update core.match_workspaces set roster_revision=next_revision,revision=revision+1,updated_at=now(),updated_by=auth.uid() where event_id=p_event_id;
 perform internal.recompute_match_projection(p_event_id);
 result:=jsonb_build_object('roster_revision_id',new_roster,'revision',next_revision,'member_count',member_count);
 update audit.match_commands set result=freeze_match_roster_for_actor.result where command_id=p_command_id;
 return result;
end$$;

create function api.freeze_match_roster(p_command_id uuid,p_event_id uuid,p_reason_code text)
returns jsonb language sql security invoker set search_path='' as $$
 select internal.freeze_match_roster_for_actor(p_command_id,p_event_id,p_reason_code)
$$;

create function api.get_match_v2_snapshot(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare value jsonb;
begin
 if auth.uid() is null or not internal.actor_can_read_event(p_event_id) then raise insufficient_privilege using message='not_found'; end if;
 select jsonb_build_object(
  'schema_version',2,'server_now',now(),'event_id',workspace.event_id,'state',workspace.state,
  'revision',workspace.revision,'roster_revision',workspace.roster_revision,
  'clock',jsonb_build_object('started_at',workspace.match_started_at,'paused_at',workspace.match_paused_at,'paused_seconds',workspace.paused_seconds,'completed_at',workspace.completed_at),
  'plan',to_jsonb(plan),'projection',to_jsonb(projection),
  'facts',coalesce((select jsonb_agg(to_jsonb(fact) order by fact.minute,fact.created_at,fact.id) from core.match_facts fact where fact.event_id=p_event_id),'[]'::jsonb),
  'cursor',coalesce((select max(command.created_at)::text||'/'||max(command.command_id)::text from audit.match_commands command where command.event_id=p_event_id),'0')
 ) into value from core.match_workspaces workspace
 left join core.match_plans plan on plan.event_id=workspace.event_id
 left join core.match_projections projection on projection.event_id=workspace.event_id
 where workspace.event_id=p_event_id;
 return value;
end$$;

revoke all on function internal.assert_match_manager(uuid),internal.ensure_match_workspace(uuid),
 internal.register_match_command(uuid,uuid,bigint,text,jsonb),internal.assert_frozen_match_member(uuid,uuid),
 internal.recompute_match_projection(uuid),internal.freeze_match_roster_for_actor(uuid,uuid,text) from public,anon,authenticated;
grant execute on function internal.freeze_match_roster_for_actor(uuid,uuid,text) to authenticated;
revoke all on function api.freeze_match_roster(uuid,uuid,text),api.get_match_v2_snapshot(uuid) from public,anon;
grant execute on function api.freeze_match_roster(uuid,uuid,text),api.get_match_v2_snapshot(uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815075030_s07_command_roster_projection_engine','greenfield','frozen v2 adapter baseline');
notify pgrst,'reload schema';
