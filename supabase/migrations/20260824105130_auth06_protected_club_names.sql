-- AUTH-06 protected names and TeamZone-only official status decisions.

create table internal.protected_club_names (
  normalized_name text primary key check (length(normalized_name) between 2 and 160),
  canonical_name text not null check (length(btrim(canonical_name)) between 2 and 120),
  club_id uuid references core.clubs(id),
  state text not null default 'active' check (state in ('active','released')),
  source text not null check (source in ('system','official_club','manual_review')),
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0)
);

create table core.club_verification_requests (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  requested_by uuid not null references core.profiles(id),
  evidence_summary text not null check (length(btrim(evidence_summary)) between 20 and 1000),
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','withdrawn')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  reviewer_reference text,
  decision_reason text,
  revision bigint not null default 1 check (revision > 0),
  check ((status='pending' and resolved_at is null)
    or (status in ('approved','rejected') and resolved_at is not null)
    or status='withdrawn')
);
create unique index club_verification_requests_one_pending
  on core.club_verification_requests(club_id) where status='pending';
create index club_verification_requests_requester_created
  on core.club_verification_requests(requested_by,created_at desc,id desc);

alter table internal.protected_club_names enable row level security;
alter table core.club_verification_requests enable row level security;
revoke all on table internal.protected_club_names,core.club_verification_requests
  from public,anon,authenticated;

create function internal.normalize_club_name(value text)
returns text language plpgsql immutable strict set search_path=''
as $$
declare result text:=lower(btrim(value));
begin
  result:=replace(replace(replace(result,'å','a'),'ä','a'),'ö','o');
  result:=replace(replace(replace(result,'á','a'),'à','a'),'â','a');
  result:=replace(replace(result,'é','e'),'è','e');
  result:=replace(result,'ü','u');
  -- Common Cyrillic homoglyphs are folded before punctuation/space removal.
  result:=replace(replace(replace(replace(replace(result,'а','a'),'е','e'),'о','o'),'р','p'),'с','c');
  result:=replace(replace(replace(result,'х','x'),'у','y'),'к','k');
  return regexp_replace(result,'[^a-z0-9]','','g');
end
$$;

insert into internal.protected_club_names(normalized_name,canonical_name,state,source)
values(internal.normalize_club_name('TeamZone'),'TeamZone','active','system');

create function internal.enforce_protected_club_name()
returns trigger language plpgsql security definer set search_path=''
as $$
declare protected_club_id uuid;
begin
  select protected.club_id into protected_club_id
  from internal.protected_club_names protected
  where protected.normalized_name=internal.normalize_club_name(new.name)
    and protected.state='active';
  if found and (protected_club_id is null or protected_club_id<>new.id) then
    raise unique_violation using message='club_name_requires_review';
  end if;
  return new;
end
$$;
create trigger clubs_enforce_protected_name
before insert or update of name on core.clubs
for each row execute function internal.enforce_protected_club_name();

create function internal.check_club_name_for_actor(candidate_name text)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); normalized text; protected boolean; collision boolean;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if length(btrim(candidate_name)) not between 2 and 120 then
    return jsonb_build_object('status','invalid');
  end if;
  normalized:=internal.normalize_club_name(candidate_name);
  if length(normalized)<2 then return jsonb_build_object('status','invalid'); end if;
  select exists(select 1 from internal.protected_club_names row_value
    where row_value.normalized_name=normalized and row_value.state='active') into protected;
  select exists(select 1 from core.clubs club
    where internal.normalize_club_name(club.name)=normalized and club.status='active') into collision;
  if protected or collision then
    return jsonb_build_object('status','review_required');
  end if;
  return jsonb_build_object('status','available');
end
$$;

create function internal.request_club_verification_for_actor(
  target_club_id uuid,evidence_summary text,idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); request_id uuid; existing_result jsonb; normalized_evidence text:=btrim(evidence_summary);
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id,null,'club.memberships.manage') then
    raise insufficient_privilege using message='not_found';
  end if;
  if length(normalized_evidence) not between 20 and 1000 then
    raise invalid_parameter_value using message='invalid_evidence';
  end if;
  if not exists(select 1 from core.clubs where id=target_club_id
      and status='active' and verification_status in ('unofficial','rejected','revoked')) then
    raise invalid_parameter_value using message='invalid_status';
  end if;
  select result into existing_result from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='club.verification.request.v1'
    and internal.command_deduplication.idempotency_key=request_club_verification_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'request_id')::uuid; end if;
  insert into core.club_verification_requests(club_id,requested_by,evidence_summary)
  values(target_club_id,actor_id,normalized_evidence)
  on conflict(club_id) where status='pending'
  do update set evidence_summary=excluded.evidence_summary,revision=core.club_verification_requests.revision+1
  returning id into request_id;
  update core.clubs set verification_status='pending',revision=revision+1 where id=target_club_id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'club.verification.request.v1',jsonb_build_object('request_id',request_id));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
  values(target_club_id,actor_id,'club.verification.request.v1','club_verification_request',request_id,1);
  return request_id;
end
$$;

create function internal.get_club_verification_status_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); result jsonb;
begin
  if actor_id is null or not internal.actor_has_club_access(target_club_id) then
    raise insufficient_privilege using message='not_found';
  end if;
  select jsonb_build_object(
    'club_id',club.id,'status',club.verification_status,
    'requested_at',request.created_at,'resolved_at',request.resolved_at
  ) into result
  from core.clubs club
  left join lateral(select created_at,resolved_at from core.club_verification_requests
    where club_id=club.id order by created_at desc,id desc limit 1) request on true
  where club.id=target_club_id;
  return coalesce(result,jsonb_build_object('status','unavailable'));
end
$$;

create function internal.decide_club_verification_as_teamzone(
  request_id uuid,decision text,reviewer_reference text,decision_reason text
)
returns void language plpgsql security definer set search_path=''
as $$
declare row_value core.club_verification_requests%rowtype; club_name text;
begin
  if current_user not in ('service_role','postgres') then
    raise insufficient_privilege using message='service_role_required';
  end if;
  if decision not in ('approved','rejected') or length(btrim(reviewer_reference))<3
     or length(btrim(decision_reason))<5 then
    raise invalid_parameter_value using message='invalid_decision';
  end if;
  select * into row_value from core.club_verification_requests
  where id=request_id and status='pending' for update;
  if row_value.id is null then raise invalid_parameter_value using message='not_found'; end if;
  select name into club_name from core.clubs where id=row_value.club_id for update;
  update core.club_verification_requests set status=decision,resolved_at=now(),
    reviewer_reference=btrim(decide_club_verification_as_teamzone.reviewer_reference),
    decision_reason=btrim(decide_club_verification_as_teamzone.decision_reason),revision=revision+1
  where id=row_value.id;
  update core.clubs set verification_status=case when decision='approved' then 'official' else 'rejected' end,
    revision=revision+1 where id=row_value.club_id;
  if decision='approved' then
    insert into internal.protected_club_names(normalized_name,canonical_name,club_id,state,source)
    values(internal.normalize_club_name(club_name),club_name,row_value.club_id,'active','official_club')
    on conflict(normalized_name) do update set canonical_name=excluded.canonical_name,
      club_id=excluded.club_id,state='active',source='official_club',revision=internal.protected_club_names.revision+1;
  end if;
  insert into audit.command_events(club_id,command_type,aggregate_type,aggregate_id,aggregate_revision,reason,metadata)
  values(row_value.club_id,'club.verification.decide.v1','club_verification_request',row_value.id,
    row_value.revision+1,btrim(decision_reason),jsonb_build_object('decision',decision,'reviewer_reference',btrim(reviewer_reference)));
end
$$;

create function internal.revoke_club_official_status_as_teamzone(
  target_club_id uuid,reviewer_reference text,decision_reason text
)
returns void language plpgsql security definer set search_path=''
as $$
declare club_revision bigint;
begin
  if current_user not in ('service_role','postgres') then
    raise insufficient_privilege using message='service_role_required';
  end if;
  if length(btrim(reviewer_reference))<3 or length(btrim(decision_reason))<5 then
    raise invalid_parameter_value using message='invalid_decision';
  end if;
  update core.clubs set verification_status='revoked',revision=revision+1
  where id=target_club_id and verification_status='official'
  returning revision into club_revision;
  if club_revision is null then raise invalid_parameter_value using message='not_found'; end if;
  insert into audit.command_events(club_id,command_type,aggregate_type,aggregate_id,aggregate_revision,reason,metadata)
  values(target_club_id,'club.verification.revoke.v1','club',target_club_id,club_revision,
    btrim(decision_reason),jsonb_build_object('reviewer_reference',btrim(reviewer_reference)));
end
$$;

create function api.check_club_name(candidate_name text)
returns jsonb language sql stable security invoker set search_path=''
as $$select internal.check_club_name_for_actor(candidate_name)$$;
create function api.request_club_verification(target_club_id uuid,evidence_summary text,idempotency_key uuid)
returns uuid language sql security invoker set search_path=''
as $$select internal.request_club_verification_for_actor(target_club_id,evidence_summary,idempotency_key)$$;
create function api.get_club_verification_status(target_club_id uuid)
returns jsonb language sql stable security invoker set search_path=''
as $$select internal.get_club_verification_status_for_actor(target_club_id)$$;
create function api.decide_club_verification(request_id uuid,decision text,reviewer_reference text,decision_reason text)
returns void language sql security invoker set search_path=''
as $$select internal.decide_club_verification_as_teamzone(request_id,decision,reviewer_reference,decision_reason)$$;
create function api.revoke_club_official_status(target_club_id uuid,reviewer_reference text,decision_reason text)
returns void language sql security invoker set search_path=''
as $$select internal.revoke_club_official_status_as_teamzone(target_club_id,reviewer_reference,decision_reason)$$;

revoke all on function internal.normalize_club_name(text),internal.enforce_protected_club_name(),
  internal.check_club_name_for_actor(text),internal.request_club_verification_for_actor(uuid,text,uuid),
  internal.get_club_verification_status_for_actor(uuid),
  internal.decide_club_verification_as_teamzone(uuid,text,text,text),
  internal.revoke_club_official_status_as_teamzone(uuid,text,text) from public,anon,authenticated;
revoke all on function api.check_club_name(text),api.request_club_verification(uuid,text,uuid),
  api.get_club_verification_status(uuid),api.decide_club_verification(uuid,text,text,text),
  api.revoke_club_official_status(uuid,text,text)
from public,anon,authenticated;
grant execute on function internal.check_club_name_for_actor(text),
  internal.request_club_verification_for_actor(uuid,text,uuid),
  internal.get_club_verification_status_for_actor(uuid) to authenticated;
grant execute on function api.check_club_name(text),api.request_club_verification(uuid,text,uuid),
  api.get_club_verification_status(uuid) to authenticated;
grant execute on function internal.decide_club_verification_as_teamzone(uuid,text,text,text),
  api.decide_club_verification(uuid,text,text,text),
  internal.revoke_club_official_status_as_teamzone(uuid,text,text),
  api.revoke_club_official_status(uuid,text,text) to service_role;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260824105130_auth06_protected_club_names','greenfield','AUTH-06 protected names and TeamZone-only official status');
