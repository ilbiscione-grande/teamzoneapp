-- S10B Board mandate changes with initiator separation and 2-of-2 approval.

create table core.board_mandate_changes (
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references core.clubs(id),
 target_assignment_id uuid not null,
 target_mandate_id uuid references core.board_mandates(id),
 action text not null check (action in ('grant','revoke')),
 office text not null check (office in ('chair','treasurer','secretary','member','auditor')),
 starts_at timestamptz,
 ends_at timestamptz,
 state text not null default 'pending' check (state in ('pending','applied','rejected','cancelled')),
 reason text not null check (length(btrim(reason)) between 3 and 500),
 created_by uuid not null references core.profiles(id),
 created_at timestamptz not null default now(),
 applied_at timestamptz,
 revision bigint not null default 1 check (revision > 0),
 foreign key (target_assignment_id,club_id) references core.assignments(id,club_id),
 check (
  (action='grant' and target_mandate_id is null and starts_at is not null and ends_at is not null and ends_at>starts_at)
  or
  (action='revoke' and target_mandate_id is not null and starts_at is null and ends_at is null)
 ),
 check ((state='applied' and applied_at is not null) or state<>'applied')
);

create index board_mandate_changes_club_state_created_idx
 on core.board_mandate_changes(club_id,state,created_at desc);
create index board_mandate_changes_assignment_idx
 on core.board_mandate_changes(target_assignment_id);
create index board_mandate_changes_target_mandate_idx
 on core.board_mandate_changes(target_mandate_id) where target_mandate_id is not null;
create index board_mandate_changes_created_by_idx
 on core.board_mandate_changes(created_by);

create table core.board_mandate_change_approvals (
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references core.clubs(id),
 change_id uuid not null references core.board_mandate_changes(id),
 approver_profile_id uuid not null references core.profiles(id),
 decision text not null check (decision in ('approved','rejected')),
 reason text not null check (length(btrim(reason)) between 3 and 500),
 decided_at timestamptz not null default now(),
 unique(change_id,approver_profile_id)
);

create index board_mandate_change_approvals_club_idx
 on core.board_mandate_change_approvals(club_id);
create index board_mandate_change_approvals_approver_idx
 on core.board_mandate_change_approvals(approver_profile_id);

alter table core.board_mandate_changes enable row level security;
alter table core.board_mandate_change_approvals enable row level security;
revoke all on table core.board_mandate_changes,core.board_mandate_change_approvals
 from public,anon,authenticated;

create function internal.create_board_mandate_change_for_actor(
 target_club_id uuid,target_assignment_id uuid,target_mandate_id uuid,
 new_action text,new_office text,new_starts_at timestamptz,new_ends_at timestamptz,
 new_reason text,idempotency_key uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare actor_id uuid; change_id uuid; prior jsonb; mandate core.board_mandates%rowtype;
begin
 actor_id:=internal.require_economy_actor(target_club_id,'board.manage');
 select result into prior from internal.command_deduplication
 where actor_profile_id=actor_id
   and internal.command_deduplication.idempotency_key=create_board_mandate_change_for_actor.idempotency_key
   and command_type='board.mandate_change.create.v1';
 if prior is not null then return (prior->>'id')::uuid; end if;
 if length(btrim(new_reason)) not between 3 and 500
   or new_office not in ('chair','treasurer','secretary','member','auditor')
   or new_action not in ('grant','revoke') then
  raise check_violation using message='invalid_mandate_change';
 end if;
 if not exists(select 1 from core.assignments assignment
   where assignment.id=target_assignment_id and assignment.club_id=target_club_id
     and assignment.state='active' and assignment.starts_at<=now()
     and (assignment.ends_at is null or assignment.ends_at>now())) then
  raise insufficient_privilege using message='not_found';
 end if;
 if new_action='grant' then
  if target_mandate_id is not null or new_starts_at is null or new_ends_at is null
     or new_ends_at<=new_starts_at or new_ends_at<=now() then
   raise check_violation using message='invalid_mandate_period';
  end if;
  if exists(select 1 from core.board_mandates existing
    where existing.club_id=target_club_id and existing.assignment_id=target_assignment_id
      and existing.office=new_office and existing.state='active'
      and tstzrange(existing.starts_at,existing.ends_at,'[)') && tstzrange(new_starts_at,new_ends_at,'[)')) then
   raise check_violation using message='mandate_overlap';
  end if;
 else
  select * into mandate from core.board_mandates existing
  where existing.id=target_mandate_id and existing.club_id=target_club_id
    and existing.assignment_id=target_assignment_id and existing.office=new_office
    and existing.state='active';
  if mandate.id is null then raise insufficient_privilege using message='not_found'; end if;
  new_starts_at:=null; new_ends_at:=null;
 end if;
 insert into core.board_mandate_changes(
  club_id,target_assignment_id,target_mandate_id,action,office,starts_at,ends_at,reason,created_by
 ) values(
  target_club_id,target_assignment_id,target_mandate_id,new_action,new_office,
  new_starts_at,new_ends_at,btrim(new_reason),actor_id
 ) returning id into change_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'board.mandate_change.create.v1',jsonb_build_object('id',change_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,reason,metadata)
 values(target_club_id,actor_id,'board.mandate_change.created.v1','board_mandate_change',change_id,btrim(new_reason),jsonb_build_object('action',new_action,'office',new_office));
 return change_id;
end$$;

create function internal.approve_board_mandate_change_for_actor(
 target_change_id uuid,new_decision text,new_reason text,idempotency_key uuid
) returns void language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); change_row core.board_mandate_changes%rowtype;
begin
 select * into change_row from core.board_mandate_changes where id=target_change_id;
 if change_row.id is null then raise insufficient_privilege using message='not_found'; end if;
 actor_id:=internal.require_economy_actor(change_row.club_id,'board.approve');
 if exists(select 1 from internal.command_deduplication
   where actor_profile_id=actor_id
     and internal.command_deduplication.idempotency_key=approve_board_mandate_change_for_actor.idempotency_key
     and command_type='board.mandate_change.approve.v1') then return; end if;
 if change_row.state<>'pending' or change_row.created_by=actor_id
   or new_decision not in ('approved','rejected')
   or length(btrim(new_reason)) not between 3 and 500 then
  raise insufficient_privilege using message='mandate_approval_denied';
 end if;
 if exists(select 1 from core.board_mandate_change_approvals
   where change_id=change_row.id and approver_profile_id=actor_id) then
  raise check_violation using message='mandate_approval_already_recorded';
 end if;
 insert into core.board_mandate_change_approvals(
  club_id,change_id,approver_profile_id,decision,reason
 ) values(change_row.club_id,change_row.id,actor_id,new_decision,btrim(new_reason));
 if new_decision='rejected' then
  update core.board_mandate_changes set state='rejected',revision=revision+1
  where id=change_row.id;
 end if;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'board.mandate_change.approve.v1',jsonb_build_object('ok',true));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,reason,metadata)
 values(change_row.club_id,actor_id,'board.mandate_change.approval.v1','board_mandate_change',change_row.id,btrim(new_reason),jsonb_build_object('decision',new_decision));
end$$;

create function internal.apply_board_mandate_change_for_actor(
 target_change_id uuid,idempotency_key uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); change_row core.board_mandate_changes%rowtype;
 mandate_id uuid; prior jsonb;
begin
 select * into change_row from core.board_mandate_changes where id=target_change_id for update;
 if change_row.id is null then raise insufficient_privilege using message='not_found'; end if;
 actor_id:=internal.require_economy_actor(change_row.club_id,'board.manage');
 select result into prior from internal.command_deduplication
 where actor_profile_id=actor_id
   and internal.command_deduplication.idempotency_key=apply_board_mandate_change_for_actor.idempotency_key
   and command_type='board.mandate_change.apply.v1';
 if prior is not null then return (prior->>'id')::uuid; end if;
 if change_row.state<>'pending' then raise check_violation using message='invalid_state'; end if;
 if exists(select 1 from core.board_mandate_change_approvals approval
   where approval.change_id=change_row.id and approval.decision='rejected') then
  raise insufficient_privilege using message='mandate_approval_rejected';
 end if;
 if (select count(*) from core.board_mandate_change_approvals approval
   where approval.change_id=change_row.id and approval.decision='approved')<2 then
  raise insufficient_privilege using message='mandate_approval_required';
 end if;
 if change_row.action='grant' then
  if change_row.ends_at<=now() or not exists(select 1 from core.assignments assignment
    where assignment.id=change_row.target_assignment_id and assignment.club_id=change_row.club_id
      and assignment.state='active' and assignment.starts_at<=now()
      and (assignment.ends_at is null or assignment.ends_at>now())) then
   raise check_violation using message='mandate_target_inactive';
  end if;
  if exists(select 1 from core.board_mandates existing
    where existing.club_id=change_row.club_id
      and existing.assignment_id=change_row.target_assignment_id
      and existing.office=change_row.office and existing.state='active'
      and tstzrange(existing.starts_at,existing.ends_at,'[)') && tstzrange(change_row.starts_at,change_row.ends_at,'[)')) then
   raise check_violation using message='mandate_overlap';
  end if;
  insert into core.board_mandates(club_id,assignment_id,office,starts_at,ends_at)
  values(change_row.club_id,change_row.target_assignment_id,change_row.office,change_row.starts_at,change_row.ends_at)
  returning id into mandate_id;
 else
  select id into mandate_id from core.board_mandates
  where id=change_row.target_mandate_id and club_id=change_row.club_id and state='active'
  for update;
  if mandate_id is null then raise check_violation using message='invalid_state'; end if;
  update core.board_mandates set state='revoked',revision=revision+1 where id=mandate_id;
 end if;
 update core.board_mandate_changes set state='applied',applied_at=now(),revision=revision+1
 where id=change_row.id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'board.mandate_change.apply.v1',jsonb_build_object('id',mandate_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,reason,metadata)
 values(change_row.club_id,actor_id,'board.mandate_change.applied.v1','board_mandate',mandate_id,1,change_row.reason,jsonb_build_object('change_id',change_row.id,'action',change_row.action,'office',change_row.office));
 return mandate_id;
end$$;

create function internal.get_board_for_actor(target_club_id uuid)
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
    'state',mandate.state,'revision',mandate.revision
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

create function api.create_board_mandate_change(
 target_club_id uuid,target_assignment_id uuid,target_mandate_id uuid,
 new_action text,new_office text,new_starts_at timestamptz,new_ends_at timestamptz,
 new_reason text,idempotency_key uuid
) returns uuid language sql security definer set search_path='' as $$
 select internal.create_board_mandate_change_for_actor(target_club_id,target_assignment_id,target_mandate_id,new_action,new_office,new_starts_at,new_ends_at,new_reason,idempotency_key)
$$;
create function api.approve_board_mandate_change(
 target_change_id uuid,new_decision text,new_reason text,idempotency_key uuid
) returns void language sql security definer set search_path='' as $$
 select internal.approve_board_mandate_change_for_actor(target_change_id,new_decision,new_reason,idempotency_key)
$$;
create function api.apply_board_mandate_change(target_change_id uuid,idempotency_key uuid)
returns uuid language sql security definer set search_path='' as $$
 select internal.apply_board_mandate_change_for_actor(target_change_id,idempotency_key)
$$;
create function api.get_board(target_club_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select internal.get_board_for_actor(target_club_id)
$$;

revoke all on function
 internal.create_board_mandate_change_for_actor(uuid,uuid,uuid,text,text,timestamptz,timestamptz,text,uuid),
 internal.approve_board_mandate_change_for_actor(uuid,text,text,uuid),
 internal.apply_board_mandate_change_for_actor(uuid,uuid),
 internal.get_board_for_actor(uuid)
 from public,anon,authenticated;
revoke all on function
 api.create_board_mandate_change(uuid,uuid,uuid,text,text,timestamptz,timestamptz,text,uuid),
 api.approve_board_mandate_change(uuid,text,text,uuid),
 api.apply_board_mandate_change(uuid,uuid),api.get_board(uuid)
 from public,anon;
grant execute on function
 api.create_board_mandate_change(uuid,uuid,uuid,text,text,timestamptz,timestamptz,text,uuid),
 api.approve_board_mandate_change(uuid,text,text,uuid),
 api.apply_board_mandate_change(uuid,uuid),api.get_board(uuid)
 to authenticated;

insert into internal.migration_provenance(migration_name,source_kind)
values('20260822082158_s10b_board_mandate_commands','greenfield');
