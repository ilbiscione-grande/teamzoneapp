create or replace function api.get_match_v2_snapshot(p_event_id uuid)
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
  'cursor',coalesce((select command.created_at::text||'/'||command.command_id::text from audit.match_commands command where command.event_id=p_event_id order by command.created_at desc,command.command_id desc limit 1),'0')
 ) into value from core.match_workspaces workspace
 left join core.match_plans plan on plan.event_id=workspace.event_id
 left join core.match_projections projection on projection.event_id=workspace.event_id
 where workspace.event_id=p_event_id;
 return value;
end$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815075428_s07_fix_snapshot_cursor','greenfield','S07 deterministic cursor fix');
