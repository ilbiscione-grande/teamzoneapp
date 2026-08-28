create or replace function internal.decide_transfer_for_actor(target_transfer_id uuid, decision text, reason text, expected_revision bigint, idempotency_key uuid)
returns bigint language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); transfer_row core.transfer_cases%rowtype; actor_side text; existing_result jsonb; new_revision bigint;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if decision not in ('approved','rejected') then raise invalid_parameter_value using message='invalid_input'; end if;
  select result into existing_result from internal.command_deduplication where actor_profile_id=actor_id and command_type='roster.transfer.decide.v1' and internal.command_deduplication.idempotency_key=decide_transfer_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'revision')::bigint; end if;
  select * into transfer_row from core.transfer_cases where id=target_transfer_id for update;
  if transfer_row.id is null then raise insufficient_privilege using message='not_found'; end if;
  if transfer_row.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
  if transfer_row.state<>'requested' then raise check_violation using message='invalid_transition'; end if;
  if internal.actor_has_capability(transfer_row.source_club_id,transfer_row.source_team_id,'club.memberships.manage') then actor_side:='source';
  elsif internal.actor_has_capability(transfer_row.target_club_id,transfer_row.target_team_id,'club.memberships.manage') then actor_side:='target';
  else raise insufficient_privilege using message='not_found'; end if;
  insert into audit.transfer_approvals(transfer_case_id,transfer_revision,side,actor_profile_id,decision,reason) values(transfer_row.id,transfer_row.revision,actor_side,actor_id,decision,nullif(btrim(reason),''));
  new_revision:=transfer_row.revision;
  if decision='rejected' then update core.transfer_cases set state='rejected',revision=revision+1 where id=transfer_row.id returning revision into new_revision;
  elsif (select count(*) from audit.transfer_approvals approval where approval.transfer_case_id=transfer_row.id and approval.transfer_revision=transfer_row.revision and approval.decision='approved')=2 then update core.transfer_cases set state='approved',revision=revision+1 where id=transfer_row.id returning revision into new_revision;
  end if;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'roster.transfer.decide.v1',jsonb_build_object('revision',new_revision));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,reason,metadata) values(case when actor_side='source' then transfer_row.source_club_id else transfer_row.target_club_id end,actor_id,'roster.transfer.decide.v1','transfer_case',transfer_row.id,new_revision,nullif(btrim(reason),''),jsonb_build_object('side',actor_side,'decision',decision));
  return new_revision;
end;
$$;

revoke all on function internal.decide_transfer_for_actor(uuid,text,text,bigint,uuid) from public, anon;
grant execute on function internal.decide_transfer_for_actor(uuid,text,text,bigint,uuid) to authenticated;
insert into internal.migration_provenance(migration_name) values('20260807220626_s02_fix_transfer_decision');
