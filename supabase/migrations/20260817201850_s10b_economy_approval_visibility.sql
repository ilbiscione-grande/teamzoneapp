-- Make high-risk approval progress observable and turn duplicate approvals into
-- a stable domain error. The API remains the only client-readable surface.

create or replace function internal.approve_economy_entry_for_actor(
 target_entry_id uuid,new_decision text,new_reason text,idempotency_key uuid
) returns void language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); entry core.economy_ledger_entries%rowtype;
begin
 select * into entry from core.economy_ledger_entries where id=target_entry_id;
 if entry.id is null then raise insufficient_privilege using message='not_found'; end if;
 actor_id:=internal.require_economy_actor(entry.club_id,'economy.approve');
 if exists(select 1 from internal.command_deduplication where actor_profile_id=actor_id and internal.command_deduplication.idempotency_key=approve_economy_entry_for_actor.idempotency_key and command_type='economy.entry.approve.v1') then return; end if;
 if entry.state<>'pending' or entry.risk_level<>'high' or entry.created_by=actor_id or new_decision not in ('approved','rejected') then
  raise insufficient_privilege using message='approval_denied'; end if;
 if exists(select 1 from core.economy_entry_approvals where entry_id=entry.id and approver_profile_id=actor_id) then
  raise check_violation using message='approval_already_recorded'; end if;
 insert into core.economy_entry_approvals(club_id,entry_id,approver_profile_id,decision,reason)
 values(entry.club_id,entry.id,actor_id,new_decision,btrim(new_reason));
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'economy.entry.approve.v1',jsonb_build_object('ok',true));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,reason,metadata)
 values(entry.club_id,actor_id,'economy.entry.approval.v1','economy_entry',entry.id,btrim(new_reason),jsonb_build_object('decision',new_decision));
end$$;

create or replace function internal.get_economy_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform internal.require_economy_actor(target_club_id,'economy.read');
 return jsonb_build_object(
  'accounts',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'team_id',a.team_id,'name',a.name,'currency',a.currency,'state',a.state) order by a.name),'[]'::jsonb) from core.economy_accounts a where a.club_id=target_club_id),
  'entries',(select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'account_id',e.account_id,'amount_minor',e.amount_minor,'currency',e.currency,
    'direction',e.direction,'category',e.category,'state',e.state,'risk_level',e.risk_level,
    'reversal_of',e.reversal_of,'created_at',e.created_at,'posted_at',e.posted_at,
    'required_approvals',case when e.risk_level='high' then 2 else 0 end,
    'approval_count',(select count(*) from core.economy_entry_approvals ea where ea.entry_id=e.id and ea.decision='approved'),
    'current_actor_approved',exists(select 1 from core.economy_entry_approvals ea where ea.entry_id=e.id and ea.approver_profile_id=auth.uid()),
    'approvers',(select coalesce(jsonb_agg(jsonb_build_object('profile_id',ea.approver_profile_id,'display_name',p.display_name,'decision',ea.decision) order by ea.decided_at),'[]'::jsonb) from core.economy_entry_approvals ea join core.profiles p on p.id=ea.approver_profile_id where ea.entry_id=e.id)
  ) order by e.created_at desc),'[]'::jsonb) from core.economy_ledger_entries e where e.club_id=target_club_id)
 );
end$$;

revoke all on function internal.approve_economy_entry_for_actor(uuid,text,text,uuid),internal.get_economy_for_actor(uuid) from public,anon,authenticated;

insert into internal.migration_provenance(migration_name,source_kind)
values('20260817201850_s10b_economy_approval_visibility','greenfield');
