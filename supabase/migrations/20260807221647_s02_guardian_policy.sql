create table core.guardian_invites (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  guardian_person_id uuid not null,
  child_person_id uuid not null,
  token_hash bytea not null unique,
  state text not null default 'issued'
    check (state in ('issued', 'consumed', 'expired', 'revoked')),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consumed_by uuid references core.profiles(id),
  created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  foreign key (guardian_person_id, club_id)
    references core.club_people(id, club_id),
  foreign key (child_person_id, club_id)
    references core.club_people(id, club_id),
  check (guardian_person_id <> child_person_id),
  check (expires_at > created_at),
  check (
    (state = 'consumed' and consumed_at is not null and consumed_by is not null)
    or state <> 'consumed'
  )
);

create unique index guardian_relations_one_active_pair
on core.guardian_relations (guardian_person_id, child_person_id)
where state = 'active';

create index guardian_invites_guardian_club_idx
on core.guardian_invites (guardian_person_id, club_id);
create index guardian_invites_child_club_idx
on core.guardian_invites (child_person_id, club_id);
create index guardian_invites_created_by_idx
on core.guardian_invites (created_by);
create index guardian_invites_consumed_by_idx
on core.guardian_invites (consumed_by);

alter table core.guardian_invites enable row level security;
create policy guardian_invites_no_direct_select
on core.guardian_invites for select to authenticated using (false);

alter table audit.transfer_approvals
  drop constraint transfer_approvals_side_check,
  add constraint transfer_approvals_side_check
    check (side in ('source', 'target', 'guardian'));

create function internal.issue_guardian_invite_for_actor(
  target_guardian_person_id uuid,
  target_child_person_id uuid,
  raw_token text,
  expires_at timestamptz,
  idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = '', extensions
as $$
declare
  actor_id uuid := auth.uid();
  target_club_id uuid;
  child_requires_guardian boolean;
  invite_id uuid;
  existing_result jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;

  select child.club_id, child.safeguarding_required
  into target_club_id, child_requires_guardian
  from core.club_people child
  where child.id = target_child_person_id and child.status = 'active';

  if target_club_id is null
     or not child_requires_guardian
     or not exists (
       select 1 from core.club_people guardian
       where guardian.id = target_guardian_person_id
         and guardian.club_id = target_club_id
         and guardian.status = 'active'
     )
     or not internal.actor_has_capability(
       target_club_id,
       null,
       'club.safeguarding.manage'
     )
  then
    raise insufficient_privilege using message = 'not_found';
  end if;

  if length(raw_token) < 32
     or expires_at <= now()
     or expires_at > now() + interval '7 days'
  then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;

  select result into existing_result
  from internal.command_deduplication
  where actor_profile_id = actor_id
    and command_type = 'roster.guardian_invite.issue.v1'
    and internal.command_deduplication.idempotency_key =
      issue_guardian_invite_for_actor.idempotency_key;
  if existing_result is not null then
    return (existing_result ->> 'invite_id')::uuid;
  end if;

  if exists (
    select 1 from core.guardian_relations relation
    where relation.guardian_person_id = target_guardian_person_id
      and relation.child_person_id = target_child_person_id
      and relation.state = 'active'
  ) then
    raise unique_violation using message = 'guardian_relation_conflict';
  end if;

  insert into core.guardian_invites (
    club_id,
    guardian_person_id,
    child_person_id,
    token_hash,
    expires_at,
    created_by
  ) values (
    target_club_id,
    target_guardian_person_id,
    target_child_person_id,
    extensions.digest(raw_token, 'sha256'),
    expires_at,
    actor_id
  ) returning id into invite_id;

  insert into internal.command_deduplication (
    actor_profile_id,
    idempotency_key,
    command_type,
    result
  ) values (
    actor_id,
    idempotency_key,
    'roster.guardian_invite.issue.v1',
    jsonb_build_object('invite_id', invite_id)
  );

  insert into audit.command_events (
    club_id,
    actor_profile_id,
    command_type,
    aggregate_type,
    aggregate_id,
    aggregate_revision
  ) values (
    target_club_id,
    actor_id,
    'roster.guardian_invite.issue.v1',
    'guardian_invite',
    invite_id,
    1
  );

  return invite_id;
end;
$$;

create function internal.accept_guardian_invite_for_actor(
  raw_token text,
  idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = '', extensions
as $$
declare
  actor_id uuid := auth.uid();
  invite_row core.guardian_invites%rowtype;
  relation_id uuid;
  existing_result jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;

  select result into existing_result
  from internal.command_deduplication
  where actor_profile_id = actor_id
    and command_type = 'roster.guardian_invite.accept.v1'
    and internal.command_deduplication.idempotency_key =
      accept_guardian_invite_for_actor.idempotency_key;
  if existing_result is not null then
    return (existing_result ->> 'guardian_relation_id')::uuid;
  end if;

  select * into invite_row
  from core.guardian_invites
  where token_hash = extensions.digest(raw_token, 'sha256')
  for update;

  if invite_row.id is null
     or invite_row.state <> 'issued'
     or invite_row.expires_at <= now()
  then
    raise invalid_parameter_value using message = 'invalid_or_expired_token';
  end if;

  if not exists (
    select 1 from core.person_account_links link
    where link.club_id = invite_row.club_id
      and link.club_person_id = invite_row.guardian_person_id
      and link.profile_id = actor_id
      and link.state = 'active'
  ) then
    raise insufficient_privilege using message = 'guardian_account_mismatch';
  end if;

  insert into core.guardian_relations (
    club_id,
    guardian_person_id,
    child_person_id,
    kind,
    state,
    starts_at,
    created_by
  ) values (
    invite_row.club_id,
    invite_row.guardian_person_id,
    invite_row.child_person_id,
    'guardian',
    'active',
    now(),
    actor_id
  ) returning id into relation_id;

  update core.guardian_invites
  set state = 'consumed',
      consumed_at = now(),
      consumed_by = actor_id,
      revision = revision + 1
  where id = invite_row.id;

  insert into internal.command_deduplication (
    actor_profile_id,
    idempotency_key,
    command_type,
    result
  ) values (
    actor_id,
    idempotency_key,
    'roster.guardian_invite.accept.v1',
    jsonb_build_object('guardian_relation_id', relation_id)
  );

  insert into audit.command_events (
    club_id,
    actor_profile_id,
    command_type,
    aggregate_type,
    aggregate_id,
    aggregate_revision,
    metadata
  ) values (
    invite_row.club_id,
    actor_id,
    'roster.guardian_invite.accept.v1',
    'guardian_relation',
    relation_id,
    1,
    jsonb_build_object(
      'acting_as_guardian_person_id', invite_row.guardian_person_id,
      'child_person_id', invite_row.child_person_id
    )
  );

  return relation_id;
end;
$$;

create or replace function internal.set_guardian_relation_for_actor()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  raise feature_not_supported using message = 'guardian_invite_required';
end;
$$;

create or replace function internal.decide_transfer_for_actor(
  target_transfer_id uuid,
  decision text,
  reason text,
  expected_revision bigint,
  idempotency_key uuid
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  transfer_row core.transfer_cases%rowtype;
  actor_side text;
  existing_result jsonb;
  new_revision bigint;
  guardian_required boolean;
  required_approvals integer;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if decision not in ('approved','rejected') then raise invalid_parameter_value using message='invalid_input'; end if;
  select result into existing_result from internal.command_deduplication where actor_profile_id=actor_id and command_type='roster.transfer.decide.v1' and internal.command_deduplication.idempotency_key=decide_transfer_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'revision')::bigint; end if;
  select * into transfer_row from core.transfer_cases where id=target_transfer_id for update;
  if transfer_row.id is null then raise insufficient_privilege using message='not_found'; end if;
  if transfer_row.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
  if transfer_row.state<>'requested' then raise check_violation using message='invalid_transition'; end if;

  select source_person.safeguarding_required
  into guardian_required
  from core.club_people source_person
  where source_person.id = transfer_row.source_club_person_id
    and source_person.club_id = transfer_row.source_club_id;

  if internal.actor_has_capability(transfer_row.source_club_id,transfer_row.source_team_id,'club.memberships.manage') then actor_side:='source';
  elsif internal.actor_has_capability(transfer_row.target_club_id,transfer_row.target_team_id,'club.memberships.manage') then actor_side:='target';
  elsif guardian_required and exists (
    select 1
    from core.guardian_relations relation
    join core.person_account_links link
      on link.club_id = relation.club_id
     and link.club_person_id = relation.guardian_person_id
    where relation.club_id = transfer_row.source_club_id
      and relation.child_person_id = transfer_row.source_club_person_id
      and relation.state = 'active'
      and relation.starts_at <= now()
      and (relation.ends_at is null or relation.ends_at > now())
      and link.profile_id = actor_id
      and link.state = 'active'
  ) then actor_side:='guardian';
  else raise insufficient_privilege using message='not_found'; end if;

  insert into audit.transfer_approvals(transfer_case_id,transfer_revision,side,actor_profile_id,decision,reason) values(transfer_row.id,transfer_row.revision,actor_side,actor_id,decision,nullif(btrim(reason),''));
  new_revision:=transfer_row.revision;
  required_approvals := case when guardian_required then 3 else 2 end;
  if decision='rejected' then update core.transfer_cases set state='rejected',revision=revision+1 where id=transfer_row.id returning revision into new_revision;
  elsif (select count(*) from audit.transfer_approvals approval where approval.transfer_case_id=transfer_row.id and approval.transfer_revision=transfer_row.revision and approval.decision='approved')=required_approvals then update core.transfer_cases set state='approved',revision=revision+1 where id=transfer_row.id returning revision into new_revision;
  end if;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'roster.transfer.decide.v1',jsonb_build_object('revision',new_revision));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,reason,metadata) values(case when actor_side='target' then transfer_row.target_club_id else transfer_row.source_club_id end,actor_id,'roster.transfer.decide.v1','transfer_case',transfer_row.id,new_revision,nullif(btrim(reason),''),jsonb_build_object('side',actor_side,'decision',decision));
  return new_revision;
end;
$$;

create or replace function internal.complete_transfer_for_actor(
  target_transfer_id uuid,
  expected_revision bigint,
  idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); transfer_row core.transfer_cases%rowtype; source_person core.club_people%rowtype; target_person_id uuid; existing_result jsonb; required_approvals integer;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select result into existing_result from internal.command_deduplication where actor_profile_id=actor_id and command_type='roster.transfer.complete.v1' and internal.command_deduplication.idempotency_key=complete_transfer_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'club_person_id')::uuid; end if;
  select * into transfer_row from core.transfer_cases where id=target_transfer_id for update;
  if transfer_row.id is null or not internal.actor_has_capability(transfer_row.target_club_id,transfer_row.target_team_id,'club.memberships.manage') then raise insufficient_privilege using message='not_found'; end if;
  if transfer_row.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
  if transfer_row.state<>'approved' or transfer_row.effective_at>now() then raise check_violation using message='invalid_transition'; end if;
  select * into source_person from core.club_people where id=transfer_row.source_club_person_id and club_id=transfer_row.source_club_id;
  required_approvals := case when source_person.safeguarding_required then 3 else 2 end;
  if (select count(*) from audit.transfer_approvals approval where approval.transfer_case_id=transfer_row.id and approval.transfer_revision=transfer_row.revision-1 and approval.decision='approved')<>required_approvals then raise insufficient_privilege using message='approval_required'; end if;
  update core.team_assignments set state='ended',ends_at=transfer_row.effective_at,ended_by=actor_id,revision=revision+1 where club_person_id=source_person.id and team_id=transfer_row.source_team_id and state='active' and starts_at<transfer_row.effective_at;
  select id into target_person_id from core.club_people where person_id=transfer_row.person_id and club_id=transfer_row.target_club_id;
  if target_person_id is null then insert into core.club_people(club_id,person_id,display_name,age_class,safeguarding_required,provenance,created_by) values(transfer_row.target_club_id,transfer_row.person_id,source_person.display_name,source_person.age_class,source_person.safeguarding_required,'transfer',actor_id) returning id into target_person_id; end if;
  insert into core.team_assignments(club_id,team_id,club_person_id,starts_at,created_by) values(transfer_row.target_club_id,transfer_row.target_team_id,target_person_id,transfer_row.effective_at,actor_id);
  update core.transfer_cases set state='completed',completed_club_person_id=target_person_id,revision=revision+1 where id=transfer_row.id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'roster.transfer.complete.v1',jsonb_build_object('club_person_id',target_person_id));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata) values(transfer_row.target_club_id,actor_id,'roster.transfer.complete.v1','transfer_case',transfer_row.id,transfer_row.revision+1,jsonb_build_object('source_club_id',transfer_row.source_club_id,'target_club_id',transfer_row.target_club_id,'club_person_id',target_person_id,'guardian_approval_required',source_person.safeguarding_required));
  return target_person_id;
end;
$$;

revoke all on table core.guardian_invites from public, anon, authenticated;
revoke all on function internal.issue_guardian_invite_for_actor(uuid,uuid,text,timestamptz,uuid), internal.accept_guardian_invite_for_actor(text,uuid) from public, anon, authenticated;
grant execute on function internal.issue_guardian_invite_for_actor(uuid,uuid,text,timestamptz,uuid), internal.accept_guardian_invite_for_actor(text,uuid) to authenticated;

create function api.issue_guardian_invite(
  guardian_person_id uuid,
  child_person_id uuid,
  raw_token text,
  expires_at timestamptz,
  idempotency_key uuid
) returns uuid language sql security invoker set search_path = '' as $$
  select internal.issue_guardian_invite_for_actor(guardian_person_id,child_person_id,raw_token,expires_at,idempotency_key);
$$;

create function api.accept_guardian_invite(raw_token text,idempotency_key uuid)
returns uuid language sql security invoker set search_path = '' as $$
  select internal.accept_guardian_invite_for_actor(raw_token,idempotency_key);
$$;

revoke all on function api.issue_guardian_invite(uuid,uuid,text,timestamptz,uuid), api.accept_guardian_invite(text,uuid) from public, anon;
grant execute on function api.issue_guardian_invite(uuid,uuid,text,timestamptz,uuid), api.accept_guardian_invite(text,uuid) to authenticated;

insert into internal.migration_provenance(migration_name)
values('20260807221647_s02_guardian_policy');
notify pgrst, 'reload schema';
