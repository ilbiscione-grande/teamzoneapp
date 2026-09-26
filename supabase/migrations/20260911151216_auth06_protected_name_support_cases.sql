-- AUTH-06: protected-name review cases before a club exists.
-- This is a platform support boundary, deliberately separate from club roles.

create table internal.support_admins (
  profile_id uuid primary key references core.profiles(id),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  revoked_at timestamptz,
  check ((active and revoked_at is null) or (not active and revoked_at is not null))
);

create table internal.protected_name_support_cases (
  id uuid primary key default gen_random_uuid(),
  requester_profile_id uuid not null references core.profiles(id),
  candidate_club_name text not null check (length(btrim(candidate_club_name)) between 2 and 120),
  candidate_team_name text not null check (length(btrim(candidate_team_name)) between 1 and 120),
  normalized_club_name text not null,
  message text not null check (length(btrim(message)) between 20 and 1000),
  status text not null default 'pending'
    check (status in ('pending','in_review','resolved','rejected')),
  idempotency_key uuid not null,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  handled_by uuid references core.profiles(id),
  resolution_note text,
  unique (requester_profile_id,idempotency_key),
  check (
    (status in ('pending','in_review') and resolved_at is null)
    or (status in ('resolved','rejected') and resolved_at is not null
      and handled_by is not null and length(btrim(resolution_note)) between 5 and 1000)
  )
);

create index protected_name_support_cases_queue_idx
  on internal.protected_name_support_cases(status,created_at,id);
create index protected_name_support_cases_requester_idx
  on internal.protected_name_support_cases(requester_profile_id,created_at desc,id desc);

alter table internal.support_admins enable row level security;
alter table internal.protected_name_support_cases enable row level security;
revoke all on table internal.support_admins,internal.protected_name_support_cases
  from public,anon,authenticated;

create function internal.actor_is_support_admin()
returns boolean language sql stable security definer set search_path=''
as $$
  select auth.uid() is not null and exists(
    select 1 from internal.support_admins admin_row
    where admin_row.profile_id=auth.uid() and admin_row.active
  )
$$;

create function internal.submit_protected_name_support_case_for_actor(
  candidate_club_name text,candidate_team_name text,message text,idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); case_id uuid; existing_id uuid;
 normalized_club text:=btrim(candidate_club_name); normalized_team text:=btrim(candidate_team_name);
 normalized_message text:=btrim(message); name_check jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if length(normalized_club) not between 2 and 120
     or length(normalized_team) not between 1 and 120
     or length(normalized_message) not between 20 and 1000 then
    raise invalid_parameter_value using message='invalid_support_case';
  end if;

  select row_value.id into existing_id
  from internal.protected_name_support_cases row_value
  where row_value.requester_profile_id=actor_id
    and row_value.idempotency_key=submit_protected_name_support_case_for_actor.idempotency_key;
  if existing_id is not null then return existing_id; end if;

  name_check:=internal.check_club_name_for_actor(normalized_club);
  if name_check->>'status'<>'review_required' then
    raise invalid_parameter_value using message='review_not_required';
  end if;

  insert into internal.protected_name_support_cases(
    requester_profile_id,candidate_club_name,candidate_team_name,
    normalized_club_name,message,idempotency_key
  ) values(
    actor_id,normalized_club,normalized_team,
    internal.normalize_club_name(normalized_club),normalized_message,idempotency_key
  ) returning id into case_id;

  insert into audit.command_events(
    actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata
  ) values(
    actor_id,'support.protected_name.request.v1','protected_name_support_case',case_id,1,
    jsonb_build_object('candidate_club_name',normalized_club,'candidate_team_name',normalized_team)
  );
  return case_id;
end
$$;

create function internal.list_my_protected_name_support_cases_for_actor()
returns table(
  case_id uuid,candidate_club_name text,candidate_team_name text,status text,
  message text,resolution_note text,created_at timestamptz,updated_at timestamptz
) language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  return query select row_value.id,row_value.candidate_club_name,row_value.candidate_team_name,
    row_value.status,row_value.message,row_value.resolution_note,row_value.created_at,row_value.updated_at
  from internal.protected_name_support_cases row_value
  where row_value.requester_profile_id=actor_id
  order by row_value.created_at desc,row_value.id desc;
end
$$;

create function internal.list_protected_name_support_cases_for_admin(
  requested_status text default null
)
returns table(
  case_id uuid,requester_profile_id uuid,candidate_club_name text,candidate_team_name text,
  status text,message text,resolution_note text,revision bigint,created_at timestamptz,updated_at timestamptz
) language plpgsql stable security definer set search_path=''
as $$
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message='not_found';
  end if;
  if requested_status is not null and requested_status not in ('pending','in_review','resolved','rejected') then
    raise invalid_parameter_value using message='invalid_status';
  end if;
  return query select row_value.id,row_value.requester_profile_id,row_value.candidate_club_name,
    row_value.candidate_team_name,row_value.status,row_value.message,row_value.resolution_note,
    row_value.revision,row_value.created_at,row_value.updated_at
  from internal.protected_name_support_cases row_value
  where requested_status is null or row_value.status=requested_status
  order by case when row_value.status='pending' then 0 when row_value.status='in_review' then 1 else 2 end,
    row_value.created_at,row_value.id;
end
$$;

create function internal.update_protected_name_support_case_for_admin(
  target_case_id uuid,new_status text,case_resolution_note text,expected_revision bigint,idempotency_key uuid
)
returns bigint language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); row_value internal.protected_name_support_cases%rowtype;
 existing_result jsonb; next_revision bigint;
begin
  if actor_id is null or not internal.actor_is_support_admin() then
    raise insufficient_privilege using message='not_found';
  end if;
  if new_status not in ('in_review','resolved','rejected')
     or (new_status in ('resolved','rejected') and length(btrim(case_resolution_note)) not between 5 and 1000) then
    raise invalid_parameter_value using message='invalid_decision';
  end if;
  select result into existing_result from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='support.protected_name.update.v1'
    and internal.command_deduplication.idempotency_key=update_protected_name_support_case_for_admin.idempotency_key;
  if existing_result is not null then return (existing_result->>'revision')::bigint; end if;

  select * into row_value from internal.protected_name_support_cases
  where id=target_case_id for update;
  if row_value.id is null then raise invalid_parameter_value using message='not_found'; end if;
  if row_value.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
  if row_value.status in ('resolved','rejected') then raise invalid_parameter_value using message='invalid_status'; end if;

  next_revision:=row_value.revision+1;
  update internal.protected_name_support_cases set
    status=new_status,revision=next_revision,updated_at=now(),handled_by=actor_id,
    resolution_note=case when new_status in ('resolved','rejected') then btrim(case_resolution_note) else null end,
    resolved_at=case when new_status in ('resolved','rejected') then now() else null end
  where id=row_value.id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'support.protected_name.update.v1',jsonb_build_object('revision',next_revision));
  insert into audit.command_events(
    actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,reason,metadata
  ) values(
    actor_id,'support.protected_name.update.v1','protected_name_support_case',row_value.id,next_revision,
    nullif(btrim(case_resolution_note),''),jsonb_build_object('status',new_status)
  );
  return next_revision;
end
$$;

create function api.submit_protected_name_support_case(
  candidate_club_name text,candidate_team_name text,message text,idempotency_key uuid
) returns uuid language sql security invoker set search_path=''
as $$select internal.submit_protected_name_support_case_for_actor(candidate_club_name,candidate_team_name,message,idempotency_key)$$;
create function api.list_my_protected_name_support_cases()
returns table(case_id uuid,candidate_club_name text,candidate_team_name text,status text,message text,
  resolution_note text,created_at timestamptz,updated_at timestamptz)
language sql stable security invoker set search_path=''
as $$select * from internal.list_my_protected_name_support_cases_for_actor()$$;
create function api.list_protected_name_support_cases(requested_status text default null)
returns table(case_id uuid,requester_profile_id uuid,candidate_club_name text,candidate_team_name text,
  status text,message text,resolution_note text,revision bigint,created_at timestamptz,updated_at timestamptz)
language sql stable security invoker set search_path=''
as $$select * from internal.list_protected_name_support_cases_for_admin(requested_status)$$;
create function api.update_protected_name_support_case(
  target_case_id uuid,new_status text,case_resolution_note text,expected_revision bigint,idempotency_key uuid
) returns bigint language sql security invoker set search_path=''
as $$select internal.update_protected_name_support_case_for_admin(target_case_id,new_status,case_resolution_note,expected_revision,idempotency_key)$$;

revoke all on function internal.actor_is_support_admin(),
  internal.submit_protected_name_support_case_for_actor(text,text,text,uuid),
  internal.list_my_protected_name_support_cases_for_actor(),
  internal.list_protected_name_support_cases_for_admin(text),
  internal.update_protected_name_support_case_for_admin(uuid,text,text,bigint,uuid)
from public,anon,authenticated;
revoke all on function api.submit_protected_name_support_case(text,text,text,uuid),
  api.list_my_protected_name_support_cases(),api.list_protected_name_support_cases(text),
  api.update_protected_name_support_case(uuid,text,text,bigint,uuid)
from public,anon,authenticated;
grant execute on function internal.submit_protected_name_support_case_for_actor(text,text,text,uuid),
  internal.list_my_protected_name_support_cases_for_actor(),
  internal.list_protected_name_support_cases_for_admin(text),
  internal.update_protected_name_support_case_for_admin(uuid,text,text,bigint,uuid)
to authenticated;
grant execute on function api.submit_protected_name_support_case(text,text,text,uuid),
  api.list_my_protected_name_support_cases(),api.list_protected_name_support_cases(text),
  api.update_protected_name_support_case(uuid,text,text,bigint,uuid)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260911151216_auth06_protected_name_support_cases','greenfield',
  'AUTH-06 protected-name support cases with explicit platform support-admin boundary');
