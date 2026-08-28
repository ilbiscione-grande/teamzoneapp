-- Expose child reversal state so a client never offers a duplicate reversal.

create or replace function internal.get_economy_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform internal.require_economy_actor(target_club_id,'economy.read');
 return jsonb_build_object(
  'accounts',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'team_id',a.team_id,'name',a.name,'currency',a.currency,'state',a.state) order by a.name),'[]'::jsonb) from core.economy_accounts a where a.club_id=target_club_id),
  'entries',(select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'account_id',e.account_id,'amount_minor',e.amount_minor,'currency',e.currency,
    'direction',e.direction,'category',e.category,'state',e.state,'risk_level',e.risk_level,
    'reversal_of',e.reversal_of,
    'reversal_state',(select child.state from core.economy_ledger_entries child where child.reversal_of=e.id),
    'created_at',e.created_at,'posted_at',e.posted_at,
    'required_approvals',case when e.risk_level='high' then 2 else 0 end,
    'approval_count',(select count(*) from core.economy_entry_approvals ea where ea.entry_id=e.id and ea.decision='approved'),
    'current_actor_approved',exists(select 1 from core.economy_entry_approvals ea where ea.entry_id=e.id and ea.approver_profile_id=auth.uid()),
    'approvers',(select coalesce(jsonb_agg(jsonb_build_object('profile_id',ea.approver_profile_id,'display_name',p.display_name,'decision',ea.decision) order by ea.decided_at),'[]'::jsonb) from core.economy_entry_approvals ea join core.profiles p on p.id=ea.approver_profile_id where ea.entry_id=e.id)
  ) order by e.created_at desc),'[]'::jsonb) from core.economy_ledger_entries e where e.club_id=target_club_id)
 );
end$$;

revoke all on function internal.get_economy_for_actor(uuid)
from public,anon,authenticated;

insert into internal.migration_provenance(migration_name,source_kind)
values('20260822075945_s10b_hide_completed_reversal_action','greenfield');
