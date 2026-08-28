create or replace function internal.freeze_match_roster_for_actor(
 p_command_id uuid,p_event_id uuid,p_reason_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare is_new boolean; next_revision bigint; new_roster uuid:=gen_random_uuid(); member_count integer; result_value jsonb; source_squad uuid;
begin
 if p_reason_code not in('initial','late_callup','manual_correction') then raise invalid_parameter_value using message='invalid_reason'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_event_id::text,0));
 is_new:=internal.register_match_command(p_command_id,p_event_id,null,'freeze_roster',jsonb_build_object('reason_code',p_reason_code));
 if not is_new then select command.result into result_value from audit.match_commands command where command_id=p_command_id; return result_value; end if;
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
 result_value:=jsonb_build_object('roster_revision_id',new_roster,'revision',next_revision,'member_count',member_count);
 update audit.match_commands command set result=result_value where command.command_id=p_command_id;
 return result_value;
end$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815075322_s07_fix_roster_result_binding','greenfield','S07 verification fix');
