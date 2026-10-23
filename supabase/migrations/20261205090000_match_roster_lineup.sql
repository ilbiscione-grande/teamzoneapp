-- The match squad (Match Space v2's frozen roster) also takes the event's
-- line-up: teams that pick the line-up without callups or registered
-- attendance froze an empty squad, so no player could be chosen for a
-- substitution, a shot or a goal. The line-up's starters and substitutes
-- join as 'lineup'; otherwise as in 20260928150100. A started match picks
-- them up when its squad is updated (reason manual_correction).

alter table core.match_roster_members drop constraint match_roster_members_source_state_check;
alter table core.match_roster_members add constraint match_roster_members_source_state_check
 check(source_state in ('accepted','leader_added','lineup'));

create or replace function internal.freeze_match_roster_for_actor(
 p_command_id uuid,p_event_id uuid,p_reason_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare is_new boolean; next_revision bigint; new_roster uuid:=gen_random_uuid(); member_count integer; result_value jsonb; source_squad uuid; walk_ins integer; from_lineup integer;
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
 insert into core.match_roster_members(roster_revision_id,club_person_id,club_id,source_callup_id,source_state)
 select distinct on (person.id) new_roster,person.id,person.club_id,null,'lineup'
 from core.event_lineups lineup
 cross join lateral (select value->>'person_id' chosen_id from jsonb_array_elements(lineup.starters)
   union all select value->>'person_id' from jsonb_array_elements(lineup.substitutes)) chosen
 join core.events event_row on event_row.id=lineup.event_id
 join core.club_people person on person.id::text=chosen.chosen_id and person.club_id=event_row.club_id
 where lineup.event_id=p_event_id
  and not exists(select 1 from core.match_roster_members member where member.roster_revision_id=new_roster and member.club_person_id=person.id);
 get diagnostics from_lineup=row_count;
 update core.match_workspaces set roster_revision=next_revision,revision=revision+1,updated_at=now(),updated_by=auth.uid() where event_id=p_event_id;
 perform internal.recompute_match_projection(p_event_id);
 result_value:=jsonb_build_object('roster_revision_id',new_roster,'revision',next_revision,'member_count',member_count+walk_ins+from_lineup);
 update audit.match_commands command set result=result_value where command.command_id=p_command_id;
 return result_value;
end$$;
