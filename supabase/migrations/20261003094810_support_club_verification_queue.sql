-- Support administrators handle official-club verification from the same
-- desktop queue as the other platform support cases. Email delivery uses a
-- separate outbox and never copies evidence or contact details into a mail.

create table internal.support_email_outbox (
  id uuid primary key default gen_random_uuid(),
  case_type text not null check (case_type in (
    'club_verification','protected_name','login_email_change','person_erasure'
  )),
  case_id uuid not null,
  case_revision bigint not null default 1 check (case_revision > 0),
  state text not null default 'pending'
    check (state in ('pending','processing','delivered','failed','dead_letter')),
  available_at timestamptz not null default now(),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error_code text,
  provider_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(case_type,case_id,case_revision)
);
create index support_email_outbox_claim_idx
  on internal.support_email_outbox(state,available_at,created_at,id)
  where state in ('pending','failed');
alter table internal.support_email_outbox enable row level security;
revoke all on table internal.support_email_outbox from public,anon,authenticated;

create function internal.enqueue_support_email()
returns trigger language plpgsql security definer set search_path=''
as $$
declare next_type text; next_revision bigint;
begin
  next_type:=case tg_table_name
    when 'club_verification_requests' then 'club_verification'
    when 'protected_name_support_cases' then 'protected_name'
    when 'login_email_change_requests' then 'login_email_change'
    when 'global_person_erasure_requests' then 'person_erasure'
  end;
  next_revision:=coalesce((to_jsonb(new)->>'revision')::bigint,1);
  insert into internal.support_email_outbox(case_type,case_id,case_revision)
  values(next_type,new.id,next_revision)
  on conflict(case_type,case_id,case_revision) do nothing;
  return new;
end
$$;

create trigger club_verification_requests_support_email
after insert on core.club_verification_requests
for each row execute function internal.enqueue_support_email();
create trigger protected_name_support_cases_support_email
after insert on internal.protected_name_support_cases
for each row execute function internal.enqueue_support_email();
create trigger login_email_change_requests_support_email
after insert on core.login_email_change_requests
for each row execute function internal.enqueue_support_email();
create trigger global_person_erasure_requests_support_email
after insert on internal.global_person_erasure_requests
for each row execute function internal.enqueue_support_email();

create function internal.list_club_verification_requests_for_admin(
  requested_status text default null
)
returns table(
  request_id uuid,club_id uuid,club_name text,requester_name text,
  evidence_summary text,status text,created_at timestamptz,resolved_at timestamptz,
  decision_reason text,revision bigint
)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message='not_found';
  end if;
  if requested_status is not null and requested_status not in ('pending','approved','rejected','withdrawn') then
    raise invalid_parameter_value using message='invalid_status';
  end if;
  return query
    select request.id,request.club_id,club.name,profile.display_name,
      request.evidence_summary,request.status,request.created_at,request.resolved_at,
      request.decision_reason,request.revision
    from core.club_verification_requests request
    join core.clubs club on club.id=request.club_id
    join core.profiles profile on profile.id=request.requested_by
    where requested_status is null or request.status=requested_status
    order by case when request.status='pending' then 0 else 1 end,
      request.created_at,request.id;
end
$$;

create function internal.decide_club_verification_for_admin(
  target_request_id uuid,approve boolean,case_decision_reason text,
  expected_revision bigint,idempotency_key uuid
)
returns bigint language plpgsql security definer set search_path=''
as $$
declare
  actor_id uuid:=auth.uid();
  row_value core.club_verification_requests%rowtype;
  club_name text;
  decision text:=case when approve then 'approved' else 'rejected' end;
  existing_result jsonb;
  next_revision bigint;
begin
  if actor_id is null or not internal.actor_is_support_admin() then
    raise insufficient_privilege using message='not_found';
  end if;
  if idempotency_key is null or length(btrim(coalesce(case_decision_reason,''))) not between 5 and 1000 then
    raise invalid_parameter_value using message='invalid_decision';
  end if;
  select result into existing_result
  from internal.command_deduplication
  where actor_profile_id=actor_id
    and command_type='support.club_verification.decide.v1'
    and internal.command_deduplication.idempotency_key=decide_club_verification_for_admin.idempotency_key;
  if existing_result is not null then
    return (existing_result->>'revision')::bigint;
  end if;

  select * into row_value from core.club_verification_requests
  where id=target_request_id for update;
  if row_value.id is null then raise invalid_parameter_value using message='not_found'; end if;
  if row_value.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
  if row_value.status<>'pending' then raise invalid_parameter_value using message='invalid_status'; end if;

  select name into club_name from core.clubs where id=row_value.club_id for update;
  next_revision:=row_value.revision+1;
  update core.club_verification_requests set
    status=decision,resolved_at=now(),reviewer_reference=actor_id::text,
    decision_reason=btrim(case_decision_reason),revision=next_revision
  where id=row_value.id;
  update core.clubs set
    verification_status=case when approve then 'official' else 'rejected' end,
    revision=revision+1
  where id=row_value.club_id;
  if approve then
    insert into internal.protected_club_names(normalized_name,canonical_name,club_id,state,source,created_by)
    values(internal.normalize_club_name(club_name),club_name,row_value.club_id,'active','official_club',actor_id)
    on conflict(normalized_name) do update set
      canonical_name=excluded.canonical_name,club_id=excluded.club_id,state='active',
      source='official_club',revision=internal.protected_club_names.revision+1;
  end if;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'support.club_verification.decide.v1',jsonb_build_object('revision',next_revision));
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
    aggregate_revision,reason,metadata
  ) values(
    row_value.club_id,actor_id,'support.club_verification.decide.v1',
    'club_verification_request',row_value.id,next_revision,btrim(case_decision_reason),
    jsonb_build_object('decision',decision)
  );
  return next_revision;
end
$$;

create function internal.claim_support_email_batch(batch_size integer default 20)
returns table(
  outbox_id uuid,case_type text,case_id uuid,attempt_count integer,
  received_at timestamptz,recipient_emails text[]
)
language plpgsql security definer set search_path=''
as $$
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise insufficient_privilege using message='service_role_required';
  end if;
  return query
  with recipients as (
    select coalesce(array_agg(user_row.email::text order by user_row.email)
      filter(where user_row.email is not null),array[]::text[]) emails
    from internal.support_admins admin
    join auth.users user_row on user_row.id=admin.profile_id
    where admin.active
  ), claimed as (
    select queue.id from internal.support_email_outbox queue
    where queue.state in ('pending','failed') and queue.available_at<=now()
      and queue.attempt_count<5
    order by queue.created_at,queue.id
    for update skip locked limit greatest(1,least(batch_size,100))
  ), updated as (
    update internal.support_email_outbox queue set
      state='processing',attempt_count=queue.attempt_count+1,updated_at=now()
    from claimed where queue.id=claimed.id
    returning queue.id,queue.case_type,queue.case_id,queue.attempt_count,queue.created_at
  )
  select updated.id,updated.case_type,updated.case_id,updated.attempt_count,
    updated.created_at,recipients.emails
  from updated cross join recipients;
end
$$;

create function internal.finish_support_email_attempt(
  target_outbox_id uuid,next_state text,error_code text default null,
  target_provider_reference text default null
)
returns void language plpgsql security definer set search_path=''
as $$
declare attempts integer;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise insufficient_privilege using message='service_role_required';
  end if;
  if next_state not in ('delivered','failed','dead_letter') then
    raise invalid_parameter_value using message='invalid_state';
  end if;
  select attempt_count into attempts from internal.support_email_outbox
  where id=target_outbox_id and state='processing' for update;
  if attempts is null then raise invalid_parameter_value using message='not_found'; end if;
  update internal.support_email_outbox set
    state=case when next_state='failed' and attempts>=5 then 'dead_letter' else next_state end,
    available_at=case when next_state='failed'
      then now()+make_interval(mins=>least(60,power(2,attempts)::integer))
      else available_at end,
    last_error_code=nullif(left(coalesce(error_code,''),120),''),
    provider_reference=nullif(left(coalesce(target_provider_reference,''),240),''),
    updated_at=now()
  where id=target_outbox_id;
end
$$;

create function api.list_club_verification_requests(requested_status text default null)
returns table(
  request_id uuid,club_id uuid,club_name text,requester_name text,
  evidence_summary text,status text,created_at timestamptz,resolved_at timestamptz,
  decision_reason text,revision bigint
)
language sql stable security invoker set search_path=''
as $$select * from internal.list_club_verification_requests_for_admin(requested_status)$$;

create function api.decide_club_verification_request(
  target_request_id uuid,approve boolean,case_decision_reason text,
  expected_revision bigint,idempotency_key uuid
)
returns bigint language sql security invoker set search_path=''
as $$select internal.decide_club_verification_for_admin(
  target_request_id,approve,case_decision_reason,expected_revision,idempotency_key
)$$;

create function api.claim_support_email_batch(batch_size integer default 20)
returns table(
  outbox_id uuid,case_type text,case_id uuid,attempt_count integer,
  received_at timestamptz,recipient_emails text[]
)
language sql security invoker set search_path=''
as $$select * from internal.claim_support_email_batch(batch_size)$$;

create function api.finish_support_email_attempt(
  target_outbox_id uuid,next_state text,error_code text default null,
  target_provider_reference text default null
)
returns void language sql security invoker set search_path=''
as $$select internal.finish_support_email_attempt(
  target_outbox_id,next_state,error_code,target_provider_reference
)$$;

revoke all on function internal.enqueue_support_email(),
  internal.list_club_verification_requests_for_admin(text),
  internal.decide_club_verification_for_admin(uuid,boolean,text,bigint,uuid),
  internal.claim_support_email_batch(integer),
  internal.finish_support_email_attempt(uuid,text,text,text),
  api.list_club_verification_requests(text),
  api.decide_club_verification_request(uuid,boolean,text,bigint,uuid),
  api.claim_support_email_batch(integer),
  api.finish_support_email_attempt(uuid,text,text,text)
from public,anon,authenticated;

grant execute on function
  internal.list_club_verification_requests_for_admin(text),
  internal.decide_club_verification_for_admin(uuid,boolean,text,bigint,uuid),
  api.list_club_verification_requests(text),
  api.decide_club_verification_request(uuid,boolean,text,bigint,uuid)
to authenticated;
grant execute on function
  internal.claim_support_email_batch(integer),
  internal.finish_support_email_attempt(uuid,text,text,text),
  api.claim_support_email_batch(integer),
  api.finish_support_email_attempt(uuid,text,text,text)
to service_role;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261003094810_support_club_verification_queue','greenfield',
  'Unified official-club support review and privacy-minimal support email outbox');

notify pgrst,'reload schema';
