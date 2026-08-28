-- S02 greenfield roster lifecycle. Teamzone6 is not a source or target.

create table core.persons (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'active' check (status in ('active', 'merged', 'ended')),
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0)
);

alter table core.club_people
  add column person_id uuid default gen_random_uuid(),
  add column age_class text,
  add column safeguarding_required boolean not null default false;

insert into core.persons (id, created_at, created_by)
select person_id, created_at, created_by from core.club_people;

alter table core.club_people
  alter column person_id set not null,
  add constraint club_people_person_id_fkey foreign key (person_id) references core.persons(id),
  add constraint club_people_person_club_unique unique (person_id, club_id);

create table core.team_assignments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  team_id uuid not null,
  club_person_id uuid not null,
  kind text not null default 'home' check (kind = 'home'),
  state text not null default 'active' check (state in ('active', 'ended')),
  starts_at timestamptz not null,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  ended_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id),
  foreign key (team_id, club_id) references core.teams(id, club_id),
  foreign key (club_person_id, club_id) references core.club_people(id, club_id),
  check (ends_at is null or ends_at > starts_at),
  check ((state = 'active' and ends_at is null) or state = 'ended')
);

create table core.play_eligibilities (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  team_id uuid not null,
  club_person_id uuid not null,
  kind text not null check (kind in ('development', 'dispensation', 'loan', 'guest', 'cross_team')),
  source_club_id uuid,
  source text not null check (length(btrim(source)) between 2 and 80),
  state text not null default 'active' check (state in ('pending', 'active', 'ended', 'rejected')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id),
  foreign key (team_id, club_id) references core.teams(id, club_id),
  foreign key (club_person_id, club_id) references core.club_people(id, club_id),
  foreign key (source_club_id) references core.clubs(id),
  check (ends_at > starts_at),
  check ((kind in ('loan', 'guest') and source_club_id is not null) or kind not in ('loan', 'guest'))
);

create table core.guardian_relations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  guardian_person_id uuid not null,
  child_person_id uuid not null,
  kind text not null check (kind in ('guardian', 'custodian')),
  state text not null default 'pending' check (state in ('pending', 'active', 'ended', 'rejected')),
  starts_at timestamptz not null,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id),
  foreign key (guardian_person_id, club_id) references core.club_people(id, club_id),
  foreign key (child_person_id, club_id) references core.club_people(id, club_id),
  check (guardian_person_id <> child_person_id),
  check (ends_at is null or ends_at > starts_at)
);

create table core.roster_invites (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  club_person_id uuid not null,
  token_hash bytea not null unique,
  allowed_action text not null default 'claim' check (allowed_action = 'claim'),
  state text not null default 'issued' check (state in ('issued', 'consumed', 'expired', 'revoked')),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consumed_by uuid references core.profiles(id),
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  foreign key (club_person_id, club_id) references core.club_people(id, club_id),
  check (expires_at > created_at),
  check ((state = 'consumed' and consumed_at is not null and consumed_by is not null) or state <> 'consumed')
);

create table core.transfer_cases (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references core.persons(id),
  source_club_id uuid not null references core.clubs(id),
  source_team_id uuid not null,
  source_club_person_id uuid not null,
  target_club_id uuid not null references core.clubs(id),
  target_team_id uuid not null,
  state text not null default 'requested' check (state in ('requested', 'approved', 'rejected', 'completed', 'cancelled')),
  effective_at timestamptz not null,
  completed_club_person_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  unique (id, source_club_id, target_club_id),
  foreign key (source_team_id, source_club_id) references core.teams(id, club_id),
  foreign key (target_team_id, target_club_id) references core.teams(id, club_id),
  foreign key (source_club_person_id, source_club_id) references core.club_people(id, club_id),
  foreign key (completed_club_person_id, target_club_id) references core.club_people(id, club_id),
  check (source_club_id <> target_club_id)
);

create table audit.transfer_approvals (
  id uuid primary key default gen_random_uuid(),
  transfer_case_id uuid not null references core.transfer_cases(id),
  transfer_revision bigint not null,
  side text not null check (side in ('source', 'target')),
  actor_profile_id uuid not null references core.profiles(id),
  decision text not null check (decision in ('approved', 'rejected')),
  reason text,
  occurred_at timestamptz not null default now(),
  unique (transfer_case_id, transfer_revision, side)
);

create index team_assignments_person_period_idx on core.team_assignments (club_person_id, starts_at, ends_at);
create index team_assignments_team_active_idx on core.team_assignments (team_id, club_id) where state = 'active';
create index play_eligibilities_person_period_idx on core.play_eligibilities (club_person_id, starts_at, ends_at);
create index guardian_relations_child_active_idx on core.guardian_relations (child_person_id, club_id) where state = 'active';
create index roster_invites_person_state_idx on core.roster_invites (club_person_id, state, expires_at);
create index transfer_cases_person_state_idx on core.transfer_cases (person_id, state);
create index transfer_cases_source_club_idx on core.transfer_cases (source_club_id);
create index transfer_cases_target_club_idx on core.transfer_cases (target_club_id);

create function internal.actor_has_capability(target_club_id uuid, target_team_id uuid, required_capability text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from core.person_account_links link
    join core.assignments assignment
      on assignment.club_person_id = link.club_person_id and assignment.club_id = link.club_id
    join core.capability_grants grant_row
      on grant_row.assignment_id = assignment.id and grant_row.club_id = assignment.club_id
    where link.profile_id = auth.uid() and link.state = 'active'
      and assignment.state = 'active' and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
      and assignment.club_id = target_club_id
      and grant_row.capability = required_capability
      and grant_row.starts_at <= now() and (grant_row.ends_at is null or grant_row.ends_at > now())
      and ((grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id)
        or (grant_row.scope_type = 'team' and grant_row.scope_id = target_team_id))
  );
$$;

create function internal.enforce_team_assignment_period()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.state = 'active' and exists (
    select 1 from core.team_assignments current_row
    where current_row.id <> new.id and current_row.club_person_id = new.club_person_id
      and current_row.state = 'active'
      and tstzrange(current_row.starts_at, coalesce(current_row.ends_at, 'infinity'), '[)') &&
          tstzrange(new.starts_at, coalesce(new.ends_at, 'infinity'), '[)')
  ) then raise exclusion_violation using message = 'overlapping_home_assignment'; end if;
  return new;
end;
$$;

create trigger team_assignments_enforce_period before insert or update on core.team_assignments
for each row execute function internal.enforce_team_assignment_period();

create function internal.list_club_people_for_actor(target_club_id uuid, target_team_id uuid default null)
returns table (club_person_id uuid, display_name text, age_class text, safeguarding_required boolean,
  team_id uuid, team_name text, assignment_state text, assignment_starts_at timestamptz, assignment_ends_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id, target_team_id, 'team.roster.view')
     and not internal.actor_has_capability(target_club_id, target_team_id, 'club.memberships.manage')
  then raise insufficient_privilege using message = 'not_found'; end if;
  return query select person.id, person.display_name, person.age_class, person.safeguarding_required,
    team.id, team.name, home.state, home.starts_at, home.ends_at
  from core.club_people person
  left join core.team_assignments home on home.club_person_id = person.id and home.club_id = person.club_id
    and home.state = 'active'
  left join core.teams team on team.id = home.team_id and team.club_id = home.club_id
  where person.club_id = target_club_id and person.status = 'active'
    and (target_team_id is null or home.team_id = target_team_id)
  order by person.display_name, person.id;
end;
$$;

create function internal.create_roster_person_for_actor(target_club_id uuid, target_team_id uuid,
  new_display_name text, new_age_class text, starts_at timestamptz, idempotency_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); new_person_id uuid; new_club_person_id uuid; existing_result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id, target_team_id, 'club.memberships.manage')
  then raise insufficient_privilege using message = 'not_found'; end if;
  if length(btrim(new_display_name)) not between 1 and 120 then raise invalid_parameter_value using message = 'invalid_input'; end if;
  select result into existing_result from internal.command_deduplication where actor_profile_id=actor_id and command_type='roster.person.create.v1' and internal.command_deduplication.idempotency_key=create_roster_person_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'club_person_id')::uuid; end if;
  insert into core.persons(created_by) values(actor_id) returning id into new_person_id;
  insert into core.club_people(club_id,person_id,display_name,age_class,created_by) values(target_club_id,new_person_id,btrim(new_display_name),nullif(btrim(new_age_class),''),actor_id) returning id into new_club_person_id;
  insert into core.team_assignments(club_id,team_id,club_person_id,starts_at,created_by) values(target_club_id,target_team_id,new_club_person_id,starts_at,actor_id);
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'roster.person.create.v1',jsonb_build_object('club_person_id',new_club_person_id));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision) values(target_club_id,actor_id,'roster.person.create.v1','club_person',new_club_person_id,1);
  return new_club_person_id;
end;
$$;

create function internal.issue_roster_invite_for_actor(target_club_person_id uuid, raw_token text, expires_at timestamptz, idempotency_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); target_club_id uuid; invite_id uuid; existing_result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select club_id into target_club_id from core.club_people where id=target_club_person_id and status='active';
  if target_club_id is null or not internal.actor_has_capability(target_club_id,null,'club.memberships.manage') then raise insufficient_privilege using message='not_found'; end if;
  if length(raw_token)<32 or expires_at<=now() or expires_at>now()+interval '14 days' then raise invalid_parameter_value using message='invalid_input'; end if;
  select result into existing_result from internal.command_deduplication where actor_profile_id=actor_id and command_type='roster.invite.issue.v1' and internal.command_deduplication.idempotency_key=issue_roster_invite_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'invite_id')::uuid; end if;
  insert into core.roster_invites(club_id,club_person_id,token_hash,expires_at,created_by) values(target_club_id,target_club_person_id,extensions.digest(raw_token,'sha256'),expires_at,actor_id) returning id into invite_id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'roster.invite.issue.v1',jsonb_build_object('invite_id',invite_id));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision) values(target_club_id,actor_id,'roster.invite.issue.v1','roster_invite',invite_id,1);
  return invite_id;
end;
$$;

create function internal.claim_club_person_for_actor(raw_token text, idempotency_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); invite_row core.roster_invites%rowtype; existing_result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select result into existing_result from internal.command_deduplication where actor_profile_id=actor_id and command_type='roster.person.claim.v1' and internal.command_deduplication.idempotency_key=claim_club_person_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'club_person_id')::uuid; end if;
  select * into invite_row from core.roster_invites where token_hash=extensions.digest(raw_token,'sha256') for update;
  if invite_row.id is null or invite_row.state<>'issued' or invite_row.expires_at<=now() then raise invalid_parameter_value using message='invalid_or_expired_token'; end if;
  if exists(select 1 from core.person_account_links where club_person_id=invite_row.club_person_id and state='active') then raise unique_violation using message='claim_conflict'; end if;
  insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at,created_by) values(invite_row.club_id,invite_row.club_person_id,actor_id,'active',now(),actor_id);
  update core.roster_invites set state='consumed',consumed_at=now(),consumed_by=actor_id,revision=revision+1 where id=invite_row.id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'roster.person.claim.v1',jsonb_build_object('club_person_id',invite_row.club_person_id));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision) values(invite_row.club_id,actor_id,'roster.person.claim.v1','club_person',invite_row.club_person_id,1);
  return invite_row.club_person_id;
end;
$$;

create function internal.end_team_assignment_for_actor(target_assignment_id uuid, expected_revision bigint, idempotency_key uuid)
returns bigint language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); row_value core.team_assignments%rowtype; existing_result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select result into existing_result from internal.command_deduplication where actor_profile_id=actor_id and command_type='roster.assignment.end.v1' and internal.command_deduplication.idempotency_key=end_team_assignment_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'revision')::bigint; end if;
  select * into row_value from core.team_assignments where id=target_assignment_id for update;
  if row_value.id is null or not internal.actor_has_capability(row_value.club_id,row_value.team_id,'club.memberships.manage') then raise insufficient_privilege using message='not_found'; end if;
  if row_value.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
  if row_value.state<>'active' then raise check_violation using message='invalid_transition'; end if;
  update core.team_assignments set state='ended',ends_at=greatest(now(),starts_at+interval '1 microsecond'),ended_by=actor_id,revision=revision+1 where id=row_value.id returning revision into expected_revision;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'roster.assignment.end.v1',jsonb_build_object('revision',expected_revision));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision) values(row_value.club_id,actor_id,'roster.assignment.end.v1','team_assignment',row_value.id,expected_revision);
  return expected_revision;
end;
$$;

create function internal.set_guardian_relation_for_actor()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
  raise feature_not_supported using message='guardian_policy_not_configured';
end;
$$;

create function internal.request_transfer_for_actor(source_club_person_id uuid, source_team_id uuid,
  target_club_id uuid, target_team_id uuid, effective_at timestamptz, idempotency_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); source_row core.club_people%rowtype; transfer_id uuid; existing_result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select * into source_row from core.club_people where id=source_club_person_id and status='active';
  if source_row.id is null or not internal.actor_has_capability(source_row.club_id,source_team_id,'club.memberships.manage') then raise insufficient_privilege using message='not_found'; end if;
  if source_row.club_id=target_club_id or effective_at<=now() or not exists(select 1 from core.teams where id=source_team_id and club_id=source_row.club_id and status='active') or not exists(select 1 from core.teams where id=target_team_id and club_id=target_club_id and status='active') then raise invalid_parameter_value using message='invalid_input'; end if;
  select result into existing_result from internal.command_deduplication where actor_profile_id=actor_id and command_type='roster.transfer.request.v1' and internal.command_deduplication.idempotency_key=request_transfer_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'transfer_id')::uuid; end if;
  if exists(select 1 from core.transfer_cases where person_id=source_row.person_id and state in ('requested','approved')) then raise unique_violation using message='transfer_conflict'; end if;
  insert into core.transfer_cases(person_id,source_club_id,source_team_id,source_club_person_id,target_club_id,target_team_id,effective_at,created_by)
  values(source_row.person_id,source_row.club_id,source_team_id,source_row.id,target_club_id,target_team_id,effective_at,actor_id) returning id into transfer_id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'roster.transfer.request.v1',jsonb_build_object('transfer_id',transfer_id));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision) values(source_row.club_id,actor_id,'roster.transfer.request.v1','transfer_case',transfer_id,1);
  return transfer_id;
end;
$$;

create function internal.decide_transfer_for_actor(target_transfer_id uuid, decision text, reason text, expected_revision bigint, idempotency_key uuid)
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

create function internal.complete_transfer_for_actor(target_transfer_id uuid, expected_revision bigint, idempotency_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); transfer_row core.transfer_cases%rowtype; source_person core.club_people%rowtype; target_person_id uuid; existing_result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select result into existing_result from internal.command_deduplication where actor_profile_id=actor_id and command_type='roster.transfer.complete.v1' and internal.command_deduplication.idempotency_key=complete_transfer_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'club_person_id')::uuid; end if;
  select * into transfer_row from core.transfer_cases where id=target_transfer_id for update;
  if transfer_row.id is null or not internal.actor_has_capability(transfer_row.target_club_id,transfer_row.target_team_id,'club.memberships.manage') then raise insufficient_privilege using message='not_found'; end if;
  if transfer_row.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
  if transfer_row.state<>'approved' or transfer_row.effective_at>now() then raise check_violation using message='invalid_transition'; end if;
  if (select count(*) from audit.transfer_approvals where transfer_case_id=transfer_row.id and transfer_revision=transfer_row.revision-1 and decision='approved')<>2 then raise insufficient_privilege using message='approval_required'; end if;
  select * into source_person from core.club_people where id=transfer_row.source_club_person_id and club_id=transfer_row.source_club_id;
  update core.team_assignments set state='ended',ends_at=transfer_row.effective_at,ended_by=actor_id,revision=revision+1 where club_person_id=source_person.id and team_id=transfer_row.source_team_id and state='active' and starts_at<transfer_row.effective_at;
  select id into target_person_id from core.club_people where person_id=transfer_row.person_id and club_id=transfer_row.target_club_id;
  if target_person_id is null then insert into core.club_people(club_id,person_id,display_name,age_class,safeguarding_required,provenance,created_by) values(transfer_row.target_club_id,transfer_row.person_id,source_person.display_name,source_person.age_class,source_person.safeguarding_required,'transfer',actor_id) returning id into target_person_id; end if;
  insert into core.team_assignments(club_id,team_id,club_person_id,starts_at,created_by) values(transfer_row.target_club_id,transfer_row.target_team_id,target_person_id,transfer_row.effective_at,actor_id);
  update core.transfer_cases set state='completed',completed_club_person_id=target_person_id,revision=revision+1 where id=transfer_row.id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'roster.transfer.complete.v1',jsonb_build_object('club_person_id',target_person_id));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata) values(transfer_row.target_club_id,actor_id,'roster.transfer.complete.v1','transfer_case',transfer_row.id,transfer_row.revision+1,jsonb_build_object('source_club_id',transfer_row.source_club_id,'target_club_id',transfer_row.target_club_id,'club_person_id',target_person_id));
  return target_person_id;
end;
$$;

alter table core.persons enable row level security;
alter table core.team_assignments enable row level security;
alter table core.play_eligibilities enable row level security;
alter table core.guardian_relations enable row level security;
alter table core.roster_invites enable row level security;
alter table core.transfer_cases enable row level security;
alter table audit.transfer_approvals enable row level security;

create policy persons_select_own on core.persons for select to authenticated using (exists(select 1 from core.club_people cp join core.person_account_links link on link.club_person_id=cp.id and link.club_id=cp.club_id where cp.person_id=persons.id and link.profile_id=(select auth.uid()) and link.state='active'));
create policy team_assignments_select_relation on core.team_assignments for select to authenticated using ((select internal.actor_has_club_access(club_id)));
create policy play_eligibilities_select_relation on core.play_eligibilities for select to authenticated using ((select internal.actor_has_club_access(club_id)));
create policy guardian_relations_select_subject on core.guardian_relations for select to authenticated using (exists(select 1 from core.person_account_links link where link.club_id=guardian_relations.club_id and link.club_person_id in (guardian_relations.guardian_person_id,guardian_relations.child_person_id) and link.profile_id=(select auth.uid()) and link.state='active'));
create policy transfer_cases_select_relation on core.transfer_cases for select to authenticated using ((select internal.actor_has_club_access(source_club_id)) or (select internal.actor_has_club_access(target_club_id)));

revoke all on all tables in schema core, audit from public, anon, authenticated;
revoke all on all sequences in schema core, audit from public, anon, authenticated;
revoke all on function internal.actor_has_capability(uuid,uuid,text), internal.enforce_team_assignment_period(), internal.list_club_people_for_actor(uuid,uuid), internal.create_roster_person_for_actor(uuid,uuid,text,text,timestamptz,uuid), internal.issue_roster_invite_for_actor(uuid,text,timestamptz,uuid), internal.claim_club_person_for_actor(text,uuid), internal.end_team_assignment_for_actor(uuid,bigint,uuid), internal.set_guardian_relation_for_actor(), internal.request_transfer_for_actor(uuid,uuid,uuid,uuid,timestamptz,uuid), internal.decide_transfer_for_actor(uuid,text,text,bigint,uuid), internal.complete_transfer_for_actor(uuid,bigint,uuid) from public, anon, authenticated;
grant execute on function internal.list_club_people_for_actor(uuid,uuid), internal.create_roster_person_for_actor(uuid,uuid,text,text,timestamptz,uuid), internal.issue_roster_invite_for_actor(uuid,text,timestamptz,uuid), internal.claim_club_person_for_actor(text,uuid), internal.end_team_assignment_for_actor(uuid,bigint,uuid), internal.set_guardian_relation_for_actor(), internal.request_transfer_for_actor(uuid,uuid,uuid,uuid,timestamptz,uuid), internal.decide_transfer_for_actor(uuid,text,text,bigint,uuid), internal.complete_transfer_for_actor(uuid,bigint,uuid) to authenticated;

create function api.list_club_people(target_club_id uuid,target_team_id uuid default null)
returns table(club_person_id uuid,display_name text,age_class text,safeguarding_required boolean,team_id uuid,team_name text,assignment_state text,assignment_starts_at timestamptz,assignment_ends_at timestamptz)
language sql stable security invoker set search_path='' as $$ select * from internal.list_club_people_for_actor(target_club_id,target_team_id); $$;
create function api.create_roster_person(target_club_id uuid,target_team_id uuid,display_name text,age_class text,starts_at timestamptz,idempotency_key uuid) returns uuid language sql security invoker set search_path='' as $$ select internal.create_roster_person_for_actor(target_club_id,target_team_id,display_name,age_class,starts_at,idempotency_key); $$;
create function api.issue_roster_invite(target_club_person_id uuid,raw_token text,expires_at timestamptz,idempotency_key uuid) returns uuid language sql security invoker set search_path='' as $$ select internal.issue_roster_invite_for_actor(target_club_person_id,raw_token,expires_at,idempotency_key); $$;
create function api.claim_club_person(raw_token text,idempotency_key uuid) returns uuid language sql security invoker set search_path='' as $$ select internal.claim_club_person_for_actor(raw_token,idempotency_key); $$;
create function api.end_team_assignment(target_assignment_id uuid,expected_revision bigint,idempotency_key uuid) returns bigint language sql security invoker set search_path='' as $$ select internal.end_team_assignment_for_actor(target_assignment_id,expected_revision,idempotency_key); $$;
create function api.set_guardian_relation() returns void language sql security invoker set search_path='' as $$ select internal.set_guardian_relation_for_actor(); $$;
create function api.request_transfer(source_club_person_id uuid,source_team_id uuid,target_club_id uuid,target_team_id uuid,effective_at timestamptz,idempotency_key uuid) returns uuid language sql security invoker set search_path='' as $$ select internal.request_transfer_for_actor(source_club_person_id,source_team_id,target_club_id,target_team_id,effective_at,idempotency_key); $$;
create function api.decide_transfer(transfer_id uuid,decision text,reason text,expected_revision bigint,idempotency_key uuid) returns bigint language sql security invoker set search_path='' as $$ select internal.decide_transfer_for_actor(transfer_id,decision,reason,expected_revision,idempotency_key); $$;
create function api.complete_transfer(transfer_id uuid,expected_revision bigint,idempotency_key uuid) returns uuid language sql security invoker set search_path='' as $$ select internal.complete_transfer_for_actor(transfer_id,expected_revision,idempotency_key); $$;

revoke all on function api.list_club_people(uuid,uuid), api.create_roster_person(uuid,uuid,text,text,timestamptz,uuid), api.issue_roster_invite(uuid,text,timestamptz,uuid), api.claim_club_person(text,uuid), api.end_team_assignment(uuid,bigint,uuid), api.set_guardian_relation(), api.request_transfer(uuid,uuid,uuid,uuid,timestamptz,uuid), api.decide_transfer(uuid,text,text,bigint,uuid), api.complete_transfer(uuid,bigint,uuid) from public, anon;
grant execute on function api.list_club_people(uuid,uuid), api.create_roster_person(uuid,uuid,text,text,timestamptz,uuid), api.issue_roster_invite(uuid,text,timestamptz,uuid), api.claim_club_person(text,uuid), api.end_team_assignment(uuid,bigint,uuid), api.set_guardian_relation(), api.request_transfer(uuid,uuid,uuid,uuid,timestamptz,uuid), api.decide_transfer(uuid,text,text,bigint,uuid), api.complete_transfer(uuid,bigint,uuid) to authenticated;

insert into internal.migration_provenance(migration_name) values('20260807220144_s02_roster_lifecycle');
notify pgrst, 'reload schema';
