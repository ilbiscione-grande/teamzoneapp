-- Derive the user-facing mandate state from the immutable mandate period.
-- No scheduled job is required and historical rows retain their recorded state.
create or replace function internal.get_board_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform internal.require_economy_actor(target_club_id,'board.read');
 return jsonb_build_object(
  'assignments',(select coalesce(jsonb_agg(jsonb_build_object(
    'id',assignment.id,'name',person.display_name,'role_package',assignment.role_package
   ) order by person.display_name),'[]'::jsonb)
   from core.assignments assignment join core.club_people person on person.id=assignment.club_person_id
   where assignment.club_id=target_club_id and assignment.state='active'
     and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now())),
  'mandates',(select coalesce(jsonb_agg(jsonb_build_object(
    'id',mandate.id,'assignment_id',mandate.assignment_id,'name',person.display_name,
    'office',mandate.office,'starts_at',mandate.starts_at,'ends_at',mandate.ends_at,
    'state',case
      when mandate.state<>'active' then mandate.state
      when mandate.starts_at>now() then 'scheduled'
      when mandate.ends_at<=now() then 'ended'
      else 'active'
    end,
    'revision',mandate.revision
   ) order by mandate.starts_at desc),'[]'::jsonb)
   from core.board_mandates mandate join core.assignments assignment on assignment.id=mandate.assignment_id
   join core.club_people person on person.id=assignment.club_person_id
   where mandate.club_id=target_club_id),
  'changes',(select coalesce(jsonb_agg(jsonb_build_object(
    'id',change_row.id,'assignment_id',change_row.target_assignment_id,
    'mandate_id',change_row.target_mandate_id,'name',person.display_name,
    'action',change_row.action,'office',change_row.office,'starts_at',change_row.starts_at,
    'ends_at',change_row.ends_at,'state',change_row.state,'created_by',change_row.created_by,
    'approval_count',(select count(*) from core.board_mandate_change_approvals approval where approval.change_id=change_row.id and approval.decision='approved'),
    'current_actor_approved',exists(select 1 from core.board_mandate_change_approvals approval where approval.change_id=change_row.id and approval.approver_profile_id=auth.uid()),
    'approvers',(select coalesce(jsonb_agg(jsonb_build_object('profile_id',approval.approver_profile_id,'display_name',profile.display_name,'decision',approval.decision) order by approval.decided_at),'[]'::jsonb)
      from core.board_mandate_change_approvals approval join core.profiles profile on profile.id=approval.approver_profile_id where approval.change_id=change_row.id)
   ) order by change_row.created_at desc),'[]'::jsonb)
   from core.board_mandate_changes change_row
   join core.assignments assignment on assignment.id=change_row.target_assignment_id
   join core.club_people person on person.id=assignment.club_person_id
   where change_row.club_id=target_club_id)
 );
end$$;

revoke all on function internal.get_board_for_actor(uuid) from public,anon,authenticated;

insert into internal.migration_provenance(migration_name,source_kind)
values('20260822090354_s10b_board_effective_period','greenfield');
