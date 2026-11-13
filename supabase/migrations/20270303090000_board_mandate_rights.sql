-- A board mandate gives its office's rights while it runs (chair, treasurer,
-- secretary, member, auditor), and they end with it: no grants to remember
-- to take back. The board register no longer needs the economy module (the
-- economy itself still does). A new club forms its first board directly:
-- while fewer than three people hold a mandate, a change is registered at
-- once by members and teams or the board; then two approvals are needed.
-- Members and teams may also see the board. Functions are their live
-- versions with these changes.

-- What each office may do in the club.
create or replace function internal.board_office_capabilities(office text)
returns text[] language sql immutable set search_path = '' as $$
  select case office
    when 'chair' then array['board.read','board.manage','board.approve','economy.read','economy.approve']
    when 'treasurer' then array['board.read','board.approve','economy.read','economy.post','economy.manage',
      'economy.approve','economy.reverse']
    when 'secretary' then array['board.read','board.manage','board.approve']
    when 'member' then array['board.read','board.approve','economy.read']
    when 'auditor' then array['board.read','economy.read']
    else array[]::text[] end
$$;

-- The rights an assignment has from its running mandates.
create or replace function internal.assignment_mandate_capabilities(target_assignment_id uuid)
returns text[] language sql stable security definer set search_path = '' as $$
  select coalesce(array(
    select distinct capability
    from core.board_mandates mandate,
      unnest(internal.board_office_capabilities(mandate.office)) capability
    where mandate.assignment_id = target_assignment_id and mandate.state = 'active'
      and mandate.starts_at <= now() and mandate.ends_at > now()
    order by 1), '{}')
$$;

create or replace function internal.merge_capabilities(first_list text[], second_list text[])
returns text[] language sql immutable set search_path = '' as $$
  select coalesce(array(select distinct value from unnest(coalesce(first_list, '{}') || coalesce(second_list, '{}')) value
    order by 1), '{}')
$$;

-- Fewer than three people hold a running mandate: the board is forming.
create or replace function internal.board_forming(target_club_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select (select count(distinct mandate.assignment_id) from core.board_mandates mandate
    where mandate.club_id = target_club_id and mandate.state = 'active'
      and mandate.starts_at <= now() and mandate.ends_at > now()) < 3
$$;

-- The board's own commands: the right, without the economy module.
create or replace function internal.require_board_actor(target_club_id uuid, target_capability text)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid := auth.uid();
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id, null, target_capability) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return actor_id;
end
$$;

revoke all on function internal.board_office_capabilities(text), internal.assignment_mandate_capabilities(uuid),
  internal.merge_capabilities(text[], text[]), internal.board_forming(uuid), internal.require_board_actor(uuid, text)
  from public, anon, authenticated;

-- As live, with the board mandates' rights.
CREATE OR REPLACE FUNCTION internal.actor_has_capability(target_club_id uuid, target_team_id uuid, required_capability text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select auth.uid() is not null and (exists (
    select 1
    from core.person_account_links link
    join core.assignments assignment
      on assignment.club_person_id = link.club_person_id
     and assignment.club_id = link.club_id
    join core.capability_grants grant_row
      on grant_row.assignment_id = assignment.id
     and grant_row.club_id = assignment.club_id
    where link.profile_id = auth.uid()
      and link.state = 'active'
      and assignment.state = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
      and assignment.club_id = target_club_id
      and (
        grant_row.capability = required_capability
        or (
          required_capability = 'club.memberships.manage'
          and target_team_id is not null
          and grant_row.capability = 'team.roster.manage'
          and grant_row.scope_type = 'team'
        )
      )
      and grant_row.starts_at <= now()
      and (grant_row.ends_at is null or grant_row.ends_at > now())
      and (
        (grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id)
        or (grant_row.scope_type = 'team' and grant_row.scope_id = target_team_id)
      )
  ) or exists (
    -- A board mandate gives its office's rights in the club while it runs.
    select 1
    from core.person_account_links link
    join core.assignments assignment
      on assignment.club_person_id = link.club_person_id
     and assignment.club_id = link.club_id
    join core.board_mandates mandate
      on mandate.assignment_id = assignment.id
     and mandate.club_id = assignment.club_id
    where link.profile_id = auth.uid()
      and link.state = 'active'
      and assignment.state = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
      and assignment.club_id = target_club_id
      and mandate.state = 'active'
      and mandate.starts_at <= now()
      and mandate.ends_at > now()
      and required_capability = any(internal.board_office_capabilities(mandate.office))
  ));
$function$;

-- As live, listing the board mandates' rights with the grants.
CREATE OR REPLACE FUNCTION internal.get_my_contexts_for_actor()
 RETURNS TABLE(context_id uuid, club_id uuid, club_name text, team_id uuid, team_name text, role_package text, capabilities text[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;

  return query
  select
    assignment.id,
    club.id,
    club.name,
    team.id,
    team.name,
    assignment.role_package,
    internal.merge_capabilities(coalesce(
      array_agg(distinct capability.capability order by capability.capability)
        filter (
          where capability.id is not null
            and capability.starts_at <= now()
            and (capability.ends_at is null or capability.ends_at > now())
            and (
              (capability.scope_type = 'club' and capability.scope_id = assignment.club_id)
              or
              (capability.scope_type = 'team' and capability.scope_id = assignment.team_id)
            )
        ),
      array[]::text[]
    ), internal.assignment_mandate_capabilities(assignment.id))
  from core.person_account_links link
  join core.assignments assignment
    on assignment.club_person_id = link.club_person_id
   and assignment.club_id = link.club_id
  join core.clubs club on club.id = assignment.club_id and club.status = 'active'
  left join core.teams team
    on team.id = assignment.team_id
   and team.club_id = assignment.club_id
   and team.status = 'active'
  left join core.capability_grants capability
    on capability.assignment_id = assignment.id
   and capability.club_id = assignment.club_id
  where link.profile_id = auth.uid()
    and link.state = 'active'
    and assignment.state = 'active'
    and assignment.starts_at <= now()
    and (assignment.ends_at is null or assignment.ends_at > now())
    and (assignment.team_id is null or team.id is not null)
  group by assignment.id, club.id, club.name, team.id, team.name, assignment.role_package
  order by club.name, team.name nulls first, assignment.id;
end;
$function$;

-- As live, open to members and teams, saying whether the board is forming.
CREATE OR REPLACE FUNCTION internal.get_board_for_actor(target_club_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 -- The board, or members and teams (who forms the first board).
 if auth.uid() is null or not (internal.actor_has_capability(target_club_id,null,'board.read')
   or internal.actor_has_capability(target_club_id,null,'club.memberships.manage')) then
  raise insufficient_privilege using message='not_found';
 end if;
 return jsonb_build_object(
  'forming',internal.board_forming(target_club_id),
  'can_register',internal.board_forming(target_club_id) and (
    internal.actor_has_capability(target_club_id,null,'board.manage')
    or internal.actor_has_capability(target_club_id,null,'club.memberships.manage')),
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
end$function$;

-- As live, registered at once while the board is forming; without the
-- economy module.
CREATE OR REPLACE FUNCTION internal.create_board_mandate_change_for_actor(target_club_id uuid, target_assignment_id uuid, target_mandate_id uuid, new_action text, new_office text, new_starts_at timestamp with time zone, new_ends_at timestamp with time zone, new_reason text, idempotency_key uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor_id uuid; change_id uuid; prior jsonb; mandate core.board_mandates%rowtype;
 forming boolean; direct_mandate uuid;
begin
 actor_id:=auth.uid();
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 perform pg_advisory_xact_lock(hashtextextended('board-mandates:'||target_club_id::text,0));
 -- While the board is forming (under three people) a change is registered
 -- at once, also by members and teams; then two approvals are needed.
 forming:=internal.board_forming(target_club_id);
 if not (internal.actor_has_capability(target_club_id,null,'board.manage')
   or (forming and internal.actor_has_capability(target_club_id,null,'club.memberships.manage'))) then
  raise insufficient_privilege using message='not_found';
 end if;
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
 if forming then
  if new_action='grant' then
   insert into core.board_mandates(club_id,assignment_id,office,starts_at,ends_at)
   values(target_club_id,target_assignment_id,new_office,new_starts_at,new_ends_at)
   returning id into direct_mandate;
  else
   update core.board_mandates set state='revoked',revision=revision+1 where id=mandate.id;
   direct_mandate:=mandate.id;
  end if;
  update core.board_mandate_changes set state='applied',applied_at=now(),revision=revision+1
  where id=change_id;
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,reason,metadata)
  values(target_club_id,actor_id,'board.mandate_change.applied.v1','board_mandate',direct_mandate,1,btrim(new_reason),
   jsonb_build_object('change_id',change_id,'action',new_action,'office',new_office,'forming',true));
 end if;
 return change_id;
end$function$;

-- As live, without the economy module.
CREATE OR REPLACE FUNCTION internal.approve_board_mandate_change_for_actor(target_change_id uuid, new_decision text, new_reason text, idempotency_key uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor_id uuid:=auth.uid(); change_row core.board_mandate_changes%rowtype;
begin
 select * into change_row from core.board_mandate_changes where id=target_change_id;
 if change_row.id is null then raise insufficient_privilege using message='not_found'; end if;
 actor_id:=internal.require_board_actor(change_row.club_id,'board.approve');
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
end$function$;

-- As live, without the economy module.
CREATE OR REPLACE FUNCTION internal.apply_board_mandate_change_for_actor(target_change_id uuid, idempotency_key uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor_id uuid:=auth.uid(); change_row core.board_mandate_changes%rowtype;
 mandate_id uuid; prior jsonb;
begin
 select * into change_row from core.board_mandate_changes where id=target_change_id for update;
 if change_row.id is null then raise insufficient_privilege using message='not_found'; end if;
 actor_id:=internal.require_board_actor(change_row.club_id,'board.manage');
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
end$function$;

notify pgrst, 'reload schema';
